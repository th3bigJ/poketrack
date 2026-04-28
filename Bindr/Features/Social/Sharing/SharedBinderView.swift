import SwiftUI

/// Read-only rendering of a friend's shared binder.
///
/// Mirrors ``BinderDetailView``'s page surface — a textured playmat
/// background derived from the publisher's colour/texture/seed, with the
/// cards laid out on each page in the publisher's grid layout. Pages swipe
/// horizontally (TabView page style) so the experience reads as a real
/// binder rather than one long list.
///
/// Used by ``SharedContentView`` whenever the shared content is a binder. For
/// other content types (wishlist, deck, pull, etc.) the original list-style
/// renderer is still appropriate because a list is what those callers
/// actually produce.
struct SharedBinderView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    let content: SharedContent

    @State private var cardsByID: [String: Card] = [:]
    @State private var presentedCard: Card?
    @State private var currentPage: Int = 0

    private struct BinderCardEntry: Identifiable {
        let id: String
        /// Slot index from the publisher. Kept so we can reproduce empty
        /// pockets and page breaks faithfully when the publisher leaves gaps.
        let position: Int
        let cardID: String
        let cardName: String
        let variantKey: String
    }

    /// Decoded binder slots. Each entry retains its publisher-side `position`
    /// so we can reproduce the original page layout — including empty slots
    /// in the middle. Sorted by position so the order is stable regardless of
    /// the JSON array's encoding order.
    private var entries: [BinderCardEntry] {
        guard case .array(let raw)? = content.payload["items"] else { return [] }
        let decoded: [BinderCardEntry] = raw.enumerated().compactMap { offset, value in
            guard case .object(let object) = value else { return nil }
            let cardID = object["cardID"]?.stringValue ?? ""
            guard !cardID.isEmpty else { return nil }
            let position: Int
            if case .number(let p)? = object["position"] {
                position = Int(p)
            } else {
                // Legacy payloads (no position field) fall back to array order
                // so older shared binders still render contiguously instead of
                // collapsing onto the same slot.
                position = offset
            }
            return BinderCardEntry(
                id: "\(position)|\(cardID)",
                position: position,
                cardID: cardID,
                cardName: object["cardName"]?.stringValue ?? "",
                variantKey: object["variantKey"]?.stringValue ?? "normal"
            )
        }
        return decoded.sorted { $0.position < $1.position }
    }

    /// Fast lookup from slot position → entry, used by `pageSurface` to fill
    /// each pocket on a page in O(1) rather than scanning the whole array.
    private var entriesByPosition: [Int: BinderCardEntry] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.position, $0) })
    }

    private var colourName: String {
        let raw = content.payload["colour"]?.stringValue ?? ""
        return raw.isEmpty ? "navy" : raw
    }

    /// Texture seed from the publisher. Falls back to a stable default so the
    /// pattern is at least deterministic if the payload is missing the field.
    private var seed: Int {
        if case .number(let value)? = content.payload["seed"] {
            return Int(value)
        }
        return 1
    }

    /// Page layout from the publisher (`fixed:RxC` or `freeScroll`). Older
    /// shared binders that pre-date the `page_layout` field default to 3×3,
    /// which matches the most common binder layout in the app.
    private var layout: BinderPageLayout {
        if let raw = content.payload["page_layout"]?.stringValue, !raw.isEmpty {
            return BinderPageLayout(rawValue: raw)
        }
        return BinderPageLayout(rawValue: "fixed:3x3")
    }

    private var slotsPerPage: Int { layout.slotsPerPage ?? 9 }
    private var cols: Int { layout.columns }

    /// Number of pages needed to cover the highest occupied position. Empty
    /// binders still get one page so the grid surface always has something to
    /// render.
    private var pageCount: Int {
        let maxPos = entries.last?.position ?? -1
        return max(1, Int(ceil(Double(maxPos + 1) / Double(slotsPerPage))))
    }

    var body: some View {
        VStack(spacing: 0) {
            titleHeader
            if layout.isFreeScroll {
                freeScrollSurface
            } else {
                pagedSurface
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(content.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadCards()
        }
        .sheet(item: $presentedCard) { card in
            // Reuse the standard browse detail screen so tapping a card here
            // matches tapping a card anywhere else in the app.
            CardBrowseDetailView(cards: [card], startIndex: 0)
                .environment(services)
        }
    }

    private var titleHeader: some View {
        VStack(spacing: 8) {
            // Redundant title removed (already in navigation bar)

            if let description = content.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Capsule()
                .fill(BinderColourPalette.color(named: colourName))
                .frame(width: 40, height: 3)
                .opacity(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// Paged content using TabView's page style. Each tab is a textured
    /// playmat with that page's slots laid out on top, matching the look of
    /// ``BinderDetailView``'s pageSurface so a friend's binder reads as a
    /// real binder, not an endless list.
    @State private var isPageTurning = false

    private func binderPageSize(in available: CGSize) -> CGSize {
        let horizontalPadding: CGFloat = 32
        let verticalPadding: CGFloat = 40
        return CGSize(
            width: available.width - horizontalPadding,
            height: available.height - verticalPadding
        )
    }

    private var pagedSurface: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let pageSize = binderPageSize(in: geo.size)
                PageCurlView(
                    pageCount: pageCount,
                    currentPage: $currentPage,
                    isTurning: $isPageTurning,
                    pageBackgroundColor: .systemBackground,
                    contentVersion: cardsByID.count
                ) { pageIdx in
                    pageSurface(pageIdx: pageIdx, pageSize: pageSize)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            pageIndicator
        }
        .padding(.bottom, 16)
    }

    /// Bottom strip — page dots plus a small "swipe to turn" hint. Mirrors
    /// the affordance from ``BinderDetailView`` so the gesture is obvious
    /// without needing to read documentation.
    private var pageIndicator: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { idx in
                    Circle()
                        .fill(idx == currentPage ? Color.primary.opacity(0.6) : Color.primary.opacity(0.18))
                        .frame(width: 6, height: 6)
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .semibold))
                Text("PAGE \(currentPage + 1) OF \(pageCount)")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(2.0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Color.primary.opacity(0.55))
        }
    }

    /// Single page of the binder. Layered the same way as
    /// ``BinderDetailView``: texture + dark wash + radial vignette + inset
    /// border, with the card grid sitting on top of all of it.
    private func pageSurface(pageIdx: Int, pageSize: CGSize) -> some View {
        let surfaceRadius: CGFloat = 22
        let slotSpacing: CGFloat = 8
        let positions = positions(for: pageIdx)

        return ZStack {
            // 1. Base: binder colour + procedural cross-hatch weave (felt/baize).
            //    `.linen` matches the playmat override BinderDetailView uses
            //    so the inside of every binder feels consistent regardless of
            //    cover material.
            BinderTextureView(
                colourName: colourName,
                texture: .linen,
                seed: seed,
                compact: false
            )
            .overlay(Color.black.opacity(0.22))
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
            .clipShape(RoundedRectangle(cornerRadius: surfaceRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: surfaceRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.55), lineWidth: 6)
                    .blur(radius: 5)
                    .mask(RoundedRectangle(cornerRadius: surfaceRadius, style: .continuous))
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)

            // 2. Card grid on top of the playmat.
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: slotSpacing), count: cols),
                spacing: slotSpacing
            ) {
                ForEach(positions, id: \.self) { pos in
                    Group {
                        if let entry = entriesByPosition[pos] {
                            cardCell(entry: entry)
                        } else {
                            emptySlot
                        }
                    }
                    .aspectRatio(5/7, contentMode: .fit)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
    }

    /// Free-scroll layout — used when the publisher chose `freeScroll` instead
    /// of a fixed grid. Renders the same textured playmat but fills it with
    /// every card in a continuous scrollable grid rather than splitting into
    /// pages, which is the same affordance ``BinderDetailView`` uses for that
    /// layout.
    private var freeScrollSurface: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: cols),
                spacing: 6
            ) {
                ForEach(entries) { entry in
                    cardCell(entry: entry)
                        .aspectRatio(5/7, contentMode: .fit)
                }
            }
            .padding(14)
            .background {
                ZStack {
                    BinderTextureView(
                        colourName: colourName,
                        texture: .linen,
                        seed: seed,
                        compact: false
                    )
                    Color.black.opacity(0.22)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func positions(for page: Int) -> [Int] {
        let start = page * slotsPerPage
        return Array(start..<(start + slotsPerPage))
    }

    @ViewBuilder
    private func cardCell(entry: BinderCardEntry) -> some View {
        let card = cardsByID[entry.cardID]
        let imageURL = card.map { AppConfiguration.imageURL(relativePath: $0.imageLowSrc) }

        Button {
            if let card { presentedCard = card }
        } label: {
            ZStack(alignment: .topTrailing) {
                CachedAsyncImage(url: imageURL, targetSize: CGSize(width: 220, height: 308)) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(uiColor: .systemGray5))
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                // Inset top highlight — same trick BinderDetailView uses to
                // suggest light catching the card edge.
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
            }
            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(card == nil)
    }

    /// Empty slot affordance — same dashed pocket BinderDetailView shows when
    /// a slot hasn't been filled, so a friend's binder looks identical to the
    /// publisher's view (rather than collapsing the empty pockets).
    private var emptySlot: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.12))

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(0.12),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )
        }
    }

    private func loadCards() async {
        for entry in entries {
            guard cardsByID[entry.cardID] == nil else { continue }
            if let card = await services.cardData.loadCard(masterCardId: entry.cardID) {
                cardsByID[entry.cardID] = card
            }
        }
    }
}
