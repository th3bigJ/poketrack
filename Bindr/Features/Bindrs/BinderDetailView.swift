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
    @Query private var collectionItems: [CollectionItem]

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
    @State private var currentPage = 0
    @State private var viewingSlot: BinderSlot? = nil
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

            // Wait for the curl-back to settle before handing control
            // back to the host's collapse overlay.
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
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

    private var ownedCardIDs: Set<String> {
        Set(collectionItems.map { $0.cardID })
    }

    private var slotsPerPage: Int { layout.slotsPerPage ?? 9 }
    private var cols: Int { layout.columns }
    private var rows: Int { layout.rows }
    private var shareAutoSyncSignature: String {
        let slotSignature = binder.slotList
            .sorted { $0.position < $1.position }
            .map { "\($0.position)|\($0.cardID)|\($0.variantKey)|\($0.cardName)" }
            .joined(separator: ";")
        return "\(binder.title)|\(slotSignature)"
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
            if !isEditing {
                // Share/likers/weekly-change row — sits between the title
                // and the binder pages so it doesn't crowd the editing
                // surface. Tied to the same chrome flag as the header so
                // it appears together with the rest of the UI after the
                // cover-to-first-page curl.
                BinderSocialRow(
                    isPublished: isSharedPublished,
                    likers: likers,
                    totalLikeCount: totalLikeCount,
                    onShareTap: { showShareSettings = true },
                    onLikersTap: nil
                )
                .opacity(isChromeVisible ? 1 : 0)
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: isChromeVisible)
            }
            if isEditing {
                editContent
            } else {
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
                    if !layout.isFreeScroll {
                        swipeHint
                            .padding(.bottom, 8)
                            // Hide the swipe hint until the chrome has
                            // arrived too — there's nothing to swipe to
                            // during the cover-hold so promising one is
                            // a lie.
                            .opacity(isChromeVisible ? 1 : 0)
                            .animation(.easeOut(duration: 0.3), value: isChromeVisible)
                    }
                    Spacer(minLength: 0)
                }
                bottomStatsBar
                    .opacity(isChromeVisible ? 1 : 0)
                    .offset(y: isChromeVisible ? 0 : 20)
                    .animation(.spring(response: 0.45, dampingFraction: 0.8), value: isChromeVisible)
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
                .ignoresSafeArea(.all)
                .zIndex(50)
                .transition(.identity)
            }
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
                        Button {
                            showShareSettings = true
                        } label: {
                            Image(systemName: isSharedPublished ? "checkmark.circle.fill" : "square.and.arrow.up")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(isSharedPublished ? .green : headerIconColor)
                        }
                        .modifier(ChromeGlassCircleGlyphModifier())
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                        .accessibilityLabel(isSharedPublished ? "Shared binder settings" : "Share binder")

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

    /// Sits flush at the bottom of the binder page.
    /// The top "Page X of Y / Page value" bar was removed — page value moved
    /// here next to the binder-wide value, and "Add Card" lives on the
    /// header's edit button, so we don't need the pill any more.
    private var bottomStatsBar: some View {
        HStack(spacing: 10) {
            statCell(value: "\(filledCardCount)", label: "CARDS")
            statDivider
            statCell(value: formattedPageValue, label: "PAGE VALUE")
            statDivider
            statCell(value: formattedTotalValue, label: "BINDER VALUE")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(
            ZStack {
                Rectangle()
                    .fill(.thinMaterial)
                LinearGradient(
                    colors: [
                        Color.black.opacity(colorScheme == .dark ? 0.30 : 0.08),
                        Color.black.opacity(colorScheme == .dark ? 0.12 : 0.03)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.18))
                        .frame(height: 1)
                }
        )
        .padding(.bottom, entryFromGrid ? bottomSafeAreaInset : 0)
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
                }
            }
            .frame(width: pageSize.width, height: pageSize.height)
            .background(
                // Report the page-area frame in screen coordinates so the
                // hosting screen (BindersRootView) can align its open/close
                // morph overlay to the same rectangle.
                GeometryReader { pgGeo in
                    Color.clear.preference(
                        key: BinderPageFramePreferenceKey.self,
                        value: pgGeo.frame(in: .global)
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

        // Lay the cover out at A4 aspect, fitted inside ``pageSize``.
        // Same maths as ``BinderOpenContainer.coverTargetFrame`` so the
        // moment the morph overlay fades, the page-0 cover sits at the
        // exact same rectangle and the hand-off is invisible.
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
            .frame(width: coverWidth, height: coverHeight)
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .clipped()
    }

    private func binderPageSize(in available: CGSize) -> CGSize {
        let horizontalPadding: CGFloat = 32
        let verticalPadding: CGFloat = 40 // More vertical breathing room
        let slotSpacing: CGFloat = 8
        // These must match the chrome inside `pageSurface`:
        //   .padding(.leading, 32)  + .padding(.trailing, 14) = 46pt
        //   .padding(.top, 30)      + .padding(.bottom, 14)   = 44pt
        // The leading inset reserves the binder-ring spine; the top inset
        // reserves the foil-stamped title strip.
        let surfaceHorizontalChrome: CGFloat = 46
        let surfaceVerticalChrome: CGFloat = 44
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

            // 2. Foil-stamped binder title — sits in the top strip above the
            //    grid. Tinted with the binder's accent so each binder feels
            //    distinct, with a layered shadow stack to read as embossed
            //    foil pressed into the playmat.
            VStack(spacing: 0) {
                foilStampedTitle
                    .padding(.top, 10)
                    .padding(.leading, 32) // skip past the ring spine
                    .padding(.trailing, 14)
                Spacer(minLength: 0)
            }

            // 3. Card grid — leading padding bumped to 32 to clear the ring
            //    spine; top padding bumped to 30 to clear the title strip.
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
            .padding(.top, 30)
            .padding(.bottom, 14)

            // 4. Three-ring binder spine on the left edge — the single change
            //    that turns the page from "felt mat" into "actual binder".
            //    Sits above the grid so the rings appear in the gutter even
            //    when cards crowd toward the edge.
            HStack {
                binderRingSpine(pageHeight: pageSize.height)
                    .padding(.leading, 8)
                Spacer(minLength: 0)
            }

            // 5. Page-turn dimming overlay (existing behaviour)
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
        // Distribute three rings vertically with generous breathing room.
        // Inset the spine slightly from the top/bottom to mimic the metal
        // hardware position on a real ringed binder.
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            binderRing()
            Spacer(minLength: 0)
            binderRing()
            Spacer(minLength: 0)
            binderRing()
            Spacer(minLength: 0)
        }
        .frame(width: 16)
        .padding(.vertical, max(20, pageHeight * 0.10))
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

    // MARK: - Foil-stamped title

    /// Binder title rendered as if it's been pressed into the playmat with
    /// coloured foil. Tinted with `binder.resolvedColour`, with a layered
    /// shadow stack (subtle white highlight above + dark shadow below + soft
    /// outer glow in the accent colour) that reads as embossed metallic ink.
    private var foilStampedTitle: some View {
        let title = binder.title.uppercased()
        let accent = binder.resolvedColour
        return Text(title)
            .font(.system(size: 11, weight: .black, design: .serif))
            .tracking(2.6)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        accent.opacity(0.95),
                        accent.opacity(0.55)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            // Embossed look: tiny white highlight above the strokes, a darker
            // shadow below, plus a soft accent-coloured halo around the whole
            // word so the foil "glows" against the felt.
            .shadow(color: Color.white.opacity(0.20), radius: 0.4, x: 0, y: -0.6)
            .shadow(color: Color.black.opacity(0.55), radius: 0.5, x: 0, y: 0.7)
            .shadow(color: accent.opacity(0.35), radius: 4, x: 0, y: 0)
            .frame(maxWidth: .infinity, alignment: .center)
            .allowsHitTesting(false)
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
        let card = cardsByID[slot.cardID]
        let imageURL = card.map { AppConfiguration.imageURL(relativePath: $0.imageLowSrc) }
        let cardCornerRadius: CGFloat = 4
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

// MARK: - Style picker sheet

struct BinderStylePickerSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var bindrAccent
    @Bindable var binder: Binder
    @State private var cardURLs: [URL?] = [nil, nil, nil]
    @State private var slotImageURLs: [String: URL] = [:]
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Preview
                    GeometryReader { proxy in
                        BinderCoverView(
                            binder: binder,
                            compact: false,
                            valueText: binder.showValueOnCover ? formattedTotalValue : nil
                        )
                        .frame(width: proxy.size.width * 0.6)
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: 320)
                    .padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("LAYOUT")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

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
                                    .background(layout.isFreeScroll ? bindrAccent.opacity(0.1) : Color(uiColor: .secondarySystemGroupedBackground))
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
                            .tint(colorScheme == .dark ? .white : .black)
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
                            Text("TITLE")
                                .font(.caption.bold())
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
                            .tint(colorScheme == .dark ? .white : .black)

                            Toggle(isOn: $binder.showValueOnCover) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Show value on cover")
                                        .font(.subheadline.weight(.medium))
                                    Text("Display the binder value label on the front")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tint(colorScheme == .dark ? .white : .black)
                        }

                        // NEW: Cover Art Feature
                        VStack(alignment: .leading, spacing: 12) {
                            Text("COVER ART")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            Picker("Art Style", selection: $binder.showCardPreview) {
                                Text("3-Card Fan").tag(true)
                                Text("Embossed Design").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .tint(colorScheme == .dark ? .white : .black)

                            if !binder.showCardPreview {
                                // Emboss settings
                                Picker("Emboss Mode", selection: $binder.embossMode) {
                                    ForEach(BinderEmbossMode.allCases) { mode in
                                        Text(mode.displayName).tag(mode.rawValue)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .tint(colorScheme == .dark ? .white : .black)

                                if !binder.slotList.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Select card to emboss")
                                            .font(.caption.bold())
                                            .foregroundStyle(.secondary)

                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 12) {
                                                // Option to have no art
                                                Button {
                                                    binder.embossedCardID = nil
                                                } label: {
                                                    VStack {
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .fill(Color.secondary.opacity(0.1))
                                                            .frame(width: 60, height: 84)
                                                            .overlay {
                                                                Image(systemName: "slash.circle")
                                                                    .foregroundStyle(.secondary)
                                                            }
                                                        Text("None")
                                                            .font(.caption2)
                                                    }
                                                }
                                                .buttonStyle(.plain)

                                                ForEach(binder.slotList) { slot in
                                                    Button {
                                                        binder.embossedCardID = slot.cardID
                                                    } label: {
                                                        VStack {
                                                            let url = slotImageURLs[slot.cardID]
                                                            CachedAsyncImage(url: url, targetSize: CGSize(width: 120, height: 168)) { img in
                                                                img.resizable()
                                                                    .aspectRatio(contentMode: .fill)
                                                            } placeholder: {
                                                                Color.secondary.opacity(0.1)
                                                            }
                                                            .frame(width: 60, height: 84)
                                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                                            .overlay {
                                                                if binder.embossedCardID == slot.cardID {
                                                                    RoundedRectangle(cornerRadius: 8)
                                                                        .stroke(bindrAccent, lineWidth: 2)
                                                                }
                                                            }
                                                            
                                                            Text(slot.cardName)
                                                                .font(.caption2)
                                                                .lineLimit(1)
                                                                .frame(width: 60)
                                                        }
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                            .padding(.horizontal, 2)
                                            .padding(.vertical, 4)
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
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 24)
            }
            .task {
                await loadCardURLs()
                await loadSlotImageURLs()
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
                urls.append(AppConfiguration.imageURL(relativePath: card.imageLowSrc))
            } else {
                urls.append(nil)
            }
        }
        
        while urls.count < 3 { urls.append(nil) }
        cardURLs = urls
    }

    private func loadSlotImageURLs() async {
        var result: [String: URL] = [:]
        for slot in binder.slotList {
            if let card = await services.cardData.loadCard(masterCardId: slot.cardID) {
                if let url = AppConfiguration.imageURL(relativePath: card.imageLowSrc) {
                    result[slot.cardID] = url
                }
            }
        }
        slotImageURLs = result
    }
}
