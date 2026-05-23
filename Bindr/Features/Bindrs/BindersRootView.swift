import SwiftUI
import SwiftData
import UIKit

struct BindersRootView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @Query(sort: \Binder.createdAt, order: .reverse) private var binders: [Binder]

    @Binding var showCreateSheet: Bool
    @State private var isEditing = false
    @State private var showPaywall = false
    @State private var binderToDelete: Binder?
    @State private var presentedBinder: Binder?
    @State private var showDeleteConfirm = false
    /// Measured height of the translucent floating header. Read by
    /// `safeAreaInset` so scroll content reserves exactly the right top
    /// gutter — keeps padding in lockstep with header changes (e.g. font
    /// scaling) without hard-coding a constant.
    @State private var bindersHeaderHeight: CGFloat = 64

    // MARK: Custom-presentation state
    //
    // We replaced ``fullScreenCover`` with an overlay-based presentation so
    // the open/close animation can sweep the other binders, morph the
    // tapped cover, and hand off to the existing page-curl. None of these
    // states are persisted — they're just the choreography for one tap.

    /// Per-binder global frames captured by the grid cells via
    /// ``BinderCellFramePreferenceKey``. The selected cell's frame becomes
    /// the morph "source"; other cells use it to compute their sweep
    /// direction.
    @State private var binderCellFrames: [UUID: CGRect] = [:]
    /// `true` while the open/close sequence is in flight; drives the sweep
    /// offsets and source-cell hide. Distinct from ``presentedBinder`` so we
    /// can keep this true through the entire close animation (which outlives
    /// the dismiss) and only flip it back to `false` at the very end.
    @State private var isPresentingBinder: Bool = false
    /// Identifier of the binder being presented (or just dismissed). Used to
    /// look up its source frame and exclude it from the sweep.
    @State private var presentingBinderID: UUID? = nil
    /// Cache of card thumbnail URLs resolved by grid cells, so the morph
    /// overlay can show images immediately without reloading.
    @State private var gridResolvedURLs: [UUID: [URL?]] = [:]
    /// Cache of total value text resolved by grid cells.
    @State private var gridResolvedValues: [UUID: String] = [:]
    
    /// Stable grid cell frame captured at the exact moment of tapping.
    /// Persistent across the entire presentation, preventing coordinate resetting or unmounting.
    @State private var activeSourceFrame: CGRect = .zero

    private var activeBrand: TCGBrand { services.brandSettings.selectedCatalogBrand }
    private var visibleBinders: [Binder] {
        binders.filter { $0.tcgBrand == activeBrand }
    }

    var body: some View {
        // ZStack overlay pattern (matches Social + Dashboard):
        // content scrolls under a translucent floating header rather than
        // sitting beneath an opaque title bar. `safeAreaInset` reserves the
        // top space so the first row of binders doesn't slip under the
        // header; `bindersHeader` itself paints `.ultraThinMaterial`.
        ZStack(alignment: .top) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: bindersHeaderHeight)
                }
                // Capture every cell's global frame so the open animation
                // knows where to morph from and the sweep knows which way
                // each non-selected cell should fly.
                .onPreferenceChange(BinderCellFramePreferenceKey.self) { frames in
                    binderCellFrames = frames
                }
            bindersHeader
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: BindersHeaderHeightKey.self, value: geo.size.height)
                    }
                )
                .onPreferenceChange(BindersHeaderHeightKey.self) { bindersHeaderHeight = $0 }
                // Header fades while a binder is presented so it doesn't
                // sit awkwardly above the morphing cover. Spring matches
                // the sweep so everything moves together.
                .opacity(isPresentingBinder ? 0 : 1)
                .allowsHitTesting(!isPresentingBinder)
                .animation(.spring(response: 0.38, dampingFraction: 0.85), value: isPresentingBinder)

            // Custom presentation overlay. Replaces ``fullScreenCover`` so
            // the cover can morph from its grid frame to the page area and
            // hand off to ``BinderDetailView``'s existing page-curl.
            if let binder = presentedBinder {
                BinderOpenContainer(
                    binder: binder,
                    sourceFrame: activeSourceFrame,
                    peekingURLs: gridResolvedURLs[binder.id] ?? [nil, nil, nil],
                    valueText: gridResolvedValues[binder.id],
                    onDismissComplete: { finishBinderClose() },
                    onStartClose: { beginSweepBack() }
                )
                .environment(services)
                .ignoresSafeArea(.all)
                .zIndex(50)
                .transition(.identity)
                // Hide the tab bar while a binder is open so it doesn't 
                // sit above the full-screen view.
                .toolbar(isPresentingBinder ? .hidden : .visible, for: .tabBar)
            }
        }
        // All cell frames and the page-frame preference are reported in this
        // named space so the morph overlay and source positions share a single
        // consistent coordinate origin.
        .coordinateSpace(name: "bindersRoot")
        .bindrPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showCreateSheet) {
            CreateBinderSheet()
                .environment(services)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet()
                .environment(services)
        }
        .alert("Delete Binder?", isPresented: $showDeleteConfirm, presenting: binderToDelete) { binder in
            Button("Delete \"\(binder.title)\"", role: .destructive) {
                modelContext.delete(binder)
            }
            Button("Cancel", role: .cancel) {}
        } message: { binder in
            Text("This will permanently remove \"\(binder.title)\" and all its cards.")
        }
        .task(id: binders.map(\.id).map(\.uuidString).sorted().joined(separator: ",")) {
            do {
                try await services.socialShare.reconcileDeletedBinders(localBinderIDs: Set(binders.map(\.id)))
            } catch {
                // Silent best-effort cleanup.
            }
        }
    }

    // MARK: - Content

    /// Scroll content extracted from `body` so the ZStack overlay can wrap
    /// it cleanly. The empty/empty-for-brand/populated branches keep the
    /// behaviour identical to the previous VStack layout — the only
    /// structural change is that the parent now owns the safe-area inset.
    @ViewBuilder
    private var content: some View {
        if binders.isEmpty {
            ScrollView {
                ContentUnavailableView {
                    Label("No Binders", systemImage: "books.vertical")
                } description: {
                    Text("Create a binder to organise your cards.")
                } actions: {
                    Button("Create a Binder") { handleCreateTap() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(minHeight: 300)
            }
        } else if visibleBinders.isEmpty {
            ScrollView {
                ContentUnavailableView {
                    Label("No \(activeBrand.displayTitle) Binders", systemImage: "books.vertical")
                } description: {
                    Text("Create a binder for \(activeBrand.displayTitle) to organise those cards.")
                } actions: {
                    Button("Create a Binder") { handleCreateTap() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(minHeight: 300)
            }
        } else {
            ScrollView {
                // Cards now render in an A4 portrait ratio (~160 × 230),
                // so allow each grid cell a bit more horizontal room and a
                // touch more vertical spacing between rows.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 14)], spacing: 16) {
                    ForEach(visibleBinders) { binder in
                        Button {
                            beginBinderOpen(binder)
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                BinderCardCell(
                                    binder: binder,
                                    onURLsLoaded: { urls in
                                        gridResolvedURLs[binder.id] = urls
                                    },
                                    onValueLoaded: { val in
                                        gridResolvedValues[binder.id] = val
                                    }
                                )

                                if isEditing {
                                    Button {
                                        binderToDelete = binder
                                        showDeleteConfirm = true
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(.red)
                                            .background(Circle().fill(.white).padding(2))
                                    }
                                    .transition(.scale.combined(with: .opacity))
                                    .padding(8)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .aspectRatio(0.707, contentMode: .fill)
                        .contextMenu {
                            Button(role: .destructive) {
                                binderToDelete = binder
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete Binder", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                        // Hide the source cell while it's being presented —
                        // the morphing overlay covers its position so a
                        // duplicate underneath would just create flicker.
                        .opacity(presentingBinderID == binder.id ? 0 : 1)
                        // Sweep non-selected binders out of the way based
                        // on their grid position relative to the tapped
                        // cell. ``sweepOffset`` returns ``.zero`` while
                        // idle so the grid sits still until a tap lands.
                        .offset(sweepOffset(for: binder))
                        .animation(
                            .spring(response: 0.4, dampingFraction: 0.82),
                            value: isPresentingBinder
                        )
                        // Each cell publishes its frame in screen coords so
                        // the open animation knows where to morph from /
                        // collapse back to. We only emit when the frame has
                        // actually changed to avoid the "multiple updates per
                        // frame" SwiftUI warning caused by all visible cells
                        // firing simultaneously during normal scroll redraws.
                        .background(
                            GeometryReader { cellGeo in
                                let newFrame = cellGeo.frame(in: .named("bindersRoot"))
                                Color.clear
                                    .preference(
                                        key: BinderCellFramePreferenceKey.self,
                                        value: [binder.id: newFrame]
                                    )
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8 + rootFloatingChromeInset)
            }
        }
    }

    // MARK: - Open / close choreography

    /// Tap handler — flips ``isPresentingBinder`` so the other cells
    /// sweep, then mounts ``BinderOpenContainer`` which owns the actual
    /// morph + cover hold + hand-off to ``BinderDetailView``.
    private func beginBinderOpen(_ binder: Binder) {
        guard presentedBinder == nil else { return }
        presentingBinderID = binder.id
        
        // Capture a stable, persistent grid frame snapshot at the exact moment of tap!
        if let frame = binderCellFrames[binder.id] {
            activeSourceFrame = frame
        } else {
            // Fallback to a safe screen frame if not resolved yet
            activeSourceFrame = CGRect(x: 100, y: 200, width: 160, height: 230)
        }
        
        // Stagger the sweep slightly ahead of the morph so the user sees
        // the others moving as the tapped cover lifts off the table — the
        // spring duration matches what the user described (350-400ms).
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            isPresentingBinder = true
        }
        presentedBinder = binder
    }

    private func beginSweepBack() {
        // Start moving the other binders back to their positions 
        // at the same time the overlay starts collapsing.
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            isPresentingBinder = false
        }
    }

    /// Called by ``BinderOpenContainer`` once the close animation (page
    /// curl back → cover morph back to grid) has finished. Sweeps the
    /// other binders back into place and tears down the overlay.
    private func finishBinderClose() {
        // Overlay has landed. Now we can safely remove the presenter.
        presentedBinder = nil
        presentingBinderID = nil
    }

    /// Computes the offset to apply to each non-selected binder cell so it
    /// sweeps off-screen in the direction of "away from the tapped cell".
    /// Returns ``.zero`` while idle and for the tapped cell itself.
    private func sweepOffset(for binder: Binder) -> CGSize {
        guard isPresentingBinder,
              let openedID = presentingBinderID,
              openedID != binder.id,
              let openedFrame = binderCellFrames[openedID],
              let thisFrame = binderCellFrames[binder.id] else {
            return .zero
        }
        let dx = thisFrame.midX - openedFrame.midX
        let dy = thisFrame.midY - openedFrame.midY
        // A generous sweep distance ensures every cell exits the viewport
        // even on iPad-class screens. Direction is decided by which axis
        // is larger so corner cells fly diagonally out via their dominant
        // component rather than at an awkward 45°.
        let sweep: CGFloat = 1200
        if abs(dx) >= abs(dy) {
            return CGSize(width: dx >= 0 ? sweep : -sweep, height: 0)
        } else {
            return CGSize(width: 0, height: dy >= 0 ? sweep : -sweep)
        }
    }

    // MARK: - Header

    private var bindersHeader: some View {
        BindrPageHeader(
            title: "Binders",
            leading: {
                ChromeGlassCircleButton(accessibilityLabel: "Back") {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }
            },
            trailing: {
                ChromeGlassCircleButton(accessibilityLabel: "Create Binder") { handleCreateTap() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
        )
    }

    private func handleCreateTap() {
        if !services.store.isPremium && visibleBinders.count >= 1 {
            showPaywall = true
        } else {
            showCreateSheet = true
        }
    }
}

private struct BinderCardCell: View {
    @Environment(AppServices.self) private var services
    let binder: Binder
    var onURLsLoaded: (([URL?]) -> Void)? = nil
    var onValueLoaded: ((String?) -> Void)? = nil
    @State private var cardURLs: [URL?] = [nil, nil, nil]
    @State private var totalUSDValue: Double = 0
    @State private var hasLoadedValue: Bool = false

    var body: some View {
        BinderCoverView(
            binder: binder,
            compact: false,
            valueText: displayedValueText
        )
        // We render the "premium" (non-compact) layout even in the grid
        // so that when the morph starts, the internal proportions 
        // (card sizes, text, spacing) are identical. 
        .subtitleOverride(subtitleText)
        .peekingURLsOverride(cardURLs)
        .task {
            await loadCardURLs()
            await refreshTotalValue()
            onValueLoaded?(displayedValueText)
        }
    }

    /// Subtitle displays only the binder card count.
    private var subtitleText: String {
        let count = binder.slotList.count
        return "\(count) \(count == 1 ? "card" : "cards")"
    }

    /// Returns the formatted total value once prices have been fetched. We
    /// hide the label entirely for empty binders so a "£0" doesn't dominate
    /// brand-new covers — once cards are added the value appears.
    private var displayedValueText: String? {
        guard binder.showValueOnCover, hasLoadedValue, !binder.slotList.isEmpty else { return nil }
        return formatTotal(usd: totalUSDValue)
    }

    private func formatTotal(usd: Double) -> String {
        let display = services.priceDisplay.currency
        let amount = display == .gbp ? usd * services.pricing.usdToGbp : usd

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = display.symbol
        formatter.maximumFractionDigits = amount >= 1000 ? 0 : 2
        return formatter.string(from: NSNumber(value: amount)) ?? ""
    }

    private func loadCardURLs() async {
        let slots = binder.slotList.prefix(3)
        var urls: [URL?] = []

        for slot in slots {
            if let card = await services.cardData.loadCard(masterCardId: slot.cardID) {
                // Use the real image path from the card metadata (e.g. cards/sv01/1_low.png)
                // rather than guessing the path from the ID.
                urls.append(AppConfiguration.imageURL(relativePath: card.imageLowSrc))
            } else {
                urls.append(nil)
            }
        }

        while urls.count < 3 { urls.append(nil) }
        cardURLs = urls
        onURLsLoaded?(urls)
    }

    /// Sums every slot's USD market price the same way ``BinderDetailView``
    /// does, so the cover front mirrors what the user sees inside the binder.
    private func refreshTotalValue() async {
        var sum: Double = 0
        for slot in binder.slotList {
            guard let card = await services.cardData.loadCard(masterCardId: slot.cardID) else { continue }
            if let usd = await services.pricing.usdPriceForVariant(
                for: card,
                variantKey: slot.variantKey
            ) {
                sum += usd
            }
        }
        totalUSDValue = sum
        hasLoadedValue = true
    }
}

/// Preference key used by ``BindersRootView`` to read its own translucent
/// header height back into a `safeAreaInset` so scroll content reserves the
/// exact pixel-perfect amount of top space for the floating header.
private struct BindersHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 64
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Per-binder grid-cell frame, in screen/global coordinates. Each
/// ``BinderCardCell`` publishes its own frame via this key; the parent
/// merges them into a `[UUID: CGRect]` and uses the result to drive both
/// the open animation (source frame to morph from) and the sweep
/// directions for non-selected cells.
private struct BinderCellFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        // Only merge entries that are new or whose frame has actually moved —
        // this prevents the "tried to update multiple times per frame" warning
        // that fires when multiple grid cells all publish during the same
        // render pass (scroll, rotation, etc.) and the accumulator gets
        // written more than once before SwiftUI flushes the preference.
        for (id, frame) in nextValue() {
            if value[id] != frame {
                value[id] = frame
            }
        }
    }
}

// MARK: - Open / close container

/// Hosts the ``BinderDetailView`` plus the morphing cover overlay that sits
/// above it during the entry / exit transitions. Lives only while a binder
/// is presented; teardown happens via ``onDismissComplete`` once the close
/// animation has fully reversed.
///
/// **Choreography**
/// 1. *Entry.* On mount, a ``BinderCoverView`` is rendered at the source
///    grid frame (passed in by the caller) and animated to the page-area
///    frame ``BinderDetailView`` reports through
///    ``BinderPageFramePreferenceKey``. Spring matches the sweep timing
///    upstream so everything moves together.
/// 2. *Hand-off.* After the morph (~400ms) the overlay cover fades out;
///    underneath, ``BinderDetailView``'s ``PageCurlView`` is showing the
///    same cover at page 0. ``BinderDetailView``'s own auto-advance timer
///    fires the existing page-curl from cover (page 0) to first card page
///    (page 1) ~1s after mount, exactly when the user wanted.
/// 3. *Exit.* When the user taps back, ``BinderDetailView`` curls back to
///    page 0 via the existing curl, then calls ``onCustomDismiss``. We
///    re-show the overlay cover at the page-area frame, fade
///    ``BinderDetailView`` away, and animate the cover back to the source
///    grid frame. Once the spring completes we call ``onDismissComplete``
///    so the parent can sweep the other binders back in.
struct BinderOpenContainer: View {
    let binder: Binder
    let sourceFrame: CGRect
    let peekingURLs: [URL?]
    let valueText: String?
    let onDismissComplete: () -> Void
    let onStartClose: () -> Void

    @Environment(AppServices.self) private var services
    /// iOS "Reduce Motion" accessibility setting. When enabled we skip
    /// the spring-based morph and the cover-hold and use a quick
    /// cross-fade instead so vestibular-sensitive users aren't shoved
    /// across the screen by a 400ms scale animation.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Frame of ``BinderDetailView``'s page-curl page area, in screen
    /// coordinates. Reported by ``BinderPageFramePreferenceKey``; we wait
    /// for the first non-zero value before kicking off the morph so the
    /// destination is real geometry, not the default zero rect.
    @State private var pageFrame: CGRect = .zero
    /// Uniform scale applied to the overlay cover during the morph.
    /// ``BinderCoverView`` lays its contents (text, ornament, peeking
    /// thumbnails) out at fixed sizes — animating ``.frame`` alone clips
    /// or stretches them. Rendering at a single reference size and
    /// scaling the rendered view as a whole is what gives the open/close
    /// that smooth, "lifting off the table" feel where every internal
    /// element scales proportionally with the binder.
    @State private var coverScale: CGFloat = 1.0
    /// Live centre point of the overlay cover, in the global coordinate
    /// space shared with ``sourceFrame`` and ``pageFrame``. Animated
    /// alongside ``coverScale`` to drive the position part of the morph.
    /// Initialised to ``sourceFrame``'s midpoint (not .zero) so the cover
    /// is never positioned at the top-left corner on its first render.
    @State private var coverCenter: CGPoint
    /// Visibility of the overlay cover. Drops to 0 after the open morph
    /// (so the user starts seeing ``BinderDetailView``'s page 0) and rises
    /// back to 1 instantly when the close animation begins.
    @State private var coverOpacity: Double = 0.0
    /// Visibility of the underlying ``BinderDetailView``. Stays at 0 until
    /// the open morph is almost done, then fades in as the overlay cover
    /// fades out. This ensures the user only sees one binder at a time.
    @State private var detailOpacity: Double = 0
    /// `true` once we've kicked off the morph. Guards against repeating it
    /// when the page-frame preference changes again later.
    @State private var hasStartedOpen = false
    /// `true` once the close sequence is in flight. Hides
    /// ``BinderDetailView`` while the overlay collapses.
    @State private var isClosing = false
    /// Drives the lift shadow under the cover. 0 at the source frame
    /// (small/tight, like the cell sitting on the grid), 1 at the page
    /// frame (large/diffuse, like the binder hovering near the lens).
    /// Animated alongside ``coverScale`` so the shadow grows in lockstep
    /// with the morph and reads as a single physical motion.
    @State private var liftIntensity: CGFloat = 0
    /// Tiny extra scale applied during the cover hold to give the binder
    /// a subtle "breath". 1.0 at rest, ~1.012 at peak. Multiplied with
    /// ``coverScale`` so the breath rides on top of the morph and stops
    /// instantly when the page-curl auto-advance fires.
    @State private var breathingScale: CGFloat = 1.0
    /// Page frame captured the moment the open morph starts. Using a
    /// snapshot here (rather than the live ``pageFrame``) prevents layout
    /// changes during the header / stats-bar chrome reveal from shifting
    /// the close-morph destination mid-animation.
    @State private var stablePageFrame: CGRect = .zero

    /// Spring used for both the opening morph and the closing collapse.
    /// Critical damping (1.0) so the cover arrives at its destination with
    /// zero overshoot — no subtle upward bounce when landing at page-center
    /// on open, and no oscillation when seating back into the grid on close.
    private var morphAnimation: Animation {
        .spring(response: 0.4, dampingFraction: 1.0)
    }

    // MARK: Init

    /// Designated init so we can seed ``coverCenter`` with the source
    /// frame's midpoint rather than CGPoint.zero. This means the cover
    /// overlay is NEVER at (0,0) on any render — even before
    /// ``startOpenMorph`` has a chance to run — which eliminates the
    /// "slides in from the top-left corner" glitch caused by animation
    /// context leaking into the first state-change pass.
    init(
        binder: Binder,
        sourceFrame: CGRect,
        peekingURLs: [URL?],
        valueText: String?,
        onDismissComplete: @escaping () -> Void,
        onStartClose: @escaping () -> Void
    ) {
        self.binder = binder
        self.sourceFrame = sourceFrame
        self.peekingURLs = peekingURLs
        self.valueText = valueText
        self.onDismissComplete = onDismissComplete
        self.onStartClose = onStartClose
        // Seed cover position at the grid cell so it is never at (0,0).
        self._coverCenter = State(initialValue: CGPoint(
            x: sourceFrame.midX,
            y: sourceFrame.midY
        ))
    }

    var body: some View {
        GeometryReader { rootGeo in
            ZStack {
                // Underlying detail view — stays mounted for the whole
                // presentation. Hidden during the very last collapse so the
                // page-area doesn't poke out behind the morphing cover.
                BinderDetailView(
                    binder: binder,
                    entryFromGrid: true,
                    onCustomDismiss: { beginClose() },
                    preloadedPeekingURLs: peekingURLs,
                    preloadedValueText: valueText,
                    topSafeAreaInset: rootGeo.safeAreaInsets.top,
                    bottomSafeAreaInset: rootGeo.safeAreaInsets.bottom
                )
                .environment(services)
                .opacity(isClosing ? 0 : detailOpacity)
                .animation(.easeOut(duration: 0.2), value: isClosing)
                .animation(.easeOut(duration: 0.2), value: detailOpacity)
                .onPreferenceChange(BinderPageFramePreferenceKey.self) { newFrame in
                    guard !isClosing else { return }
                    guard newFrame != .zero else { return }
                    guard newFrame.origin.y > 20, newFrame.width > 100, newFrame.height > 100 else { return }
                    
                    pageFrame = newFrame
                    if !hasStartedOpen {
                        hasStartedOpen = true
                        startOpenMorph()
                    }
                }

                // Morphing cover overlay. Renders the same cover as
                // ``BinderDetailView``'s page 0 so the hand-off is seamless.
                //
                // Sizing strategy: render the cover at the *target* page
                // frame (always at the larger, "compact-false" geometry)
                // and morph it via ``scaleEffect`` + ``position``. That
                // way every internal layout sub-piece — title, ornament,
                // value text, peeking card fan — scales uniformly, which
                // is what stops the cards from "popping" mid-morph.
                BinderCoverView(
                    binder: binder,
                    compact: false,
                    valueText: valueText
                )
                // Use the URLs passed from the grid so they are visible
                // immediately during the morph without re-loading.
                .peekingURLsOverride(peekingURLs)
                .subtitleOverride("\(binder.slotList.count) \(binder.slotList.count == 1 ? "card" : "cards")")
                // Always render the overlay at the cover's *natural* A4
                // aspect ratio. ``coverTargetFrame`` is an A4 rectangle
                // fitted inside ``pageFrame`` and used as the morph end
                // point. Because ``sourceFrame`` is also A4 (the grid
                // cells are aspect-locked to 0.707), source and target
                // share aspect — a single uniform ``scaleEffect`` morphs
                // cleanly between them with no end-of-close height pop.
                .frame(
                    width: max(coverTargetFrame.width, 1),
                    height: max(coverTargetFrame.height, 1)
                )
                // Animated lift shadow — grows from a tight contact
                // shadow at the source frame (binder sitting on the
                // grid) to a deep, diffuse shadow at the page frame
                // (binder hovering close to the camera). Drives off
                // ``liftIntensity`` so it interpolates with the same
                // spring as the position/scale.
                .shadow(
                    color: .black.opacity(0.18 + 0.22 * Double(liftIntensity)),
                    radius: 4 + 22 * liftIntensity,
                    x: 0,
                    y: 2 + 18 * liftIntensity
                )
                .scaleEffect(coverScale * breathingScale, anchor: .center)
                // ``coverCenter`` is stored in the "bindersRoot" coordinate space
                // (same as the cell frames and the page-frame preference). The parent
                // ZStack here starts at the top of the screen (y = 0) because
                // BinderOpenContainer was applied .ignoresSafeArea(.all), while the
                // "bindersRoot" ZStack starts below the status bar. Subtracting the
                // origin of this full-screen reader in "bindersRoot" space converts
                // bindersRoot coordinates → the screen-local coordinates that
                // .position() expects. Without this correction the cover appears
                // ~59 px above the actual grid cell and appears to "lift" before
                // starting the spring.
                .position(
                    x: coverCenter.x - rootGeo.frame(in: .named("bindersRoot")).origin.x,
                    y: coverCenter.y - rootGeo.frame(in: .named("bindersRoot")).origin.y
                )
                .opacity(coverOpacity)
                .allowsHitTesting(false)
            }
            .ignoresSafeArea(.all)
            // Free-scroll layouts don't host a ``PageCurlView`` and so never
            // publish ``BinderPageFramePreferenceKey``. Fall back to a
            // centred rect inside the root geometry after a brief wait so
            // the morph still runs in those cases. Paged layouts publish
            // their real page frame on the first layout pass and skip this
            // path entirely.
            .task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if !hasStartedOpen {
                    let size = rootGeo.size
                    let fallbackHeight = min(size.height * 0.78, size.width * 1.4)
                    let fallbackWidth = min(size.width - 32, fallbackHeight / 1.4)
                    // Express the fallback rect in "bindersRoot" space (same as cell
                    // frames and the page-frame preference) so coverTargetFrame →
                    // pageCenter → .position correction all stay consistent.
                    let geoOrigin = rootGeo.frame(in: .named("bindersRoot")).origin
                    pageFrame = CGRect(
                        x: geoOrigin.x + (size.width - fallbackWidth) / 2,
                        y: geoOrigin.y + (size.height - fallbackHeight) / 2,
                        width: fallbackWidth,
                        height: fallbackHeight
                    )
                    hasStartedOpen = true
                    startOpenMorph()
                }
            }
            // Logic moved to BinderCardCell and passed in via valueText
        }
    }

    // MARK: Phase transitions

    /// Cover's natural aspect ratio — the same A4-ish portrait the grid
    /// cells are locked to (``aspectRatio(0.707, contentMode: .fill)``).
    /// Treating the cover as A4 at every step of the morph means source
    /// and target share aspect, which is what lets a single uniform
    /// scaleEffect morph cleanly without distortion.
    private static let coverAspect: CGFloat = 0.707

    /// A4-aspect rectangle fitted inside ``pageFrame`` and centred there.
    /// This is the morph's actual destination — *not* the page frame
    /// itself. Some layouts (4×3) produce a near-square page area; we
    /// don't want the binder cover to morph into a square mid-flight.
    ///
    /// Once ``stablePageFrame`` is locked (at the start of the open morph),
    /// we use that snapshot so chrome-reveal layout changes cannot shift
    /// the destination while the animation is in flight.
    private var coverTargetFrame: CGRect {
        // Prefer the locked stable frame once it has been set.
        let base = stablePageFrame != .zero ? stablePageFrame : pageFrame
        guard base.width > 0, base.height > 0 else { return base }
        let aspect = Self.coverAspect
        let pageAspect = base.width / base.height
        let width: CGFloat
        let height: CGFloat
        if pageAspect < aspect {
            // Page is narrower than A4 — width-limited.
            width = base.width
            height = width / aspect
        } else {
            // Page is wider than (or equal to) A4 — height-limited.
            height = base.height
            width = height * aspect
        }
        return CGRect(
            x: base.midX - width / 2,
            y: base.midY - height / 2,
            width: width,
            height: height
        )
    }

    /// Scale that maps the rendered cover (always at ``coverTargetFrame``
    /// dimensions) down to the source grid cell. Width-based: both
    /// rectangles share the cover aspect, so width is enough to derive
    /// the full transform.
    private var sourceScale: CGFloat {
        guard coverTargetFrame.width > 0 else { return 1.0 }
        return max(0.05, sourceFrame.width / coverTargetFrame.width)
    }

    private var sourceCenter: CGPoint {
        CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
    }

    private var pageCenter: CGPoint {
        CGPoint(x: coverTargetFrame.midX, y: coverTargetFrame.midY)
    }

    /// Kicks off the morph from grid cell → page area. Once the morph
    /// settles, fade the overlay out so ``BinderDetailView``'s own page 0
    /// (which already shows an identical cover) takes over.
    private func startOpenMorph() {
        // Lock the page frame snapshot so that chrome-reveal layout
        // changes (isChromeVisible transitions animating the header and
        // stats bar) cannot shift the destination while the morph is
        // in flight, and so that beginClose() always has a stable target.
        stablePageFrame = pageFrame

        // Snap to the source state with ALL animation disabled.
        // Without disablesAnimations, any spring transaction still in
        // flight from `withAnimation { isPresentingBinder = true }` in
        // beginBinderOpen() causes the cover to slide in from (0,0)
        // rather than jumping directly to the grid-cell frame.
        var snapTx = Transaction(animation: nil)
        snapTx.disablesAnimations = true
        withTransaction(snapTx) {
            coverScale = sourceScale
            coverCenter = sourceCenter
            coverOpacity = 1
            liftIntensity = 0
        }

        // Reduce-Motion path: the morph itself becomes a quick
        // cross-fade, no spring or scale travel. We still show the
        // overlay cover at the page frame so the cover-to-page-1 hand
        // off works the same way in ``BinderDetailView``.
        if reduceMotion {
            coverScale = 1.0
            coverCenter = pageCenter
            liftIntensity = 1
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) {
                        coverOpacity = 0
                        detailOpacity = 1
                    }
                }
            }
            return
        }

        Task {
            // Yield to the next main-actor run-loop turn so the
            // no-animation snap is committed in its own render pass
            // before the spring starts. Task.yield() is more precise
            // than a 16 ms sleep on variable-refresh-rate displays.
            await Task.yield()
            await MainActor.run {
                withAnimation(morphAnimation) {
                    coverScale = 1.0
                    coverCenter = pageCenter
                    liftIntensity = 1
                }
            }

            // Soft haptic at the moment the cover lands — sells the
            // "binder placed in front of you" beat. ``.soft`` is the
            // gentle thud Apple uses when a sheet finishes presenting.
            try? await Task.sleep(nanoseconds: 380_000_000)
            await MainActor.run {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }

            // Fade the overlay out shortly after the spring lands. The
            // ``BinderDetailView`` cover (page 0) is already underneath at
            // the same rect so the user can't see the swap. Fading
            // ``liftIntensity`` alongside opacity dissolves the floating
            // shadow gradually instead of it "dropping" the moment the
            // overlay disappears — the hand-off reads as one continuous motion.
            try? await Task.sleep(nanoseconds: 30_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    coverOpacity = 0
                    detailOpacity = 1
                    liftIntensity = 0
                }
                // Subtle breath during the cover hold — single ease in/
                // out cycle so the binder reads as "alive" without
                // becoming a gimmick. Stops as soon as the page-curl
                // auto-advance fires (we explicitly clamp it).
                withAnimation(.easeInOut(duration: 0.45).delay(0.05)) {
                    breathingScale = 1.012
                }
            }

            // Settle the breath back to 1.0 just before the auto-curl
            // would start, so the curl doesn't inherit a non-1 scale.
            try? await Task.sleep(nanoseconds: 600_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.35)) {
                    breathingScale = 1.0
                }
            }
        }
    }

    /// Triggered by ``BinderDetailView``'s back tap once it has finished
    /// curling back to page 0. Re-shows the overlay cover at the page-area
    /// frame, fades the detail view, and animates the cover back to the
    /// source grid frame. After the spring completes we call
    /// ``onDismissComplete`` so the parent finishes the choreography
    /// (sweep the other binders back in).
    private func beginClose() {
        guard !isClosing else { return }
        onStartClose()

        // Re-show the overlay cover at the (stable) page-frame position
        // with ALL animation disabled — same pattern as the open snap.
        // Using stablePageFrame (via coverTargetFrame → pageCenter) means
        // layout drift from the chrome-reveal animation cannot push the
        // starting point of the collapse to (0, 0) or off-screen.
        var snapTx = Transaction(animation: nil)
        snapTx.disablesAnimations = true
        withTransaction(snapTx) {
            coverScale = 1.0
            coverCenter = pageCenter   // reads stablePageFrame via coverTargetFrame
            coverOpacity = 1
            detailOpacity = 0
            breathingScale = 1.0
            liftIntensity = 1
            isClosing = true
        }

        // Reduce-Motion path: skip the spring collapse, just fade out.
        if reduceMotion {
            Task {
                try? await Task.sleep(nanoseconds: 30_000_000)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) {
                        coverOpacity = 0
                    }
                }
                try? await Task.sleep(nanoseconds: 220_000_000)
                await MainActor.run {
                    onDismissComplete()
                }
            }
            return
        }

        Task {
            // Yield to the next run-loop turn — same reasoning as startOpenMorph.
            await Task.yield()
            await MainActor.run {
                // Spring drives only position and scale — liftIntensity is
                // kept separate so the shadow stays "elevated" while the binder
                // travels toward the grid cell, rather than immediately sinking
                // (which created a visual drop at the start of the close).
                withAnimation(morphAnimation) {
                    coverScale = sourceScale
                    coverCenter = sourceCenter
                }
                // Shadow fades out near the END of the close travel so the
                // binder looks lifted the whole way and only "lands" once it
                // reaches the cell. delay(0.25) lets most of the spring travel
                // complete first; duration(0.15) matches the final approach.
                withAnimation(.easeOut(duration: 0.15).delay(0.25)) {
                    liftIntensity = 0
                }
            }

            // Soft haptic at the moment the cover seats back into the
            // grid — mirror of the open-morph land so close feels just
            // as committed as open.
            try? await Task.sleep(nanoseconds: 410_000_000)
            await MainActor.run {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }

            // Wait a beat for the haptic to settle, then unmount.
            try? await Task.sleep(nanoseconds: 20_000_000)
            await MainActor.run {
                onDismissComplete()
            }
        }
    }
}
