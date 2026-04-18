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

    private var layout: BinderPageLayout { binder.layout }

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
                viewContent
            }
        }
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
        .sheet(item: $slotPickerTarget) { target in
            BinderSlotPickerView { cardID, variantKey, cardName in
                fillSlot(position: target.id, cardID: cardID, variantKey: variantKey, cardName: cardName)
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
            BinderColourPickerSheet(current: binder.colour) { colour in
                binder.colour = colour
            }
        }
    }

    // MARK: - Header

    private var binderHeader: some View {
        ZStack {
            if isEditing {
                Button {
                    editingTitle = binder.title
                    showEditTitle = true
                } label: {
                    HStack(spacing: 6) {
                        Text(binder.title)
                            .font(.title2.weight(.bold))
                        Image(systemName: "pencil")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            } else {
                Text(binder.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
            }

            HStack {
                ChromeGlassCircleButton(accessibilityLabel: "Back") { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 0)
                Button(isEditing ? "Done" : "Edit") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isEditing.toggle()
                    }
                }
                .fontWeight(isEditing ? .semibold : .regular)
                .modifier(ChromeGlassCircleGlyphModifier())
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - View mode (page-turn)

    private var viewContent: some View {
        GeometryReader { geo in
            if layout == .freeScroll {
                freeScrollView
            } else {
                pagedViewContent(geo: geo)
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
            pageBackgroundColor: UIColor(pageBackColor)
        ) { pageIdx in
            pageSurface(pageIdx: pageIdx, pageSize: pageSize)
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 16)
    }

    private var pageBackColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private func binderPageSize(in available: CGSize) -> CGSize {
        let horizontalPadding: CGFloat = 32
        let verticalPadding: CGFloat = 24
        let slotSpacing: CGFloat = 8
        let gridPadding: CGFloat = 24
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
        let contentWidth = max(width - gridPadding, 120)
        let cellWidth = (contentWidth - totalGridSpacingX) / CGFloat(cols)
        let gridHeight = cellWidth / cardAspectRatio * CGFloat(rows) + totalGridSpacingY
        let desiredHeight = gridHeight + gridPadding

        if desiredHeight < height {
            height = desiredHeight
        }

        return CGSize(width: width, height: height)
    }

    private func pageSurface(pageIdx: Int, pageSize: CGSize) -> some View {
        let positions = positions(for: pageIdx)
        return ZStack {
            // Page background — subtle paper texture via shadow layering
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(pageBackColor)
                .shadow(color: .black.opacity(0.08), radius: 6, x: 2, y: 2)
                .shadow(color: .black.opacity(0.04), radius: 2, x: -1, y: -1)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(pageBackColor)
                .padding(12)

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
                            Color(uiColor: .systemGray6)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .aspectRatio(5/7, contentMode: .fit)
                }
            }
            .padding(12)

            if isPageTurning {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.22 : 0.12))
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .clipped()
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
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(pageBackColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(pageBackColor.opacity(0.98))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), lineWidth: 0.5)
                    }

                CachedAsyncImage(url: imageURL, targetSize: CGSize(width: 220, height: 308)) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(uiColor: .systemGray5))
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 2, x: 1, y: 1)

                Image(systemName: isOwned ? "checkmark.circle.fill" : "questionmark.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isOwned ? .green : Color(uiColor: .systemGray3))
                    .background(Circle().fill(.white).padding(1))
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Edit mode

    private var editContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                editToolbar

                if layout == .freeScroll {
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

            if layout != .freeScroll {
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

    private func fillSlot(position: Int, cardID: String, variantKey: String, cardName: String) {
        if let existing = binder.slotList.first(where: { $0.position == position }) {
            existing.cardID = cardID
            existing.variantKey = variantKey
            existing.cardName = cardName
        } else {
            let slot = BinderSlot(position: position, cardID: cardID, variantKey: variantKey, cardName: cardName)
            slot.binder = binder
            modelContext.insert(slot)
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
    }

    static func binderSwiftUIColor(_ name: String) -> Color {
        switch name {
        case "red":    return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green":  return .green
        case "blue":   return .blue
        case "purple": return .purple
        case "pink":   return .pink
        default:       return Color(uiColor: .systemGray2)
        }
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

// MARK: - Colour picker sheet

struct BinderColourPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let current: String
    let onSelect: (String) -> Void

    private let colours: [(name: String, color: Color)] = [
        ("red", .red), ("orange", .orange), ("yellow", .yellow),
        ("green", .green), ("blue", .blue), ("purple", .purple),
        ("pink", .pink), ("grey", Color(uiColor: .systemGray2))
    ]

    var body: some View {
        NavigationStack {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 20) {
                ForEach(colours, id: \.name) { swatch in
                    Button {
                        onSelect(swatch.name)
                        dismiss()
                    } label: {
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 64, height: 64)
                            .overlay {
                                if current == swatch.name {
                                    Image(systemName: "checkmark")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .shadow(color: swatch.color.opacity(0.4), radius: 6, x: 0, y: 3)
                    }
                }
            }
            .padding(32)
            .navigationTitle("Choose Colour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
