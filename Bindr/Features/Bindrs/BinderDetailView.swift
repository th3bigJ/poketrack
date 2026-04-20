import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

private struct BinderSlotPickerTarget: Identifiable {
    let id: Int
}

struct BinderDetailView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var binder: Binder
    @Query private var collectionItems: [CollectionItem]

    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var cardsByID: [String: Card] = [:]
    @State private var slotPickerTarget: BinderSlotPickerTarget? = nil
    @State private var showEditTitle = false
    @State private var editingTitle = ""
    @State private var showColourPicker = false
    @State private var currentPage = 0
    @State private var viewingSlot: BinderSlot? = nil
    @State private var isPageTurning = false
    @State private var draggedSlotPosition: Int? = nil
    /// Cached USD price per "cardID|variantKey" — refreshed whenever the slot
    /// set or pricing provider changes. Used by the bottom stats bar to show
    /// a live total value and by the page-info bar for per-page value.
    @State private var slotUSDValues: [String: Double] = [:]

    private var layout: BinderPageLayout { binder.layout }
    private var headerIconColor: Color { colorScheme == .dark ? .white : .black }

    private var sortedSlots: [BinderSlot] {
        binder.slotList.sorted { $0.position < $1.position }
    }

    private var ownedCardIDs: Set<String> {
        Set(collectionItems.map { $0.cardID })
    }

    private var slotsPerPage: Int { layout.slotsPerPage ?? 9 }
    private var cols: Int { layout.columns }
    private var rows: Int { layout.rows }

    private var pageCount: Int {
        let maxPos = sortedSlots.last?.position ?? -1
        return max(1, Int(ceil(Double(maxPos + 1) / Double(slotsPerPage))))
    }

    private func positions(for page: Int) -> [Int] {
        let start = page * slotsPerPage
        return Array(start..<(start + slotsPerPage))
    }

    var body: some View {
        VStack(spacing: 0) {
            binderHeader
            if isEditing {
                editContent
            } else {
                // No top info bar any more — "Page Value" moved into the
                // bottom stats row so the binder itself has more vertical room.
                viewContent
                bottomStatsBar
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .overlay {
            if let slot = viewingSlot, let card = cardsByID[slot.cardID] {
                BinderCardViewer(card: card) {
                    viewingSlot = nil
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewingSlot?.id)
        .onAppear { Task { await loadCards() } }
        .onChange(of: binder.slotList.count) { Task { await loadCards() } }
        .onChange(of: cardsByID.count) { Task { await refreshSlotValues() } }
        .fullScreenCover(item: $slotPickerTarget) { target in
            BinderSlotPickerView(
                brand: binder.tcgBrand,
                startPosition: target.id,
                occupiedPositions: Set(binder.slotList.map(\.position))
            ) { selections in
                fillSlots(startingAt: target.id, selections: selections)
            }
            .environment(services)
        }
        .alert("Rename Binder", isPresented: $showEditTitle) {
            TextField("Name", text: $editingTitle)
            Button("Save") {
                let t = editingTitle.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { binder.title = t }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showColourPicker) {
            BinderStylePickerSheet(binder: binder)
        }
    }

    // MARK: - Header

    private var binderHeader: some View {
        VStack(spacing: 8) {
            ZStack {
                Text(binder.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                HStack {
                    ChromeGlassCircleButton(accessibilityLabel: "Back") { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isEditing.toggle()
                        }
                    } label: {
                        Image(systemName: isEditing ? "checkmark" : "pencil")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(headerIconColor)
                    }
                    .modifier(ChromeGlassCircleGlyphModifier())
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
                    .accessibilityLabel(isEditing ? "Done editing binder" : "Edit binder")
                }
            }
            
            // Premium accent line under title
            Capsule()
                .fill(binder.resolvedColour)
                .frame(width: 40, height: 3)
                .opacity(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Bottom stats bar (Cards · Page Value · Binder Value)

    /// Sits flush at the bottom of the binder page.
    /// The top "Page X of Y / Page value" bar was removed — page value moved
    /// here next to the binder-wide value, and "Add Card" lives on the
    /// header's edit button, so we don't need the pill any more.
    private var bottomStatsBar: some View {
        HStack(spacing: 0) {
            statCell(value: "\(filledCardCount)", label: "CARDS")
            statDivider
            statCell(value: formattedPageValue, label: "PAGE VALUE")
            statDivider
            statCell(value: formattedTotalValue, label: "BINDER VALUE")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Divider().opacity(0.6)
                }
        )
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            Text(label)
                .font(.caption2.weight(.medium))
                .tracking(0.6)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.18))
            .frame(width: 1, height: 26)
    }

    // MARK: - View mode (page-turn)

    private var viewContent: some View {
        GeometryReader { geo in
            ZStack {
                if layout.isFreeScroll {
                    freeScrollView
                } else {
                    pagedViewContent(geo: geo)
                }
            }
        }
    }

    private var freeScrollView: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: cols), spacing: 6) {
                ForEach(sortedSlots) { slot in
                    viewSlotCell(slot: slot)
                        .aspectRatio(5/7, contentMode: .fit)
                }
            }
            .padding(12)
        }
    }

    private func pagedViewContent(geo: GeometryProxy) -> some View {
        let pageSize = binderPageSize(in: geo.size)
        return PageCurlView(
            pageCount: pageCount,
            currentPage: $currentPage,
            isTurning: $isPageTurning,
            // Use the system background so the rounded corners of the binder
            // surface read as distinct cut-outs (a "card" against the page
            // chrome) instead of blending into a same-colour rectangle.
            // Also gives the page-curl effect realistic white page-back.
            pageBackgroundColor: .systemBackground
        ) { pageIdx in
            pageSurface(pageIdx: pageIdx, pageSize: pageSize)
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func binderPageSize(in available: CGSize) -> CGSize {
        let horizontalPadding: CGFloat = 32
        let verticalPadding: CGFloat = 24
        let slotSpacing: CGFloat = 8
        // These must match the chrome inside `pageSurface`:
        //   .padding(.horizontal, 14)  →  28pt total
        //   .padding(.top, 14) + Spacer(min 6) + swipeHint (~20) + .padding(.bottom, 10) ≈ 50pt
        // Plus a few pts of breathing room so cards never touch the rounded edges.
        let surfaceHorizontalChrome: CGFloat = 28
        let surfaceVerticalChrome: CGFloat = 60
        let cardAspectRatio: CGFloat = 5.0 / 7.0

        let maxWidth = max(available.width - horizontalPadding, 240)
        let maxHeight = max(available.height - verticalPadding, 320)

        let gridAspectRatio = CGFloat(cols) * cardAspectRatio / CGFloat(rows)
        let pageAspectRatio = (gridAspectRatio * 1.04)

        var width = min(maxWidth, maxHeight * pageAspectRatio)
        var height = width / pageAspectRatio

        if height > maxHeight {
            height = maxHeight
            width = height * pageAspectRatio
        }

        let totalGridSpacingX = CGFloat(max(cols - 1, 0)) * slotSpacing
        let totalGridSpacingY = CGFloat(max(rows - 1, 0)) * slotSpacing
        let contentWidth = max(width - surfaceHorizontalChrome, 120)
        let cellWidth = (contentWidth - totalGridSpacingX) / CGFloat(cols)
        let gridHeight = cellWidth / cardAspectRatio * CGFloat(rows) + totalGridSpacingY
        let desiredHeight = gridHeight + surfaceVerticalChrome

        if desiredHeight < height {
            height = desiredHeight
        } else {
            // Grid wants more vertical room than is available — shrink cells so
            // the whole thing fits without clipping the top/bottom rows.
            let availableForGrid = height - surfaceVerticalChrome
            let shrunkCellHeight = max((availableForGrid - totalGridSpacingY) / CGFloat(rows), 40)
            let shrunkCellWidth = shrunkCellHeight * cardAspectRatio
            let shrunkContentWidth = shrunkCellWidth * CGFloat(cols) + totalGridSpacingX
            width = min(width, shrunkContentWidth + surfaceHorizontalChrome)
        }

        return CGSize(width: width, height: height)
    }

    private func pageSurface(pageIdx: Int, pageSize: CGSize) -> some View {
        let positions = positions(for: pageIdx)
        // Corner radius for the binder playmat. Bumped from 14 → 22 to match
        // the mockup's pronounced, card-like rounding — the smaller radius read
        // as barely-rounded against the page chrome.
        let surfaceRadius: CGFloat = 22

        return ZStack {
            // 1. Base: binder colour + procedural cross-hatch weave (felt/baize).
            //    We override to `.linen` here so the *interior* of every binder
            //    has a consistent playmat texture regardless of cover material.
            BinderTextureView(
                colourName: binder.colour,
                texture: .linen,
                seed: binder.textureSeed,
                compact: false
            )
            // Slight all-over darkening so cards pop against the surface.
            .overlay(Color.black.opacity(0.22))
            // Radial vignette — centre lighter, edges darker. Makes the
            // surface feel recessed and focuses the eye on the cards.
            .overlay {
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: .black.opacity(0), location: 0.0),
                        .init(color: .black.opacity(0.14), location: 0.6),
                        .init(color: .black.opacity(0.30), location: 1.0)
                    ]),
                    center: .center,
                    startRadius: 40,
                    endRadius: max(pageSize.width, pageSize.height) * 0.65
                )
            }
            // Faint inner border, a few pixels in — suggests material wear
            // along the playmat edge.
            .overlay {
                RoundedRectangle(cornerRadius: surfaceRadius - 4, style: .continuous)
                    .inset(by: 4)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: surfaceRadius, style: .continuous))
            // Inset shadow on all four edges to reinforce the recessed feel.
            .overlay {
                RoundedRectangle(cornerRadius: surfaceRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.55), lineWidth: 6)
                    .blur(radius: 5)
                    .mask(
                        RoundedRectangle(cornerRadius: surfaceRadius, style: .continuous)
                    )
                    .allowsHitTesting(false)
            }
            // Soft drop shadow under the surface.
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)

            // 2. Card grid
            VStack(spacing: 0) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: cols),
                    spacing: 8
                ) {
                    ForEach(positions, id: \.self) { pos in
                        let slot = sortedSlots.first { $0.position == pos }
                        Group {
                            if let slot {
                                viewSlotCell(slot: slot)
                            } else {
                                emptySlotCell(position: pos)
                            }
                        }
                        .aspectRatio(5/7, contentMode: .fit)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)

                Spacer(minLength: 6)

                // 3. Faint swipe hint (present enough to onboard, invisible enough
                //    to not distract from the cards).
                swipeHint
                    .padding(.bottom, 10)
            }

            // 4. Page-turn dimming overlay (existing behaviour)
            if isPageTurning {
                RoundedRectangle(cornerRadius: surfaceRadius, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.22 : 0.12))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .clipped()
    }

    private var swipeHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.left")
                .font(.system(size: 9, weight: .semibold))
            Text("SWIPE TO TURN PAGE")
                .font(.system(size: 10, weight: .medium))
                .tracking(2.0)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(Color.white.opacity(0.20))
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func emptySlotCell(position: Int) -> some View {
        let cornerRadius: CGFloat = 6
        ZStack {
            // Dark, semi-transparent fill — gives the slot a "pocket" presence
            // against the recessed surface without competing with filled cards.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.12))

            // Dashed boundary so an empty slot reads as "a place for a card".
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(0.12),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )

            // Faint plus/cross formed by two thin lines.
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 14, height: 1)
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 1, height: 14)
            }
        }
    }

    @ViewBuilder
    private func viewSlotCell(slot: BinderSlot) -> some View {
        let isOwned = ownedCardIDs.contains(slot.cardID)
        let imageURL = cardsByID[slot.cardID].map {
            AppConfiguration.imageURL(relativePath: $0.imageLowSrc)
        }
        Button {
            if !isEditing { viewingSlot = slot }
        } label: {
            ZStack(alignment: .topTrailing) {
                // Card back/face
                CachedAsyncImage(url: imageURL, targetSize: CGSize(width: 220, height: 308)) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(uiColor: .systemGray5))
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                // Inset top highlight — simulates light catching the card edge.
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .inset(by: 0.5)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1
                    )

                Image(systemName: isOwned ? "checkmark.circle.fill" : "questionmark.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isOwned ? .green : Color(uiColor: .systemGray3))
                    .background(Circle().fill(.white).padding(1))
                    .padding(3)
            }
        }
        .buttonStyle(BinderCardButtonStyle())
    }

    // MARK: - Edit mode

    private var editContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                editToolbar

                if layout.isFreeScroll {
                    editGrid(positions: Array(0..<max(sortedSlots.count + 3, slotsPerPage)))
                } else {
                    ForEach(0..<(pageCount + 1), id: \.self) { pageIdx in
                        editPageSection(pageIdx: pageIdx)
                    }
                }
            }
            .padding(12)
        }
    }

    private var editToolbar: some View {
        HStack(spacing: 12) {
            Button {
                editingTitle = binder.title
                showEditTitle = true
            } label: {
                Label("Rename", systemImage: "pencil")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)

            Button {
                showColourPicker = true
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(BinderDetailView.binderSwiftUIColor(binder.colour))
                        .frame(width: 14, height: 14)
                    Text("Colour")
                        .font(.caption.weight(.medium))
                }
            }
            .buttonStyle(.bordered)

            Spacer()

            if !layout.isFreeScroll {
                Button {
                    addPage()
                } label: {
                    Label("Add Page", systemImage: "plus.rectangle.on.rectangle")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func editPageSection(pageIdx: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Page \(pageIdx + 1)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            editGrid(positions: positions(for: pageIdx))

            Divider()
        }
    }

    private func editGrid(positions: [Int]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: cols), spacing: 8) {
            ForEach(positions, id: \.self) { pos in
                editSlotCell(position: pos)
                    .aspectRatio(5/7, contentMode: .fit)
            }
        }
    }

    @ViewBuilder
    private func editSlotCell(position: Int) -> some View {
        let slot = sortedSlots.first { $0.position == position }
        ZStack(alignment: .topTrailing) {
            if let slot {
                let imageURL = cardsByID[slot.cardID].map {
                    AppConfiguration.imageURL(relativePath: $0.imageLowSrc)
                }
                CachedAsyncImage(url: imageURL, targetSize: CGSize(width: 220, height: 308)) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4).fill(Color(uiColor: .systemGray5))
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                // Remove badge
                Button {
                    removeSlot(at: position)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.red)
                        .background(Circle().fill(.white).padding(2))
                }
                .padding(3)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color(uiColor: .systemGray4), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                    .overlay {
                        Image(systemName: "plus")
                            .font(.title3)
                            .foregroundStyle(Color(uiColor: .systemGray3))
                    }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .opacity(draggedSlotPosition == position ? 0.45 : 1)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    draggedSlotPosition != nil && draggedSlotPosition != position
                        ? Color.accentColor.opacity(0.18)
                        : Color.clear,
                    lineWidth: 1
                )
        }
        .onDrag {
            guard slot != nil else { return NSItemProvider() }
            draggedSlotPosition = position
            return NSItemProvider(object: NSString(string: "\(position)"))
        }
        .onDrop(of: [UTType.text], delegate: BinderSlotDropDelegate(
            targetPosition: position,
            draggedSlotPosition: $draggedSlotPosition,
            onDropSlot: moveSlot
        ))
        .onTapGesture {
            if draggedSlotPosition == nil {
                slotPickerTarget = BinderSlotPickerTarget(id: position)
            }
        }
    }

    // MARK: - Helpers

    private func fillSlots(startingAt position: Int, selections: [BinderSlotPickerSelection]) {
        for (offset, selection) in selections.enumerated() {
            let targetPosition = position + offset
            if let existing = binder.slotList.first(where: { $0.position == targetPosition }) {
                existing.cardID = selection.cardID
                existing.variantKey = selection.variantKey
                existing.cardName = selection.cardName
            } else {
                let slot = BinderSlot(
                    position: targetPosition,
                    cardID: selection.cardID,
                    variantKey: selection.variantKey,
                    cardName: selection.cardName
                )
                slot.binder = binder
                modelContext.insert(slot)
            }
        }
        slotPickerTarget = nil
        Task { await loadCards() }
    }

    private func removeSlot(at position: Int) {
        guard let slot = binder.slotList.first(where: { $0.position == position }) else { return }
        modelContext.delete(slot)
    }

    private func moveSlot(from sourcePosition: Int, to targetPosition: Int) {
        guard sourcePosition != targetPosition else { return }
        guard let sourceSlot = binder.slotList.first(where: { $0.position == sourcePosition }) else { return }

        if let targetSlot = binder.slotList.first(where: { $0.position == targetPosition }) {
            targetSlot.position = sourcePosition
        }
        sourceSlot.position = targetPosition
    }

    private func addPage() {
        // Navigate to the last page so the user sees the new empty page
        withAnimation { currentPage = pageCount }
    }

    private func loadCards() async {
        var map = cardsByID
        for slot in binder.slotList {
            let id = slot.cardID
            guard map[id] == nil else { continue }
            if let card = await services.cardData.loadCard(masterCardId: id) {
                map[id] = card
            }
        }
        cardsByID = map
        await refreshSlotValues()
    }

    /// Re-fetches the USD market price for every filled slot, keyed by
    /// `cardID|variantKey`. Called on load and whenever slot membership changes
    /// so the bottom stats bar / page value stay live without heavy work on
    /// every render.
    private func refreshSlotValues() async {
        var values: [String: Double] = [:]
        for slot in binder.slotList {
            guard let card = cardsByID[slot.cardID] else { continue }
            if let usd = await services.pricing.usdPriceForVariant(
                for: card,
                variantKey: slot.variantKey
            ) {
                values[slotValueKey(slot)] = usd
            }
        }
        slotUSDValues = values
    }

    private func slotValueKey(_ slot: BinderSlot) -> String {
        "\(slot.cardID)|\(slot.variantKey)"
    }

    static func binderSwiftUIColor(_ name: String) -> Color {
        BinderColourPalette.color(named: name)
    }

    // MARK: - Stats helpers

    private var filledCardCount: Int { binder.slotList.count }

    private var totalUSDValue: Double {
        binder.slotList.reduce(0) { acc, slot in
            acc + (slotUSDValues[slotValueKey(slot)] ?? 0)
        }
    }

    private var pageUSDValue: Double {
        let positions = Set(positions(for: currentPage))
        return binder.slotList
            .filter { positions.contains($0.position) }
            .reduce(0) { acc, slot in
                acc + (slotUSDValues[slotValueKey(slot)] ?? 0)
            }
    }

    private var formattedTotalValue: String {
        formatMoney(usd: totalUSDValue)
    }

    private var formattedPageValue: String {
        formatMoney(usd: pageUSDValue)
    }

    private func formatMoney(usd: Double) -> String {
        let display = services.priceDisplay.currency
        // Round to whole units for the stats bar so the three numbers stay
        // visually balanced; per-page uses the same precision the rest of the
        // app does (2dp) so small values still read accurately.
        let amount = display == .gbp ? usd * services.pricing.usdToGbp : usd
        let formatted: String
        if amount >= 1000 {
            formatted = String(format: "%.0f", amount)
        } else {
            formatted = String(format: "%.2f", amount)
        }
        return "\(display.symbol)\(formatted)"
    }

}

// MARK: - Button style for cards (lift on press)

private struct BinderCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.02 : 1.0)
            .offset(y: configuration.isPressed ? -2 : 0)
            // Primary shadow (long, soft) + secondary (short, contact).
            .shadow(
                color: .black.opacity(configuration.isPressed ? 0.55 : 0.50),
                radius: configuration.isPressed ? 10 : 8,
                x: 0,
                y: configuration.isPressed ? 6 : 3
            )
            .shadow(
                color: .black.opacity(0.40),
                radius: 2,
                x: 0,
                y: 1
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

private struct BinderSlotDropDelegate: DropDelegate {
    let targetPosition: Int
    @Binding var draggedSlotPosition: Int?
    let onDropSlot: (Int, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggedSlotPosition != nil && info.hasItemsConforming(to: [UTType.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { draggedSlotPosition = nil }
        guard let sourcePosition = draggedSlotPosition else { return false }
        onDropSlot(sourcePosition, targetPosition)
        return true
    }

    func dropExited(info: DropInfo) {}
}

// MARK: - Full-size card viewer with swipe-to-dismiss

private struct BinderCardViewer: View {
    let card: Card
    let onDismiss: () -> Void

    @State private var offset: CGSize = .zero
    @State private var rotation: Double = 0
    @State private var opacity: Double = 1

    private var imageURL: URL? {
        let src = card.imageHighSrc ?? card.imageLowSrc
        return AppConfiguration.imageURL(relativePath: src)
    }

    private var dragDistance: CGFloat {
        sqrt(offset.width * offset.width + offset.height * offset.height)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.72 * opacity)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            CachedAsyncImage(url: imageURL, targetSize: CGSize(width: 600, height: 840)) { img in
                img.resizable().scaledToFit()
            } placeholder: {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .systemGray4))
                    .aspectRatio(5/7, contentMode: .fit)
                    .overlay { ProgressView() }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 8)
            .padding(.horizontal, 32)
            .offset(offset)
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = value.translation
                        rotation = Double(value.translation.width / 20)
                    }
                    .onEnded { value in
                        let dist = sqrt(value.translation.width * value.translation.width + value.translation.height * value.translation.height)
                        let velocity = sqrt(value.velocity.width * value.velocity.width + value.velocity.height * value.velocity.height)
                        if dist > 120 || velocity > 800 {
                            let angle = atan2(value.translation.height, value.translation.width)
                            let flyX = cos(angle) * 600
                            let flyY = sin(angle) * 600
                            withAnimation(.easeOut(duration: 0.3)) {
                                offset = CGSize(width: flyX, height: flyY)
                                rotation = Double(flyX / 8)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onDismiss()
                            }
                        } else {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                offset = .zero
                                rotation = 0
                                opacity = 1
                            }
                        }
                    }
            )
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.22)) {
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            onDismiss()
        }
    }
}

// MARK: - Page-curl wrapper

private struct PageCurlView<Content: View>: UIViewControllerRepresentable {
    let pageCount: Int
    @Binding var currentPage: Int
    @Binding var isTurning: Bool
    let pageBackgroundColor: UIColor
    @ViewBuilder let pageContent: (Int) -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let vc = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: UIPageViewController.SpineLocation.min.rawValue]
        )
        vc.isDoubleSided = false
        vc.view.backgroundColor = pageBackgroundColor
        vc.view.layer.speed = 0.55
        vc.dataSource = context.coordinator
        vc.delegate = context.coordinator
        context.coordinator.parent = self
        context.coordinator.controllers = (0..<pageCount).map { makeHosting(index: $0) }
        if pageCount > 0 {
            vc.setViewControllers(
                [context.coordinator.controllers[currentPage]],
                direction: .forward,
                animated: false
            )
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        let coord = context.coordinator
        coord.parent = self

        let needed = pageCount
        if coord.controllers.count != needed {
            coord.controllers = (0..<needed).map { makeHosting(index: $0) }
        } else {
            for i in 0..<needed {
                (coord.controllers[i] as? UIHostingController<Content>)?.rootView = pageContent(i)
            }
        }

        guard needed > 0 else { return }
        let clampedPage = max(0, min(currentPage, needed - 1))
        let shown = uiViewController.viewControllers?.first
        if shown !== coord.controllers[clampedPage] {
            isTurning = true
            uiViewController.setViewControllers(
                [coord.controllers[clampedPage]],
                direction: clampedPage > (coord.lastPage ?? 0) ? .forward : .reverse,
                animated: true
            )
            coord.lastPage = clampedPage
        }
    }

    private func makeHosting(index: Int) -> UIViewController {
        let hosting = UIHostingController(rootView: pageContent(index))
        hosting.view.backgroundColor = pageBackgroundColor
        hosting.view.isOpaque = true
        return hosting
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageCurlView
        var controllers: [UIViewController] = []
        var lastPage: Int?

        init(parent: PageCurlView) {
            self.parent = parent
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
            guard let idx = controllers.firstIndex(of: vc), idx > 0 else { return nil }
            return controllers[idx - 1]
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
            guard let idx = controllers.firstIndex(of: vc), idx < controllers.count - 1 else { return nil }
            return controllers[idx + 1]
        }

        func pageViewController(_ pvc: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            parent.isTurning = true
        }

        func pageViewController(
            _ pvc: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            parent.isTurning = false
            guard completed, let shown = pvc.viewControllers?.first,
                  let idx = controllers.firstIndex(of: shown) else { return }
            lastPage = idx
            parent.currentPage = idx
        }
    }
}

// MARK: - Style picker sheet

struct BinderStylePickerSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Bindable var binder: Binder
    @State private var cardURLs: [URL?] = [nil, nil, nil]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Preview
                    BinderCoverView(
                        title: binder.title,
                        subtitle: "\(binder.slotList.count) cards · \(binder.layout.displayName)",
                        colourName: binder.colour,
                        texture: binder.textureKind,
                        seed: binder.textureSeed,
                        peekingCardURLs: cardURLs,
                        showCardPreview: binder.showCardPreview,
                        compact: false
                    )
                    .padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 20) {
                        // Texture Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TEXTURE")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            Picker("Texture", selection: $binder.texture) {
                                ForEach(BinderTexture.allCases) { tex in
                                    Text(tex.displayName).tag(tex.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        // Colour Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("COLOUR")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                                ForEach(BinderColourPalette.pickerOptions, id: \.name) { swatch in
                                    Button {
                                        binder.colour = swatch.name
                                    } label: {
                                        Circle()
                                            .fill(swatch.color)
                                            .frame(width: 44, height: 44)
                                            .overlay {
                                                if binder.colour == swatch.name {
                                                    Image(systemName: "checkmark")
                                                        .font(.headline.weight(.bold))
                                                        .foregroundStyle(.white)
                                                }
                                            }
                                            .shadow(color: swatch.color.opacity(0.3), radius: 4, x: 0, y: 2)
                                    }
                                }
                            }
                        }

                        // Cover Options — mirror of the create sheet's toggle.
                        VStack(alignment: .leading, spacing: 12) {
                            Text("COVER")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            Toggle(isOn: $binder.showCardPreview) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Show cards on cover")
                                        .font(.subheadline.weight(.medium))
                                    Text("Preview the first few cards on the binder front")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tint(.accentColor)
                            .padding(16)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 24)
            }
            .task {
                await loadCardURLs()
            }
            .navigationTitle("Binder Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .bold()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func loadCardURLs() async {
        let slots = binder.slotList.prefix(3)
        var urls: [URL?] = []
        
        for slot in slots {
            if let card = await services.cardData.loadCard(masterCardId: slot.cardID) {
                urls.append(AppConfiguration.imageURL(relativePath: card.imageLowSrc))
            } else {
                urls.append(nil)
            }
        }
        
        while urls.count < 3 { urls.append(nil) }
        cardURLs = urls
    }
}
