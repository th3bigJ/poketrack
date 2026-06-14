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
    @Environment(\.bindrAccent) private var bindrAccent
    @Bindable var binder: Binder

    /// When `true`, the binder was opened from the Binders grid and should
    /// include its front cover as page 0 of the page-curl. After a brief
    /// hold (~1s) the view programmatically advances to page 1 so the
    /// existing UIPageViewController curl reveals the first card page —
    /// identical to a manual swipe.
    var entryFromGrid: Bool = false
    /// Custom dismiss hook. When provided, the back button (and the
    /// post-cover-curl exit) call this instead of the SwiftUI `dismiss`
    /// environment, so the host can drive its own collapse animation.
    var onCustomDismiss: (() -> Void)? = nil
    /// Pre-loaded card thumbnail URLs passed from the grid view, used to 
    /// prevent re-loading flickers on the cover page during entry.
    var preloadedPeekingURLs: [URL?]? = nil
    /// Pre-resolved binder value text passed from the grid.
    var preloadedValueText: String? = nil
    /// The top safe-area inset of the screen, passed in by the host when
    /// ``entryFromGrid`` is true so the header doesn't overlap the status bar.
    var topSafeAreaInset: CGFloat = 0
    /// The bottom safe-area inset of the screen (home indicator area), passed
    /// in by the host so the bottom stats row doesn't sit under the home bar.
    var bottomSafeAreaInset: CGFloat = 0

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isEditing = false
    @State private var cardsByID: [String: Card] = [:]
    @State private var slotPickerTarget: BinderSlotPickerTarget? = nil
    @State private var showEditTitle = false
    @State private var editingTitle = ""
    @State private var showColourPicker = false
    @State private var showShareSettings = false
    @State private var isSharedPublished = false
    @State private var isModeTransitioning = false
    @State private var currentPage = 0
    @State private var viewingSlot: BinderSlot? = nil
    @State private var detailCard: Card? = nil
    @State private var isPageTurning = false
    @State private var draggedSlotPosition: Int? = nil
    @State private var isClosing = false
    /// Hides the header and bottom stats row until the binder has finished
    /// its opening morph. Prevents users from tapping "Back" before the
    /// animation lands and creates a cleaner "reveal" moment.
    @State private var isChromeVisible = false
    /// Becomes `true` once the post-mount cover-hold timer has fired and we
    /// have programmatically auto-advanced from the cover (page 0) to the
    /// first card page (page 1). Tracks whether we're still in the entry
    /// "cover" moment so chrome can fade in at the right point.
    @State private var hasAutoAdvancedFromCover = false
    /// When the cover auto-curls into the first card page, start the
    /// wider inner page just a little smaller and ease it to full size.
    /// This softens the portrait-cover → landscape-grid size change
    /// without cropping the cover itself.
    @State private var innerPageRevealScale: CGFloat = 1
    /// Wall-clock moment (`CACurrentMediaTime` reference) at which the
    /// auto page-curl from the cover finished. Used by ``handleBackTap``
    /// to decide whether to play the full reverse curl or skip straight
    /// to the host's collapse — quick "I tapped the wrong binder" backs
    /// shouldn't feel like a 2-second penalty.
    @State private var firstCardPageLandedAt: Date? = nil

    /// Back-button handler for the binder detail screen. Mirrors the open
    /// sequence: when entered from the grid we curl back to the cover (page
    /// 0) using the existing ``PageCurlView`` flip, then hand off to the
    /// host's collapse animation. When opened any other way (or when we're
    /// already on the cover), we just dismiss.
    ///
    /// **Quick-back shortcut.** If the user taps back within ~2.5s of the
    /// auto page-curl landing on page 1, they almost certainly opened the
    /// wrong binder by mistake — skip the full reverse curl and go straight
    /// to the host's collapse. This avoids subjecting the user to a ~1.7s
    /// "did you really mean to leave" animation when they obviously did.
    /// Reduce-Motion always takes the shortcut path.
    private func handleBackTap() {
        guard !isClosing else { return }

        let triggerHostDismiss = {
            if let onCustomDismiss {
                onCustomDismiss()
            } else {
                dismiss()
            }
        }

        // Decide whether to play the reverse curl or skip straight to
        // the host's collapse.
        let isQuickBack: Bool = {
            guard let landed = firstCardPageLandedAt else { return false }
            return Date().timeIntervalSince(landed) < 2.5
        }()
        let shouldReverseCurl =
            entryFromGrid &&
            currentPage > 0 &&
            !reduceMotion &&
            !isQuickBack

        if shouldReverseCurl {
            // Reverse curl → cover.
            // We hide the chrome immediately to focus on the cover.
            isChromeVisible = false
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                currentPage = 0
            }

            // Wait for the slowed page curl to settle before handing control
            // back to the host's collapse overlay. The PageCurlView layer speed
            // stretches the turn to roughly 1.1s; cutting away earlier makes
            // the close feel like a size snap.
            Task {
                try? await Task.sleep(nanoseconds: 1_120_000_000)
                await MainActor.run {
                    isClosing = true
                    triggerHostDismiss()
                }
            }
        } else {
            // Shortcut path: hide chrome and hand the host control
            // immediately so its collapse-from-page-frame morph runs
            // straight away. The host owns the cover-back-to-grid morph;
            // we just need to get out of the way fast.
            isChromeVisible = false
            isClosing = true
            triggerHostDismiss()
        }
    }
    /// Cached USD price per "cardID|variantKey" — refreshed whenever the slot
    /// set or pricing provider changes. Used by the bottom stats bar to show
    /// a live total value and by the page-info bar for per-page value.
    @State private var slotUSDValues: [String: Double] = [:]
    /// Cached 7-day percent change per "cardID|variantKey", from
    /// ``PricingService.priceTrends``. Combined with `slotUSDValues` to
    /// produce the binder's weekly USD swing for the social row.
    @State private var slotChange7d: [String: Double] = [:]
    /// Identifier of the published `SharedContent` row for this binder, when
    /// it has been shared. `nil` while loading or when the binder is private.
    @State private var sharedContentID: UUID? = nil
    /// Profiles of users who have upvoted the published binder. Empty when
    /// the binder isn't shared yet or hasn't been voted on.
    @State private var likers: [SocialProfile] = []
    /// Total upvote count from the vote aggregate — may be larger than
    /// `likers.count` if we only fetched a partial page of voters.
    @State private var totalLikeCount: Int = 0

    private var layout: BinderPageLayout { binder.layout }
    private var headerIconColor: Color { colorScheme == .dark ? .white : .black }
    private var editTagColor: Color { colorScheme == .dark ? .white : .black }

    private var sortedSlots: [BinderSlot] {
        binder.slotList.sorted { $0.position < $1.position }
    }

    private var slotsPerPage: Int { layout.slotsPerPage ?? 9 }
    private var cols: Int { layout.columns }
    private var rows: Int { layout.rows }
    private var shareAutoSyncSignature: String {
        let slotSignature = binder.slotList
            .sorted { $0.position < $1.position }
            .map { "\($0.position)|\($0.cardID)|\($0.variantKey)|\($0.cardName)" }
            .joined(separator: ";")
        return [
            binder.title,
            binder.colour,
            binder.texture,
            binder.pageLayout,
            binder.showCardPreview ? "1" : "0",
            binder.showValueOnCover ? "1" : "0",
            binder.showPriceOverlay ? "1" : "0",
            binder.titleTextColor,
            binder.titleFontStyle,
            binder.embossedCardID ?? "",
            binder.embossedPokemonImageUrl ?? "",
            binder.embossMode,
            slotSignature
        ].joined(separator: "|")
    }

    /// Number of card pages (the playmat surfaces). Doesn't count the
    /// optional binder-front cover page — see ``totalPageCount``.
    private var cardPageCount: Int {
        let maxPos = sortedSlots.last?.position ?? -1
        return max(1, Int(ceil(Double(maxPos + 1) / Double(slotsPerPage))))
    }

    /// Total pages handed to ``PageCurlView``. When entering from the grid we
    /// prepend the binder-front cover at index 0; otherwise the count is just
    /// the regular card pages.
    private var totalPageCount: Int {
        cardPageCount + (entryFromGrid ? 1 : 0)
    }

    /// Convert a `PageCurlView` page index to the underlying card-page index.
    /// When entering from the grid, page 0 is the cover so card pages begin
    /// at 1 and we subtract one to get the real card-page index.
    private func cardPageIndex(for pageIdx: Int) -> Int {
        entryFromGrid ? max(0, pageIdx - 1) : pageIdx
    }

    /// `true` when the given `PageCurlView` page index should render the
    /// binder front cover instead of a card-grid page.
    private func isCoverPage(_ pageIdx: Int) -> Bool {
        entryFromGrid && pageIdx == 0
    }

    private func positions(for cardPage: Int) -> [Int] {
        let start = cardPage * slotsPerPage
        return Array(start..<(start + slotsPerPage))
    }

    var body: some View {
        VStack(spacing: 0) {
            binderHeader
                .opacity(isChromeVisible ? 1 : 0)
                .offset(y: isChromeVisible ? 0 : -20)
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: isChromeVisible)
            ZStack(alignment: .top) {
                if !isEditing || isModeTransitioning {
                    viewModeContent
                        .opacity(isEditing ? 0 : 1)
                        .scaleEffect(isEditing ? 0.982 : 1, anchor: .center)
                        .offset(y: isEditing ? -10 : 0)
                        .allowsHitTesting(!isEditing && isChromeVisible)
                        .accessibilityHidden(isEditing)
                        .compositingGroup()
                }

                if isEditing || isModeTransitioning {
                    editContent
                        .opacity(isEditing ? 1 : 0)
                        .scaleEffect(isEditing ? 1 : 1.018, anchor: .top)
                        .offset(y: isEditing ? 0 : 22)
                        .allowsHitTesting(isEditing)
                        .accessibilityHidden(!isEditing)
                        .compositingGroup()
                }
            }
            .animation(.spring(response: 0.44, dampingFraction: 0.9), value: isEditing)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(Color(uiColor: .systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .overlay {
            if let slot = viewingSlot, let card = cardsByID[slot.cardID] {
                BinderCardViewer(
                    card: card,
                    onViewDetails: {
                        viewingSlot = nil
                        detailCard = card
                    },
                    onDismiss: {
                        viewingSlot = nil
                    }
                )
                .ignoresSafeArea(.all)
                .zIndex(50)
                .transition(.identity)
            }
        }
        .sheet(item: $detailCard) { card in
            CardDetailSheet(cards: [card], startIndex: 0)
                .environment(services)
        }
        .animation(.easeInOut(duration: 0.25), value: viewingSlot?.id)
        .onAppear {
            Task {
                await loadCards()
                await refreshShareStatus()
            }
            // Cover-hold + auto page-turn. When the binder was opened from
            // the grid, page 0 is the cover and we hold for ~1s after the
            // open morph settles before advancing to page 1 — that flips
            // ``currentPage`` through the existing ``PageCurlView`` curl
            // animation, which the user wanted preserved verbatim.
            //
            // The 1.4s budget reserves ~400ms for the host's morph + ~1s of
            // pure hold so the cover read time matches the user's spec
            // ("approximately 1 second" *after* the cover lands).
            if entryFromGrid && !hasAutoAdvancedFromCover {
                currentPage = 0

                // Reduce-Motion path: skip the cover hold + auto page
                // curl entirely. Land on page 1 with chrome visible,
                // no animation. Less delight, much less vestibular
                // stress.
                if reduceMotion {
                    Task {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        await MainActor.run {
                            hasAutoAdvancedFromCover = true
                            if cardPageCount > 0 { currentPage = 1 }
                            firstCardPageLandedAt = Date()
                            withAnimation(.easeIn(duration: 0.25)) {
                                isChromeVisible = true
                            }
                        }
                    }
                    return
                }

                Task {
                    // Cover-hold + auto page-turn.
                    // The 1.4s budget reserves ~400ms for the host's morph + ~1s of
                    // pure hold so the cover read time matches the user's spec.
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    await MainActor.run {
                        guard !hasAutoAdvancedFromCover else { return }
                        innerPageRevealScale = 0.94
                        hasAutoAdvancedFromCover = true
                        if cardPageCount > 0 {
                            currentPage = 1
                        }
                        // Light haptic the moment the page-curl kicks
                        // off — the user feels the page lift even
                        // before they see it move. Pairs with the
                        // ``.soft`` haptic the host fires when the
                        // open morph lands.
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }

                    try? await Task.sleep(nanoseconds: 180_000_000)
                    await MainActor.run {
                        withAnimation(.easeOut(duration: 0.55)) {
                            innerPageRevealScale = 1
                        }
                    }

                    // Stamp the moment the page-curl landed so
                    // ``handleBackTap`` can decide whether a back tap
                    // counts as a "quick back" (skip the reverse curl).
                    // ~1.1s for the curl itself.
                    try? await Task.sleep(nanoseconds: 1_100_000_000)
                    await MainActor.run {
                        firstCardPageLandedAt = Date()
                    }

                    // Reveal the chrome (buttons/stats) only AFTER the page
                    // has fully turned. ``PageCurlView`` runs the curl through
                    // ``UIPageViewController`` at ``layer.speed = 0.55`` which
                    // gives a ~1.1s curl; we then wait an additional 0.5s so
                    // the user has a moment to take in the first page before
                    // the chrome flies in.
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await MainActor.run {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            isChromeVisible = true
                        }
                    }
                }
            } else {
                // Not from grid? Show chrome immediately.
                isChromeVisible = true
            }
        }
        .onChange(of: binder.slotList.count) { Task { await loadCards() } }
        .onChange(of: shareAutoSyncSignature) { _, _ in
            services.socialShare.scheduleAutoSync(binder: binder)
            services.scheduleLibraryCloudBackup()
            Task { await refreshShareStatus() }
        }
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
        .sheet(isPresented: $showShareSettings) {
            SocialShareSheet(item: .binder(binder))
                .environment(services)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
    }

    // MARK: - Header

    private func setEditing(_ editing: Bool) {
        guard editing != isEditing else { return }
        isModeTransitioning = true
        withAnimation(.spring(response: 0.44, dampingFraction: 0.9)) {
            isEditing = editing
        }

        Task {
            try? await Task.sleep(nanoseconds: 560_000_000)
            await MainActor.run {
                if isEditing == editing {
                    isModeTransitioning = false
                }
            }
        }
    }

    private var viewModeContent: some View {
        ZStack(alignment: .bottom) {
            viewContent
                // Lock swipe gestures while the open sequence is
                // still running. Without this guard a fast user
                // can flick the page mid-morph, racing against
                // the auto cover→page-1 advance and leaving the
                // ``UIPageViewController`` in a confused state.
                // Once chrome lands the user is firmly in the
                // detail view and the page-curl is theirs again.
                .allowsHitTesting(isChromeVisible)

            VStack(spacing: 12) {
                if !layout.isFreeScroll {
                    swipeHint
                        // Hide the swipe hint until the chrome has
                        // arrived too — there's nothing to swipe to
                        // during the cover-hold so promising one is
                        // a lie.
                        .opacity(isChromeVisible ? 1 : 0)
                        .animation(.easeOut(duration: 0.3), value: isChromeVisible)
                }

                bottomStatsBar
                    .opacity(isChromeVisible ? 1 : 0)
                    .offset(y: isChromeVisible ? 0 : 20)
                    .animation(.spring(response: 0.45, dampingFraction: 0.8), value: isChromeVisible)
            }
            .allowsHitTesting(isChromeVisible)
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    /// Uses ``BindrPageHeader`` (the same component Social/Binders/Decks list
    /// pages use) so the binder detail screen's chrome lines up perfectly
    /// with the rest of the app's glass treatment. The colour-accent capsule
    /// stays as a per-binder flourish below the title.
    private var binderHeader: some View {
        VStack(spacing: 4) {
            BindrPageHeader(
                title: binder.title,
                leading: {
                    ChromeGlassCircleButton(accessibilityLabel: "Back") { handleBackTap() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                },
                trailing: {
                    HStack(spacing: 8) {
                        Menu {
                            Button {
                                showShareSettings = true
                            } label: {
                                Label(isSharedPublished ? "Manage Social Post" : "Post to Bindr Social", systemImage: "person.2.fill")
                            }

                            Button {
                                renderAndShareSnapshot()
                            } label: {
                                Label("Share Page Image", systemImage: "photo")
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(headerIconColor)
                        }
                        .modifier(ChromeGlassCircleGlyphModifier())
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                        .menuOrder(.fixed)
                        .accessibilityLabel("Share binder")

                        Button {
                            setEditing(!isEditing)
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
            )
            // Push the header down so it sits below the status bar. 
            // Fall back to 47pt (standard notch height) if the inset 
            // isn't reported correctly.
            .padding(.top, entryFromGrid ? (topSafeAreaInset > 0 ? topSafeAreaInset : 47) : 0)

            // Per-binder colour-accent capsule sits below the shared header
            // so the chrome layout stays uniform but each binder still gets
            // its identifying flourish.
            Capsule()
                .fill(binder.resolvedColour)
                .frame(width: 40, height: 3)
                .opacity(0.8)
                .padding(.bottom, 4)
        }
    }

    // MARK: - Bottom stats bar (Cards · Page Value · Binder Value)

    private var bottomStatsBar: some View {
        HStack(spacing: 10) {
            statCell(value: "\(filledCardCount)", label: "CARDS")
            statDivider
            statCell(value: formattedPageValue, label: "PAGE VALUE")
            statDivider
            statCell(value: formattedTotalValue, label: "BINDER VALUE")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.15 : 0.3),
                                    Color.white.opacity(colorScheme == .dark ? 0.05 : 0.1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.1), radius: 15, x: 0, y: 8)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
                .multilineTextAlignment(.center)
            Text(label)
                .font(.caption2.weight(.medium))
                .tracking(1.1)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 4)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(colorScheme == .dark ? 0.24 : 0.18))
            .frame(width: 1, height: 30)
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
        let pageVerticalOffset: CGFloat = -40
        return VStack(spacing: 0) {
            PageCurlView(
                pageCount: totalPageCount,
                currentPage: $currentPage,
                isTurning: $isPageTurning,
                pageBackgroundColor: .systemBackground,
                contentVersion: binder.slotList.count
            ) { pageIdx in
                if isCoverPage(pageIdx) {
                    coverPageSurface(pageSize: pageSize)
                } else {
                    pageSurface(pageIdx: cardPageIndex(for: pageIdx), pageSize: pageSize)
                        .scaleEffect(innerPageScale(for: pageIdx), anchor: .center)
                }
            }
            .frame(width: pageSize.width, height: pageSize.height)
            .offset(y: pageVerticalOffset) // Shift binder up so it is visually balanced between header and floating bottom bar.
            .background(
                GeometryReader { pgGeo in
                    let layoutFrame = pgGeo.frame(in: .named("bindersRoot"))
                    let reportedFrame = isCoverPage(currentPage)
                        ? coverFrame(in: pageSize, pageOrigin: layoutFrame.origin)
                        : layoutFrame
                    let visualFrame = reportedFrame.offsetBy(dx: 0, dy: pageVerticalOffset)
                    Color.clear.preference(
                        key: BinderPageFramePreferenceKey.self,
                        value: visualFrame
                    )
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    /// Renders the binder's front cover so it can sit as page 0 of
    /// ``PageCurlView``. The cover itself is laid out at the cover's
    /// natural A4 aspect (centred inside the wider page area) — that's
    /// what lets the open/close morph use a single uniform scale and
    /// land cleanly on the A4 grid cell without a height pop. The
    /// surrounding ``pageSize`` rectangle stays as the curl's "page" so
    /// ``UIPageViewController`` flips between equally-sized pages.
    private func coverPageSurface(pageSize: CGSize) -> some View {
        // Mirror the grid cell's logic: hide the value entirely on empty
        // binders or when the user has switched the cover-value setting
        // off.
        let value: String? = preloadedValueText ?? ((binder.showValueOnCover && !binder.slotList.isEmpty)
            ? formattedTotalValue
            : nil)

        let coverRect = coverFrame(in: pageSize)

        return ZStack {
            // The page itself is the system background — same colour
            // ``PageCurlView`` is initialised with — so the cover sits
            // visually flush within the curl's "page" rectangle.
            Color(uiColor: .systemBackground)
            BinderCoverView(
                binder: binder,
                compact: false,
                valueText: value
            )
            .peekingURLsOverride(preloadedPeekingURLs)
            .frame(width: coverRect.width, height: coverRect.height)
            .position(x: coverRect.midX, y: coverRect.midY)
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .clipped()
    }

    private func coverFrame(in pageSize: CGSize, pageOrigin: CGPoint = .zero) -> CGRect {
        let coverAspect: CGFloat = 0.707
        let pageAspect = pageSize.width / max(pageSize.height, 1)
        let coverWidth: CGFloat
        let coverHeight: CGFloat
        if pageAspect < coverAspect {
            coverWidth = pageSize.width
            coverHeight = coverWidth / coverAspect
        } else {
            coverHeight = pageSize.height
            coverWidth = coverHeight * coverAspect
        }
        return CGRect(
            x: pageOrigin.x + (pageSize.width - coverWidth) / 2,
            y: pageOrigin.y + (pageSize.height - coverHeight) / 2,
            width: coverWidth,
            height: coverHeight
        )
    }

    private func innerPageScale(for pageIdx: Int) -> CGFloat {
        entryFromGrid && pageIdx == 1 && hasAutoAdvancedFromCover ? innerPageRevealScale : 1
    }

    private func binderPageSize(in available: CGSize) -> CGSize {
        let horizontalPadding: CGFloat = 32
        let verticalPadding: CGFloat = 40 // More vertical breathing room
        let slotSpacing: CGFloat = 8
        // These must match the chrome inside `pageSurface`:
        //   .padding(.leading, 32)  + .padding(.trailing, 14) = 46pt
        //   .padding(.top, 14)     + .padding(.bottom, 14)   = 28pt
        // The leading inset reserves the binder-ring spine.
        let surfaceHorizontalChrome: CGFloat = 46
        let surfaceVerticalChrome: CGFloat = 28
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

            // 2. Card grid — leading padding bumped to 32 to clear the ring
            //    spine; top/bottom padding match for even vertical margins.
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
            .padding(.leading, 32)
            .padding(.trailing, 14)
            .padding(.top, 14)
            .padding(.bottom, 14)

            // 3. Three-ring binder spine on the left edge — the single change
            //    that turns the page from "felt mat" into "actual binder".
            //    Sits above the grid so the rings appear in the gutter even
            //    when cards crowd toward the edge.
            HStack {
                binderRingSpine(pageHeight: pageSize.height)
                    .padding(.leading, 8)
                Spacer(minLength: 0)
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
        .foregroundStyle(Color.primary.opacity(0.7))
        .frame(maxWidth: .infinity)
    }

    // MARK: - Binder ring spine

    /// Three metal rings running down the left edge of the page. The single
    /// most impactful piece of binder-metaphor chrome — turns the surface
    /// from "felt playmat" into "object you flip pages of".
    private func binderRingSpine(pageHeight: CGFloat) -> some View {
        ZStack(alignment: .top) {
            ForEach(Array(BinderRingGuide.normalizedYPositions.enumerated()), id: \.offset) { _, yPosition in
                binderRing()
                    .position(x: 8, y: pageHeight * yPosition)
            }
        }
        .frame(width: 16, height: pageHeight)
        .allowsHitTesting(false)
    }

    /// One ring, drawn as a stack: dark inner hole, metallic gradient body,
    /// crescent highlight on top to suggest light catching the metal.
    private func binderRing() -> some View {
        ZStack {
            // 1. Outer rim — metallic gradient (dark grey → mid grey → almost
            //    black) gives the ring its silhouette and dimension.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.62),
                            Color(white: 0.30),
                            Color(white: 0.10)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 16, height: 16)
                .shadow(color: .black.opacity(0.55), radius: 1.2, x: 0, y: 1.2)

            // 2. Inner hole — pure dark so the felt colour reads through it
            //    just enough to feel like a real hole.
            Circle()
                .fill(Color.black.opacity(0.92))
                .frame(width: 8, height: 8)
                .overlay {
                    Circle()
                        .stroke(Color.black.opacity(0.6), lineWidth: 0.5)
                        .blur(radius: 0.8)
                }

            // 3. Crescent highlight — bright arc on the upper edge of the
            //    ring catches the eye and reads instantly as polished metal.
            Circle()
                .trim(from: 0.62, to: 0.92)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.75),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                )
                .frame(width: 14, height: 14)
        }
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

            // No add affordance in view mode: empty pockets should still
            // read as real binder sleeves until the user enters edit mode.
        }
    }

    @ViewBuilder
    private func viewSlotCell(slot: BinderSlot) -> some View {
        let card = cardsByID[slot.cardID]
        let imageURL = card.map { AppConfiguration.imageURL(relativePath: $0.displayImageSrc) }
        let cardCornerRadius: CGFloat = 4
        let priceKey = slotValueKey(slot)
        let usdPrice = slotUSDValues[priceKey]
        Button {
            if !isEditing { viewingSlot = slot }
        } label: {
            ZStack(alignment: .topTrailing) {
                // Card back/face
                CachedAsyncImage(url: imageURL, targetSize: CGSize(width: 220, height: 308)) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                        .fill(Color(uiColor: .systemGray5))
                }
                .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))

                // Inset top highlight — simulates light catching the card edge.
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
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

                // Price badge — compact capsule at the bottom of the card
                if binder.showPriceOverlay, let usd = usdPrice, usd > 0 {
                    priceBadge(usd: usd)
                }
            }
        }
        .buttonStyle(BinderCardButtonStyle())
    }

    private func priceBadge(usd: Double) -> some View {
        let text = compactPriceLabel(usd: usd)
        return Text(text)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.72),
                                Color.black.opacity(0.58)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            .padding([.bottom, .trailing], 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    /// Compact price format matching the app currency but dropping the symbol
    /// when space is tight so the capsule stays tiny. Returns e.g. "£12.50" or
    /// "$1,299" (whole amounts above 1000 drop decimals).
    private func compactPriceLabel(usd: Double) -> String {
        let display = services.priceDisplay.currency
        let amount = display == .gbp ? usd * services.pricing.usdToGbp : usd
        if amount >= 1000 {
            return String(format: "\(display.symbol)%.0f", amount)
        }
        return String(format: "\(display.symbol)%.2f", amount)
    }

    // MARK: - Edit mode

    private var editContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                editToolbar

                if layout.isFreeScroll {
                    editGrid(positions: Array(0..<max(sortedSlots.count + 3, slotsPerPage)))
                } else {
                    ForEach(0..<(cardPageCount + 1), id: \.self) { pageIdx in
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
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)

            Button {
                showColourPicker = true
            } label: {
                Label("Binder Style", systemImage: "paintpalette")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)

            Spacer()

            if !layout.isFreeScroll {
                Button {
                    addPage()
                } label: {
                    Label("Add Page", systemImage: "plus.rectangle.on.rectangle")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.regular)
        .tint(editTagColor)
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
                    AppConfiguration.imageURL(relativePath: $0.displayImageSrc)
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
                        ? bindrAccent.opacity(0.18)
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
        // Navigate to the last page so the user sees the new empty page.
        // The page-curl indexes through ``totalPageCount`` (which includes
        // the cover when entered from the grid) so the destination index is
        // the count itself — that's the new last page.
        withAnimation { currentPage = totalPageCount }
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
        var changes: [String: Double] = [:]

        // Pricing and 7-day trend lookups are independent per slot, so we
        // run them concurrently per slot and serially across slots — which
        // matches how the rest of the detail view paces this kind of work.
        for slot in binder.slotList {
            guard let card = cardsByID[slot.cardID] else { continue }
            async let usdPrice = services.pricing.usdPriceForVariant(
                for: card,
                variantKey: slot.variantKey
            )
            async let trends = services.pricing.priceTrends(for: card)

            if let usd = await usdPrice {
                values[slotValueKey(slot)] = usd
            }
            if let t = await trends {
                // Binder slots don't track grade; prefer "raw", then any
                // grade for this variant, then the trend's primary entry.
                let raw = t.changes(for: slot.variantKey, grade: "raw").change7d
                let anyGrade = t.allVariants[slot.variantKey]?.values
                    .compactMap(\.change7d).first
                if let pct = raw ?? anyGrade ?? t.change7d {
                    changes[slotValueKey(slot)] = pct
                }
            }
        }
        slotUSDValues = values
        slotChange7d = changes
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
        // ``currentPage`` indexes into ``PageCurlView``'s pages — when entering
        // from the grid that includes a cover at index 0, so translate back
        // to the underlying card page before reading its slot positions.
        let cardPage = cardPageIndex(for: currentPage)
        let positions = Set(positions(for: cardPage))
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
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = display.symbol
        formatter.maximumFractionDigits = amount >= 1000 ? 0 : 2
        return formatter.string(from: NSNumber(value: amount)) ?? ""
    }

    private func refreshShareStatus() async {
        do {
            let snapshot = try await services.socialShare.shareSnapshot(for: binder)
            isSharedPublished = snapshot.isPublished
            sharedContentID = snapshot.sharedContent?.id
            await refreshLikers()
        } catch {
            isSharedPublished = false
            sharedContentID = nil
            likers = []
            totalLikeCount = 0
        }
    }

    /// Loads the upvoter list for the published binder so the social row can
    /// show avatar bubbles. Skipped entirely when the binder is private —
    /// there's no `SharedContent` row to query reactions against. Best-effort:
    /// any network failure leaves the row empty rather than blocking the view.
    private func refreshLikers() async {
        guard let contentID = sharedContentID else {
            likers = []
            totalLikeCount = 0
            return
        }
        do {
            async let aggregateTask = services.socialFeed.fetchVoteAggregate(for: contentID)
            async let votesTask = services.socialFeed.fetchVotes(for: contentID)
            let (aggregate, votes) = try await (aggregateTask, votesTask)
            // Only include upvotes — downvotes don't belong on a "who liked
            // this" row even though the same reactions endpoint serves them.
            let profiles = votes
                .filter { $0.voteType == .upvote }
                .compactMap { $0.actor }
            likers = profiles
            totalLikeCount = aggregate.upvoteCount
        } catch {
            likers = []
            totalLikeCount = 0
        }
    }

    /// Sums each slot's 7-day USD change. The trend feed gives us a percent;
    /// converting back to dollars via `current - current/(1+pct/100)` yields
    /// the actual dollar amount the card has gained or lost in the last week.
    /// Returns `nil` until at least one slot has both a price and a trend so
    /// the UI doesn't briefly flash a misleading "£0".
    private var weeklyUSDChange: Double? {
        var total: Double = 0
        var anyResolved = false
        for slot in binder.slotList {
            let key = slotValueKey(slot)
            guard let current = slotUSDValues[key], let pct = slotChange7d[key] else { continue }
            let denom = 1.0 + (pct / 100.0)
            guard denom != 0 else { continue }
            let delta = current - (current / denom)
            total += delta
            anyResolved = true
        }
        return anyResolved ? total : nil
    }

    // MARK: - Share as image

    /// Renders the currently visible binder page (or cover) as a snapshot image
    /// with a "Bindr" branded watermark, then opens the system share sheet.
    private func renderAndShareSnapshot() {
        let pageSize = binderPageSize(in: UIScreen.main.bounds.size)
        let isCover = entryFromGrid && currentPage == 0

        let snapshotView = ZStack {
            if isCover {
                let coverRect = coverFrame(in: pageSize)
                let value: String? = (binder.showValueOnCover && !binder.slotList.isEmpty)
                    ? formattedTotalValue
                    : nil
                Color(uiColor: .systemBackground)
                BinderCoverView(
                    binder: binder,
                    compact: false,
                    valueText: value
                )
                .peekingURLsOverride(preloadedPeekingURLs)
                .frame(width: coverRect.width, height: coverRect.height)
            } else {
                pageSurface(pageIdx: cardPageIndex(for: currentPage), pageSize: pageSize)
            }
        }
        .frame(width: pageSize.width, height: pageSize.height)

        let scale = UIScreen.main.scale
        let renderer = ImageRenderer(
            content: snapshotView
                .environment(\.colorScheme, .light)
        )
        renderer.scale = scale

        guard let baseImage = renderer.uiImage else { return }
        let subtitle = isCover ? binder.title : "\(binder.title) · Page \(cardPageIndex(for: currentPage) + 1)"
        let watermarked = applyBindrWatermark(to: baseImage, subtitle: subtitle)

        presentShareSheet(image: watermarked)
    }

    /// Presents the system share sheet (UIActivityViewController) from the
    /// topmost UIKit view controller. This approach is more reliable than
    /// embedding it in a SwiftUI sheet, especially on iPad.
    private func presentShareSheet(image: UIImage) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }

        let activityVC = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(
                x: topVC.view.bounds.midX,
                y: topVC.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }

        topVC.present(activityVC, animated: true)
    }

    /// Applies a "Bindr" branded tag to the bottom-right of the snapshot.
    private func applyBindrWatermark(to image: UIImage, subtitle: String) -> UIImage {
        let imageSize = image.size
        let scale = image.scale

        UIGraphicsBeginImageContextWithOptions(imageSize, false, scale)
        defer { UIGraphicsEndImageContext() }

        guard let ctx = UIGraphicsGetCurrentContext() else { return image }

        image.draw(at: .zero)

        let watermarkText = "Bindr"
        let fontSize: CGFloat = max(imageSize.width * 0.045, 16)
        let subtitleFontSize: CGFloat = max(fontSize * 0.42, 9)
        let padding: CGFloat = fontSize * 0.8
        let tagSize = CGSize(width: min(imageSize.width * 0.72, fontSize * 8.2), height: fontSize * 2.4)
        let tagOrigin = CGPoint(
            x: imageSize.width - tagSize.width - padding,
            y: imageSize.height - tagSize.height - padding
        )
        let tagRect = CGRect(origin: tagOrigin, size: tagSize)

        let bgPath = UIBezierPath(roundedRect: tagRect, cornerRadius: fontSize * 0.5)
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
        ctx.addPath(bgPath.cgPath)
        ctx.fillPath()

        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.25).cgColor)
        ctx.setLineWidth(0.5)
        ctx.addPath(bgPath.cgPath)
        ctx.strokePath()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.9),
            .paragraphStyle: paragraphStyle
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: subtitleFontSize, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.72),
            .paragraphStyle: paragraphStyle
        ]

        let textSize = watermarkText.size(withAttributes: attributes)
        let textOrigin = CGPoint(
            x: tagRect.midX - textSize.width / 2,
            y: tagRect.minY + fontSize * 0.35
        )
        watermarkText.draw(at: textOrigin, withAttributes: attributes)

        let clippedSubtitle = subtitle.count > 38 ? String(subtitle.prefix(35)) + "..." : subtitle
        let subtitleRect = CGRect(
            x: tagRect.minX + fontSize * 0.45,
            y: textOrigin.y + textSize.height + 1,
            width: tagRect.width - fontSize * 0.9,
            height: subtitleFontSize * 1.3
        )
        clippedSubtitle.draw(in: subtitleRect, withAttributes: subtitleAttributes)

        return UIGraphicsGetImageFromCurrentImageContext() ?? image
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

// MARK: - Page-area frame preference key

/// Reports the binder page-curl's page-area frame (in screen/global
/// coordinates) so the host (``BindersRootView``) can position its open/close
/// morph overlay over the same rectangle. The host reads it through a
/// `.onPreferenceChange` and animates the matched-geometry cover from the
/// grid cell frame to this rect, then back when the binder is closed.
struct BinderPageFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

// MARK: - Full-size card viewer with swipe-to-dismiss

private struct BinderCardViewer: View {
    let card: Card
    let onViewDetails: () -> Void
    let onDismiss: () -> Void

    @Environment(\.bindrAccent) private var bindrAccent
    @Environment(\.colorScheme) private var colorScheme
    @State private var offset: CGSize = .zero
    @State private var rotation: Double = 0
    @State private var opacity: Double = 1

    private var imageURL: URL? {
        let src = card.displayImageSrc
        return AppConfiguration.imageURL(relativePath: src)
    }

    private var dragDistance: CGFloat {
        sqrt(offset.width * offset.width + offset.height * offset.height)
    }

    var body: some View {
        ZStack {
            Color.black.opacity((colorScheme == .dark ? 0.78 : 0.64) * opacity)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            RadialGradient(
                colors: [
                    bindrAccent.opacity(colorScheme == .dark ? 0.30 : 0.22),
                    bindrAccent.opacity(colorScheme == .dark ? 0.12 : 0.08),
                    .clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 380
            )
            .ignoresSafeArea()
            .opacity(opacity)

            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(card.cardName)
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text("Binder card")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.58))
                            .textCase(.uppercase)
                            .tracking(1.4)
                    }

                    Spacer(minLength: 12)

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 14) {
                    CachedAsyncImage(url: imageURL, targetSize: CGSize(width: 650, height: 910)) { img in
                        img.resizable().scaledToFit()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(uiColor: .systemGray4))
                            .aspectRatio(5/7, contentMode: .fit)
                            .overlay { ProgressView().tint(.white) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.30), lineWidth: 1)
                    }
                    .shadow(color: bindrAccent.opacity(0.22), radius: 26, x: 0, y: 8)
                    .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 14)

                    Button {
                        onViewDetails()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("View Card Details")
                                .font(.system(size: 16, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .bindrAccentFill(bindrAccent, logoOpacity: 0.96)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.28), lineWidth: 1)
                        }
                        .shadow(color: bindrAccent.opacity(0.28), radius: 14, x: 0, y: 6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
            }
            .padding(.horizontal, 24)
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

// MARK: - Style picker sheet

struct BinderStylePickerSheet: View {
    private enum CoverDisplayMode: String, CaseIterable, Identifiable {
        case clean
        case cards
        case embossed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .cards: return "Cards"
            case .clean: return "Clean"
            case .embossed: return "Embossed"
            }
        }
    }

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var bindrAccent
    @Bindable var binder: Binder
    @State private var cardURLs: [URL?]? = nil
    @State private var slotImageURLs: [String: URL] = [:]
    @State private var pokemonQuery = ""
    @State private var coverDisplayMode: CoverDisplayMode = .cards
    private let layoutOptions: [BinderPageLayout] = [
        .fixed(rows: 2, columns: 2),
        .fixed(rows: 3, columns: 2),
        .fixed(rows: 3, columns: 3),
        .fixed(rows: 4, columns: 3),
        .fixed(rows: 3, columns: 4),
        .fixed(rows: 4, columns: 4)
    ]

    private var formattedTotalValue: String {
        let total = binder.slotList.compactMap { slot in
            // Basic price lookup if available
            return 0.0 // Simplified for now since we don't have easy access to the full pricing service here
        }.reduce(0, +)
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD" // Fallback
        return formatter.string(from: NSNumber(value: total)) ?? "$0.00"
    }

    private var hasEmbossSelection: Bool {
        binder.embossedCardID != nil || binder.embossedPokemonImageUrl != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    GeometryReader { proxy in
                        BinderCoverView(
                            binder: binder,
                            compact: false,
                            valueText: binder.showValueOnCover ? formattedTotalValue : nil
                        )
                        .peekingURLsOverride(cardURLs)
                        .frame(width: proxy.size.width * 0.6)
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: 320)
                    .padding(.horizontal, 24)

                    VStack(alignment: .leading, spacing: 16) {
                        stylePanel(title: "Binder style", icon: "swatchpalette") {
                            VStack(alignment: .leading, spacing: 16) {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                                    ForEach(BinderColourPalette.pickerOptions, id: \.name) { swatch in
                                        colorSwatchButton(swatch)
                                    }
                                }

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    ForEach(BinderTexture.allCases) { texture in
                                        textureButton(texture)
                                    }
                                }

                                Divider()

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("COVER TEXT")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)

                                    Picker("Title text color", selection: $binder.titleTextColor) {
                                        ForEach(BinderTitleTextColor.allCases) { option in
                                            Text(option.displayName).tag(option.rawValue)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .tint(colorScheme == .dark ? .white : .black)

                                    Picker("Title font", selection: $binder.titleFontStyle) {
                                        ForEach(BinderTitleFontStyle.allCases) { option in
                                            Text(option.displayName).tag(option.rawValue)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .tint(colorScheme == .dark ? .white : .black)
                                }

                                Divider()

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    ForEach(layoutOptions, id: \.self) { option in
                                        layoutButton(for: option)
                                    }

                                    Button {
                                        binder.pageLayout = BinderPageLayout.freeScroll.rawValue
                                    } label: {
                                        HStack {
                                            Image(systemName: "square.grid.3x3")
                                            Text("Free flow")
                                        }
                                        .font(.system(size: 13, weight: .medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(layout.isFreeScroll ? bindrAccent.opacity(0.1) : Color(uiColor: .tertiarySystemGroupedBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay {
                                            if layout.isFreeScroll {
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(bindrAccent, lineWidth: 1)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .gridCellColumns(3)
                                }
                            }
                        }

                        stylePanel(title: "Front cover", icon: "rectangle.portrait") {
                            VStack(spacing: 12) {
                                ForEach(CoverDisplayMode.allCases) { mode in
                                    coverModeRow(mode)
                                }

                                Divider()

                                Toggle(isOn: $binder.showValueOnCover) {
                                    Label {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Show value")
                                                .font(.subheadline.weight(.semibold))
                                            Text("Adds the collection value to the cover")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    } icon: {
                                        Image(systemName: "sterlingsign.circle")
                                            .foregroundStyle(bindrAccent)
                                    }
                                }
                                .tint(bindrAccent)

                                Toggle(isOn: $binder.showPriceOverlay) {
                                    Label {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Show card prices")
                                                .font(.subheadline.weight(.semibold))
                                            Text("Adds subtle market-price badges to binder page cards")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    } icon: {
                                        Image(systemName: "tag")
                                            .foregroundStyle(bindrAccent)
                                    }
                                }
                                .tint(bindrAccent)
                            }
                        }

                        if coverDisplayMode == .embossed {
                            stylePanel(title: "Embossed art", icon: "sparkles") {
                                VStack(alignment: .leading, spacing: 14) {
                                    Picker("Emboss Mode", selection: $binder.embossMode) {
                                        ForEach(BinderEmbossMode.allCases) { mode in
                                            Text(mode.displayName).tag(mode.rawValue)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .tint(colorScheme == .dark ? .white : .black)

                                    if binder.embossModeKind == .character {
                                        VStack(alignment: .leading, spacing: 10) {
                                            Text("Character")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)

                                            HStack {
                                                Image(systemName: "magnifyingglass")
                                                    .foregroundStyle(.secondary)
                                                TextField("Search Pokémon", text: $pokemonQuery)
                                                    .textInputAutocapitalization(.never)
                                                    .autocorrectionDisabled()
                                            }
                                            .padding(12)
                                            .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                            let allPokemon = services.cardData.nationalDexPokemonSorted()
                                            let filteredPokemon: [NationalDexPokemon] = {
                                                let q = pokemonQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                                                guard !q.isEmpty else { return allPokemon }
                                                return allPokemon.filter {
                                                    $0.name.lowercased().contains(q) ||
                                                    $0.displayName.lowercased().contains(q) ||
                                                    String($0.nationalDexNumber).contains(q)
                                                }
                                            }()

                                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 10)], spacing: 10) {
                                                if pokemonQuery.isEmpty {
                                                    Button {
                                                        binder.embossedPokemonImageUrl = nil
                                                        binder.embossedCardID = nil
                                                    } label: {
                                                        VStack(spacing: 5) {
                                                            Image(systemName: "slash.circle")
                                                                .font(.system(size: 22, weight: .semibold))
                                                                .foregroundStyle(.secondary)
                                                                .frame(height: 58)
                                                            Text("None")
                                                                .font(.caption2)
                                                                .lineLimit(1)
                                                        }
                                                        .foregroundStyle(.primary)
                                                        .padding(8)
                                                        .frame(maxWidth: .infinity)
                                                        .background(
                                                            binder.embossedPokemonImageUrl == nil && binder.embossedCardID == nil
                                                                ? bindrAccent.opacity(0.14)
                                                                : Color(uiColor: .tertiarySystemGroupedBackground),
                                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        )
                                                        .overlay {
                                                            if binder.embossedPokemonImageUrl == nil && binder.embossedCardID == nil {
                                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                                    .stroke(bindrAccent, lineWidth: 1.5)
                                                            }
                                                        }
                                                    }
                                                    .buttonStyle(.plain)
                                                }

                                                ForEach(filteredPokemon) { mon in
                                                    Button {
                                                        binder.embossedPokemonImageUrl = mon.imageUrl
                                                        binder.embossedCardID = nil
                                                    } label: {
                                                        VStack(spacing: 5) {
                                                            CachedAsyncImage(url: AppConfiguration.pokemonArtURL(imageFileName: mon.imageUrl)) { img in
                                                                img.resizable().scaledToFit()
                                                            } placeholder: {
                                                                Color.secondary.opacity(0.1)
                                                            }
                                                            .frame(height: 58)
                                                            Text(mon.displayName)
                                                                .font(.caption2)
                                                                .lineLimit(1)
                                                        }
                                                        .foregroundStyle(.primary)
                                                        .padding(8)
                                                        .frame(maxWidth: .infinity)
                                                        .background(binder.embossedPokemonImageUrl == mon.imageUrl ? bindrAccent.opacity(0.14) : Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                                        .overlay {
                                                            if binder.embossedPokemonImageUrl == mon.imageUrl {
                                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                                    .stroke(bindrAccent, lineWidth: 1.5)
                                                            }
                                                        }
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                            .task {
                                                if services.cardData.nationalDexPokemon.isEmpty {
                                                    await services.cardData.loadNationalDexPokemon()
                                                }
                                            }
                                        }
                                    } else if !binder.slotList.isEmpty {
                                        VStack(alignment: .leading, spacing: 10) {
                                            Text("Full card")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)

                                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 10)], spacing: 10) {
                                                Button {
                                                    binder.embossedCardID = nil
                                                    binder.embossedPokemonImageUrl = nil
                                                } label: {
                                                    VStack(spacing: 5) {
                                                        Image(systemName: "slash.circle")
                                                            .font(.system(size: 22, weight: .semibold))
                                                            .foregroundStyle(.secondary)
                                                            .frame(height: 76)
                                                        Text("None")
                                                            .font(.caption2)
                                                            .lineLimit(1)
                                                    }
                                                    .foregroundStyle(.primary)
                                                    .padding(8)
                                                    .frame(maxWidth: .infinity)
                                                    .background(
                                                        binder.embossedCardID == nil && binder.embossedPokemonImageUrl == nil
                                                            ? bindrAccent.opacity(0.14)
                                                            : Color(uiColor: .tertiarySystemGroupedBackground),
                                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    )
                                                    .overlay {
                                                        if binder.embossedCardID == nil && binder.embossedPokemonImageUrl == nil {
                                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                                .stroke(bindrAccent, lineWidth: 1.5)
                                                        }
                                                    }
                                                }
                                                .buttonStyle(.plain)

                                                ForEach(binder.slotList) { slot in
                                                    Button {
                                                        binder.embossedCardID = slot.cardID
                                                        binder.embossedPokemonImageUrl = nil
                                                    } label: {
                                                        VStack(spacing: 5) {
                                                            let url = slotImageURLs[slot.cardID]
                                                            CachedAsyncImage(url: url, targetSize: CGSize(width: 132, height: 184)) { img in
                                                                img.resizable()
                                                                    .aspectRatio(contentMode: .fill)
                                                            } placeholder: {
                                                                Color.secondary.opacity(0.1)
                                                            }
                                                            .frame(width: 58, height: 76)
                                                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                                            .overlay {
                                                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                                            }
                                                            Text(slot.cardName)
                                                                .font(.caption2)
                                                                .lineLimit(1)
                                                        }
                                                        .foregroundStyle(.primary)
                                                        .padding(8)
                                                        .frame(maxWidth: .infinity)
                                                        .background(
                                                            binder.embossedCardID == slot.cardID
                                                                ? bindrAccent.opacity(0.14)
                                                                : Color(uiColor: .tertiarySystemGroupedBackground),
                                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        )
                                                        .overlay {
                                                            if binder.embossedCardID == slot.cardID {
                                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                                    .stroke(bindrAccent, lineWidth: 1.5)
                                                            }
                                                        }
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                        }
                                    } else {
                                        Text("Add cards to this binder to select cover art.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 24)
            }
            .task {
                syncCoverDisplayModeFromBinder()
                await loadCardURLs()
                await loadSlotImageURLs()
            }
            .onChange(of: coverDisplayMode) { _, mode in
                applyCoverDisplayMode(mode)
            }
            .navigationTitle("Binder Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .bold()
                        .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var layout: BinderPageLayout {
        BinderPageLayout(rawValue: binder.pageLayout)
    }

    private func syncCoverDisplayModeFromBinder() {
        if binder.showCardPreview {
            coverDisplayMode = .cards
        } else if hasEmbossSelection {
            coverDisplayMode = .embossed
        } else {
            coverDisplayMode = .clean
        }
    }

    private func applyCoverDisplayMode(_ mode: CoverDisplayMode) {
        switch mode {
        case .cards:
            binder.showCardPreview = true
        case .clean:
            binder.showCardPreview = false
            binder.embossedCardID = nil
            binder.embossedPokemonImageUrl = nil
        case .embossed:
            binder.showCardPreview = false
        }
    }

    private func coverModeRow(_ mode: CoverDisplayMode) -> some View {
        let isSelected = coverDisplayMode == mode
        return Button {
            coverDisplayMode = mode
        } label: {
            HStack(spacing: 12) {
                Image(systemName: coverModeIcon(mode))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? bindrAccent : .secondary)
                    .frame(width: 34, height: 34)
                    .background(
                        (isSelected ? bindrAccent.opacity(0.14) : Color(uiColor: .tertiarySystemGroupedBackground)),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.subheadline.weight(.semibold))
                    Text(coverModeSubtitle(mode))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(bindrAccent)
                }
            }
            .foregroundStyle(.primary)
            .padding(12)
            .background(
                isSelected ? bindrAccent.opacity(0.08) : Color(uiColor: .tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? bindrAccent.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func coverModeIcon(_ mode: CoverDisplayMode) -> String {
        switch mode {
        case .cards: return "rectangle.stack.fill"
        case .clean: return "rectangle.portrait.fill"
        case .embossed: return "sparkles"
        }
    }

    private func coverModeSubtitle(_ mode: CoverDisplayMode) -> String {
        switch mode {
        case .cards: return "Fan the first cards across the cover"
        case .clean: return "Keep the material and title uncluttered"
        case .embossed: return "Press a card or character into the surface"
        }
    }

    private func colorSwatchButton(_ swatch: (name: String, color: Color)) -> some View {
        let isSelected = binder.colour == swatch.name
        return Button {
            binder.colour = swatch.name
        } label: {
            binderColourSwatch(name: swatch.name, color: swatch.color, size: 36)
                .overlay {
                    Circle()
                        .stroke(isSelected ? Color.primary.opacity(0.35) : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                }
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BinderColourPalette.displayName(for: swatch.name))
    }

    private func binderColourSwatch(name: String, color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .overlay {
                if name == BinderColourPalette.logoColourName {
                    Circle()
                        .fill(BinderColourPalette.logoGradient)
                }
            }
            .frame(width: size, height: size)
    }

    private func textureButton(_ texture: BinderTexture) -> some View {
        let isSelected = binder.texture == texture.rawValue
        return Button {
            binder.texture = texture.rawValue
        } label: {
            HStack(spacing: 8) {
                Image(systemName: texture.pickerSymbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(texture.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? bindrAccent : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                isSelected ? bindrAccent.opacity(0.10) : Color(uiColor: .tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(isSelected ? bindrAccent.opacity(0.55) : Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func stylePanel<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            } icon: {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(bindrAccent)
            }
            .foregroundStyle(.primary)

            content()
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func layoutButton(for option: BinderPageLayout) -> some View {
        let isSelected = layout == option
        Button {
            binder.pageLayout = option.rawValue
        } label: {
            VStack(spacing: 4) {
                gridIcon(for: option)
                    .font(.system(size: 16))
                Text("\(option.columns) × \(option.rows)")
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? bindrAccent.opacity(0.1) : Color(uiColor: .secondarySystemGroupedBackground))
            .foregroundStyle(isSelected ? bindrAccent : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(bindrAccent, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func gridIcon(for option: BinderPageLayout) -> Image {
        switch (option.columns, option.rows) {
        case (2, 2): return Image(systemName: "square.grid.2x2.fill")
        default: return Image(systemName: "square.grid.3x3.fill")
        }
    }

    private func loadCardURLs() async {
        let slots = binder.slotList.prefix(3)
        var urls: [URL?] = []
        
        for slot in slots {
            if let card = await services.cardData.loadCard(masterCardId: slot.cardID) {
                urls.append(AppConfiguration.imageURL(relativePath: card.displayImageSrc))
            } else {
                urls.append(nil)
            }
        }
        
        cardURLs = urls
    }

    private func loadSlotImageURLs() async {
        var result: [String: URL] = [:]
        for slot in binder.slotList {
            if let card = await services.cardData.loadCard(masterCardId: slot.cardID) {
                result[slot.cardID] = AppConfiguration.imageURL(relativePath: card.displayImageSrc)
            }
        }
        slotImageURLs = result
    }
}
