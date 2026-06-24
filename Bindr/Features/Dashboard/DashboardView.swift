import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    var onViewAllActivity: (() -> Void)? = nil
    var onOpenScanner: (() -> Void)? = nil
    var onOpenCollection: (() -> Void)? = nil
    var onOpenSealedProducts: (() -> Void)? = nil
    var onOpenWishlist: (() -> Void)? = nil
    var onOpenBrowse: (() -> Void)? = nil
    /// Opens Social → Trades. Pass a trade ID to jump straight to that offer; pass nil for the trades list.
    var onOpenActionableTrades: ((UUID?) -> Void)? = nil
    var onInitialLoadStatusChange: ((String) -> Void)? = nil
    var onInitialLoadComplete: (() -> Void)? = nil

    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.restoreTabBarChrome) private var restoreTabBarChrome
    @Environment(\.suppressTabBarForModalChrome) private var suppressTabBarForModalChrome

    // Manual @State instead of @Query so CloudKit background syncs don't trigger
    // DashboardView body re-renders. @Query fires on every SwiftData save — including
    // every CloudKit record delivery — which blocked the main thread for 8-9 seconds
    // after launch with 1000+ collection items. Ledger lines are refreshed explicitly
    // in reloadDashboardInventory and via a debounced SwiftData notification observer.
    @State private var allLedgerLines: [LedgerLine] = []
    @State private var ledgerRefreshDebounceTask: Task<Void, Never>? = nil

    @State private var collectionItems: [CollectionItem] = []
    @State private var wishlistItems: [WishlistItem] = []
    @State private var binderCount = 0
    @State private var dashboardDataRevision = 0
    @State private var isLoadingDashboardInventory = false
    @State private var isPreparingInitialDashboardData = false
    @State private var hasPreparedInitialDashboardData = false
    @State private var liveTotalGbp: Double? = nil
    @State private var livePokemonGbp: Double = 0
    @State private var liveCardsGbp: Double = 0
    @State private var liveSealedGbp: Double = 0
    @State private var totalCostBasis: Double = 0
    @State private var isLoadingValue = false
    @State private var hasFiredInitialLoadComplete = false
    @State private var selectedPoint: ChartPoint? = nil
    @State private var chartRefreshID: Int = 0
    @State private var selectedBrand: TCGBrand? = nil
    @State private var lastLiveValueComputedAt: Date? = nil
    // Grouped into a single struct so all three update in one SwiftUI render pass,
    // avoiding three sequential body re-evaluations over the full collection.
    private struct CardMetadataCache {
        var namesByID: [String: String] = [:]
        var setNamesByCardID: [String: String] = [:]
        var imageURLsByID: [String: URL] = [:]
    }
    @State private var cardMetadata = CardMetadataCache()
    private var cardNamesByID: [String: String] { cardMetadata.namesByID }
    private var setNamesByCardID: [String: String] { cardMetadata.setNamesByCardID }
    private var cardImageURLsByID: [String: URL] { cardMetadata.imageURLsByID }
    @State private var upcomingReleases: [UpcomingRelease] = []
    @State private var editingRecentLedgerLine: LedgerLine?
    @State private var selectedCardForDetail: Card? = nil
    @State private var selectedSealedProductForDetail: SealedProduct? = nil
    @State private var actionableTrades: [(id: UUID, status: TradeStatus, updatedAt: Date?)] = []
    @State private var progressTracker = DashboardProgressTrackerStore.load()
    @State private var progressSnapshots: [DashboardProgressSnapshot] = []
    @State private var isLoadingProgressSnapshots = false
    @State private var showProgressTrackerSheet = false

    // Cached chart data — updated only when chartRefreshID changes so body re-evaluations
    // from unrelated @State writes don't rebuild snapshot arrays.
    @State private var cachedDailyPoints: [ChartPoint] = []
    @State private var cachedActivePoints: [ChartPoint] = []

    // Cached collection stats — updated via task when collectionItems/brand changes,
    // so SwiftUI body evaluation never pays the O(n) cost of iterating 997+ items.
    @State private var cachedVisibleCollectionItems: [CollectionItem] = []
    @State private var cachedVisibleCardCollectionItems: [CollectionItem] = []
    @State private var cachedTotalCardsCount: Int = 0
    @State private var cachedUniqueCardsCount: Int = 0
    @State private var cachedSealedProductsCount: Int = 0
    @State private var cachedWishlistedCardsCount: Int = 0

    private struct NewsUpdate: Identifiable {
        let id: String
        let icon: String
        let title: String
        let summary: String
        let label: String
    }

    private static let placeholderNewsUpdates: [NewsUpdate] = [
        NewsUpdate(
            id: "elemental-themes",
            icon: "paintpalette.fill",
            title: "Elemental themes have arrived",
            summary: "Personalise Bindr with Grass, Fire, Water, Dragon and more.",
            label: "NEW"
        ),
        NewsUpdate(
            id: "scanner-refresh",
            icon: "viewfinder",
            title: "A sharper scanner experience",
            summary: "Cleaner controls and improved matching make adding cards feel faster.",
            label: "UPDATE"
        ),
        NewsUpdate(
            id: "community-roadmap",
            icon: "megaphone.fill",
            title: "More from the Bindr team",
            summary: "News, announcements and community updates will appear here.",
            label: "COMING SOON"
        )
    ]

    private var liveSnapshot: BrandSnapshot? {
        guard let t = liveTotalGbp else { return nil }
        return BrandSnapshot(
            total: t,
            pokemon: livePokemonGbp,
            cards: liveCardsGbp,
            sealed: liveSealedGbp
        )
    }

    /// Today's live value first; falls back to today's saved SwiftData snapshot while recomputing.
    private var todayLiveSnapshot: BrandSnapshot? {
        liveSnapshot ?? services.collectionValue?.brandSnapshot(for: Date())
    }

    private var displayedBrandSnapshot: BrandSnapshot? {
        todayLiveSnapshot
    }

    /// True when the hero total reflects a live recompute this session, not only a stored snapshot.
    private var isShowingLiveTodayValue: Bool {
        liveSnapshot != nil
    }

    /// Subtitle beneath the hero total — shows the scrubbed chart date while dragging, otherwise today's label.
    private var displayValueSubtitle: String {
        if let point = selectedPoint {
            if Calendar.current.isDateInToday(point.date) {
                return "Today"
            }
            return rangeLabel(for: point.date)
        }
        return isShowingLiveTodayValue ? "Today's value" : "Last saved value"
    }

    private var displayTotal: Double {
        let point = selectedPoint
        switch selectedBrand {
        case .pokemon: return point?.pokemon ?? displayedBrandSnapshot?.pokemon ?? 0
        case nil:      return point?.total ?? displayedBrandSnapshot?.total ?? 0
        }
    }

    private var isScrubbingOrLoaded: Bool { selectedPoint != nil || displayedBrandSnapshot != nil }
    private var displayCardsValue: Double {
        if let point = selectedPoint, let cards = point.cards { return cards }
        return displayedBrandSnapshot?.cards ?? liveCardsGbp
    }
    private var displaySealedValue: Double {
        if let point = selectedPoint, let sealed = point.sealed { return sealed }
        return displayedBrandSnapshot?.sealed ?? liveSealedGbp
    }
    private var activeBrand: TCGBrand { services.brandSettings.selectedCatalogBrand }

    private var visibleCollectionItems: [CollectionItem] { cachedVisibleCollectionItems }
    private var visibleCardCollectionItems: [CollectionItem] { cachedVisibleCardCollectionItems }

    private var visibleWishlistItems: [WishlistItem] {
        wishlistItems.filter { TCGBrand.inferredFromMasterCardId($0.cardID) == activeBrand }
    }

    private var recentLines: [LedgerLine] {
        Array(
            allLedgerLines.filter { line in
                guard let cardID = cleaned(line.cardID) else { return false }
                return TCGBrand.inferredFromMasterCardId(cardID) == activeBrand
            }
            .prefix(5)
        )
    }

    private var totalCardsCount: Int { cachedTotalCardsCount }
    private var uniqueCardsCount: Int { cachedUniqueCardsCount }
    private var sealedProductsCount: Int { cachedSealedProductsCount }
    private var wishlistedCardsCount: Int { cachedWishlistedCardsCount }

    private func recomputeCollectionStats() {
        let visible = collectionItems.filter { TCGBrand.inferredFromMasterCardId($0.cardID) == activeBrand }
        let visibleCards = visible.filter { sealedProductID(for: $0) == nil }
        cachedVisibleCollectionItems = visible
        cachedVisibleCardCollectionItems = visibleCards
        cachedTotalCardsCount = visible.reduce(0) { $0 + max($1.quantity, 0) }
        cachedUniqueCardsCount = Set(visibleCards.map(\.cardID)).count
        cachedSealedProductsCount = visible.reduce(0) { total, item in
            guard sealedProductID(for: item) != nil else { return total }
            guard item.sealedStatus != SealedInventoryStatus.opened.rawValue else { return total }
            return total + max(item.quantity, 0)
        }
        cachedWishlistedCardsCount = Set(wishlistItems.filter { TCGBrand.inferredFromMasterCardId($0.cardID) == activeBrand }.map(\.cardID)).count
    }

    private var portfolioGain: Double? {
        guard let liveTotalGbp else { return nil }
        return liveTotalGbp - totalCostBasis
    }

    private var portfolioGainColor: Color {
        guard let gain = portfolioGain else { return dashboardSecondaryText }
        return gain >= 0 ? DashboardPalette.success : DashboardPalette.danger
    }

    private var dashboardPrimaryText: Color {
        Color(uiColor: .label)
    }

    private var dashboardSecondaryText: Color {
        Color(uiColor: .secondaryLabel)
    }

    private var dashboardCardBackground: Color {
        BindrGlassStyle.primarySurfaceFill(colorScheme)
    }

    private var dashboardCardInsetBackground: Color {
        BindrGlassStyle.secondarySurfaceFill(colorScheme)
    }

    private var dashboardTileBackground: Color {
        colorScheme == .dark ? dashboardCardInsetBackground : BindrGlassStyle.primarySurfaceFill(colorScheme)
    }

    private var dashboardBorder: Color {
        BindrGlassStyle.surfaceBorder(colorScheme)
    }

    private var dashboardDividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)
    }

    private var backfillTrigger: String {
        "\(services.collectionValue == nil ? "nil" : "ready"):\(collectionItems.count):\(services.isLaunchCatalogPipelineComplete)"
    }

    private func recomputeChartData() async {
        let svc = services.collectionValue
        let todaySnap = todayLiveSnapshot
        let snapshots = svc?.snapshots ?? []

        let daily = await Task.detached(priority: .userInitiated) {
            let cal = Calendar.current
            let now = cal.startOfDay(for: Date())

            var pointsByDay: [Date: ChartPoint] = [:]
            for snapshot in snapshots {
                let day = cal.startOfDay(for: snapshot.date)
                pointsByDay[day] = ChartPoint(
                    date: day,
                    total: snapshot.totalGbp,
                    pokemon: snapshot.pokemonGbp,
                    cards: snapshot.cardsGbp > 0 || snapshot.sealedGbp > 0 ? snapshot.cardsGbp : snapshot.totalGbp,
                    sealed: snapshot.cardsGbp > 0 || snapshot.sealedGbp > 0 ? snapshot.sealedGbp : 0
                )
            }
            if let snap = todaySnap {
                // Always pin today's live/saved value on the chart so it matches the hero total.
                pointsByDay[now] = ChartPoint(
                    date: now,
                    total: snap.total,
                    pokemon: snap.pokemon,
                    cards: snap.cards,
                    sealed: snap.sealed
                )
            }
            return pointsByDay.keys.sorted().compactMap { pointsByDay[$0] }
        }.value

        cachedDailyPoints = daily
        recomputeActivePoints()
    }

    private func recomputeActivePoints() {
        let base = cachedDailyPoints
        guard let brand = selectedBrand else { cachedActivePoints = base; return }
        cachedActivePoints = base.map { point in
            let total: Double
            switch brand {
            case .pokemon: total = point.pokemon
            }
            return ChartPoint(
                date: point.date,
                total: total,
                pokemon: point.pokemon,
                cards: point.cards,
                sealed: point.sealed
            )
        }
    }

    private var activePoints: [ChartPoint] { cachedActivePoints }

    private var chartMin: Double { (cachedActivePoints.map(\.total).min() ?? 0) * 0.95 }
    private var chartMax: Double { (cachedActivePoints.map(\.total).max() ?? 0) * 1.05 }

    private var chartXAxisDates: [Date] {
        let points = cachedActivePoints
        guard points.count > 1 else { return points.map(\.date) }
        let maxLabels = 5
        if points.count <= maxLabels { return points.map(\.date) }
        let stride = max(1, (points.count - 1) / (maxLabels - 1))
        var dates: [Date] = []
        var i = 0
        while i < points.count - 1 {
            dates.append(points[i].date)
            i += stride
        }
        dates.append(points[points.count - 1].date)
        return dates
    }

    private var periodChangeAmount: Double? {
        let points = cachedActivePoints
        guard points.count >= 2 else { return nil }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        let currentIndex: Int
        if let sel = selectedPoint, let idx = points.firstIndex(where: { $0.date == sel.date }) {
            guard idx > 0 else { return nil }
            currentIndex = idx
        } else if let todayIdx = points.firstIndex(where: { cal.isDate($0.date, inSameDayAs: today) }) {
            currentIndex = todayIdx
        } else {
            currentIndex = points.count - 1
        }

        guard currentIndex > 0 else { return nil }
        let current = points[currentIndex].total
        let previous = points[currentIndex - 1].total
        guard previous > 0 else { return nil }

        return current - previous
    }

    /// Reference date/value for period stats — follows chart scrubbing when active.
    private var collectionValueReference: (date: Date, value: Double)? {
        let points = cachedActivePoints
        guard !points.isEmpty else { return nil }
        let cal = Calendar.current
        if let sel = selectedPoint {
            return (sel.date, sel.total)
        }
        if let todayPoint = points.last(where: { cal.isDateInToday($0.date) }) {
            return (todayPoint.date, todayPoint.total)
        }
        let last = points[points.count - 1]
        return (last.date, last.total)
    }

    private var collectionValueChange31Days: Double? { collectionValuePercentChange(daysBack: 31) }
    private var collectionValueChange7Days: Double? { collectionValuePercentChange(daysBack: 7) }
    private var collectionValueChange1Day: Double? { collectionValuePercentChange(daysBack: 1) }

    private func collectionValuePercentChange(daysBack: Int) -> Double? {
        guard daysBack > 0,
              let reference = collectionValueReference,
              reference.value > 0 else { return nil }

        let cal = Calendar.current
        let referenceDay = cal.startOfDay(for: reference.date)
        guard let targetDay = cal.date(byAdding: .day, value: -daysBack, to: referenceDay) else { return nil }

        guard let baselinePoint = cachedActivePoints.last(where: { cal.startOfDay(for: $0.date) <= targetDay }),
              baselinePoint.total > 0,
              cal.startOfDay(for: baselinePoint.date) < referenceDay
        else { return nil }

        return ((reference.value - baselinePoint.total) / baselinePoint.total) * 100
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                dashboardPageOne
                    .containerRelativeFrame(.vertical, alignment: .top)
                    .id(0)

                dashboardPageTwo
                    .containerRelativeFrame(.vertical, alignment: .top)
                    .id(1)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .background(dashboardBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(services.collectionValue != nil):\(services.isLaunchCatalogPipelineComplete)") {
            guard services.collectionValue != nil else { return }
            guard services.isLaunchCatalogPipelineComplete else { return }
            await prepareInitialDashboardData()
        }
        .task(id: "\(services.needsCollectionValueRecalcAfterRestore):\(services.isLaunchCatalogPipelineComplete):\(services.isBootstrapping):\(collectionItems.count)") {
            guard services.needsCollectionValueRecalcAfterRestore else { return }
            guard services.isLaunchCatalogPipelineComplete, !services.isBootstrapping else { return }
            guard collectionItems.count > 0, services.collectionValue != nil else { return }

            isLoadingValue = true
            defer { isLoadingValue = false }

            for attempt in 0..<10 {
                let delayNs = UInt64(400_000_000 + attempt * 400_000_000)
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled else { return }

                await reloadDashboardInventory(deferForLaunch: false)
                await services.pricing.prefetchPokemonCardPricing(forSetCodes: [])
                if await computeLiveValue(validateAgainstRestore: attempt >= 2) {
                    if let snap = liveSnapshot {
                        await services.collectionValue?.forceRecalculate(
                            liveSnapshot: snap,
                            collectionItems: collectionItems
                        )
                    }
                    services.markCollectionValueRecalcAfterRestoreComplete()
                    chartRefreshID += 1
                    return
                }
            }

            _ = await computeLiveValue(validateAgainstRestore: false)
            services.markCollectionValueRecalcAfterRestoreComplete()
            chartRefreshID += 1
        }
        .task(id: backfillTrigger) {
            guard collectionItems.count > 0,
                  services.isLaunchCatalogPipelineComplete,
                  hasFiredInitialLoadComplete,
                  let svc = services.collectionValue else { return }
            // Snapshot backfill is not needed for first paint — keep it just off the launch
            // handoff so taps stay responsive right after the overlay fades.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await svc.runBackfillIfNeeded(
                collectionItems: collectionItems,
                preferredTodaySnapshot: liveSnapshot ?? displayedBrandSnapshot
            )
        }
        .task(id: dashboardDataSignature) {
            guard hasFiredInitialLoadComplete else { return }
            guard visibleCollectionItems.count > 0 || allLedgerLines.count > 0 else { return }
            // Defer card metadata just past the overlay fade so it doesn't
            // compete with the first interactive frame.
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await resolveDashboardMetadata()
        }
        .task(id: supplementalDashboardDataTrigger) {
            guard hasFiredInitialLoadComplete else { return }
            guard services.isLaunchCatalogPipelineComplete else { return }
            guard !services.isCatalogDownloadInProgress else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await loadUpcomingReleases()
        }
        .task(id: services.dashboardMarketReloadToken) {
            guard services.dashboardMarketReloadToken > 0 else { return }
            guard hasFiredInitialLoadComplete else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await reloadDashboardInventory(deferForLaunch: false)
            await computeLiveValue()
            chartRefreshID += 1
            await loadUpcomingReleases()
        }
        .task(id: "\(services.collectionInventoryRevision):\(hasFiredInitialLoadComplete)") {
            guard hasFiredInitialLoadComplete else { return }
            await reloadDashboardInventory(deferForLaunch: false)
            recomputeCollectionStats()
            chartRefreshID += 1
            await computeLiveValue()
            chartRefreshID += 1
        }
        .onChange(of: services.isCatalogDownloadInProgress) { _, inProgress in
            guard !inProgress else { return }
            Task {
                guard hasFiredInitialLoadComplete else { return }
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                await reloadDashboardInventory(deferForLaunch: false)
                await computeLiveValue()
                chartRefreshID += 1
                if let snap = liveSnapshot {
                    await services.collectionValue?.forceRecalculate(
                        liveSnapshot: snap,
                        collectionItems: collectionItems
                    )
                }
            }
        }
        .onAppear {
            selectedBrand = activeBrand
        }
        .task(id: "\(dashboardDataRevision):\(activeBrand.rawValue)") {
            recomputeCollectionStats()
        }
        .task(id: chartRefreshID) {
            await recomputeChartData()
        }
        .onChange(of: services.brandSettings.selectedCatalogBrand) { _, brand in
            selectedBrand = brand
            selectedPoint = nil
            recomputeActivePoints()
        }
        .onChange(of: services.isBootstrapping) { _, bootstrapping in
            guard !bootstrapping, hasFiredInitialLoadComplete, collectionItems.count > 0 else { return }
            Task {
                await computeLiveValue()
                chartRefreshID += 1
            }
        }
        .onChange(of: services.pricing.usdToGbp) { old, new in
            // Skip recompute if the rate change is < 0.5% (daily FX moves are tiny).
            let delta = abs(new - old) / max(old, 1e-9)
            guard delta >= 0.005 else { return }
            Task {
                await computeLiveValue()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, let snapshot = liveSnapshot {
                services.collectionValue?.persistLastKnownValue(snapshot)
            }
            if phase == .active {
                Task {
                    await refreshActionableTrades()
                    guard hasFiredInitialLoadComplete,
                          services.isLaunchCatalogPipelineComplete,
                          collectionItems.count > 0 else { return }
                    // Throttle pricing recomputes to once per 5 minutes on foreground to
                    // avoid sustained CPU work on every lock/unlock cycle.
                    if let last = lastLiveValueComputedAt,
                       Date().timeIntervalSince(last) < 300 { return }
                    await computeLiveValue()
                    chartRefreshID += 1
                }
            }
        }
        .onChange(of: services.trade.lastMutationAt) { _, _ in
            Task { await refreshActionableTrades() }
        }
        .onChange(of: services.socialAuth.authState) { _, _ in
            Task { await refreshActionableTrades() }
        }
        .task(id: hasFiredInitialLoadComplete) {
            guard hasFiredInitialLoadComplete else { return }
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await refreshActionableTrades()
        }
        // Refresh ledger lines and collection items when SwiftData saves (e.g. CloudKit sync or
        // card added mid-session). Debounce so rapid batch saves only trigger one fetch. The 2s
        // debounce lets CloudKit finish delivering a batch before we read — avoids partial re-renders.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            guard hasFiredInitialLoadComplete else { return }
            ledgerRefreshDebounceTask?.cancel()
            ledgerRefreshDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                var d = FetchDescriptor<LedgerLine>(
                    sortBy: [SortDescriptor(\LedgerLine.occurredAt, order: .reverse)]
                )
                d.fetchLimit = 100
                allLedgerLines = (try? modelContext.fetch(d)) ?? []

                // If a CollectionItem was added, removed, or had its quantity changed, reload inventory
                // and recompute live value. Use fetchCount first to avoid loading all rows when only
                // a quantity on an existing item changed (same count); fall back to full fetch only then.
                let freshCount = (try? modelContext.fetchCount(FetchDescriptor<CollectionItem>())) ?? 0
                let currentCount = collectionItems.count
                let currentTotalQty = collectionItems.reduce(0, { $0 + $1.quantity })
                let signatureChanged: Bool
                var freshItems: [CollectionItem]? = nil
                if freshCount != currentCount {
                    signatureChanged = true
                } else {
                    let all = (try? modelContext.fetch(FetchDescriptor<CollectionItem>())) ?? []
                    let freshQty = all.reduce(0, { $0 + $1.quantity })
                    signatureChanged = freshQty != currentTotalQty
                    if signatureChanged { freshItems = all }
                }
                guard signatureChanged else { return }
                await reloadDashboardInventory(deferForLaunch: false)
                // If a concurrent reload was in-flight, reloadDashboardInventory returns early
                // without updating collectionItems. Use the already-fetched items as fallback.
                if collectionItems.count != freshCount {
                    collectionItems = freshItems ?? (try? modelContext.fetch(FetchDescriptor<CollectionItem>())) ?? []
                }
                recomputeCollectionStats()
                // Skip the live-value recompute when pricing hasn't been prefetched —
                // computeLiveValue would trigger prefetchPokemonCardPricing (a full SQLite
                // scan) on every CloudKit batch delivery. The normal launch path will
                // compute the value once pricing is ready.
                guard services.pricing.isAllPokemonPricingPrefetched else { return }
                if await computeLiveValue() {
                    chartRefreshID += 1
                }
            }
        }
        .sheet(item: $selectedCardForDetail, onDismiss: restoreTabBarAfterSheet) { card in
            CardDetailSheet(cards: [card], startIndex: 0)
                .environment(services)
                .bindrTheme(accent: services.theme.accentColor)
        }
        .sheet(item: $selectedSealedProductForDetail, onDismiss: restoreTabBarAfterSheet) { product in
            SealedProductBrowseDetailView(products: [product], startProductID: product.id)
                .environment(services)
        }
        .onChange(of: selectedCardForDetail?.id) { _, cardID in
            services.isCardDetailPresentationActive = cardID != nil
            if cardID != nil {
                suppressTabBarForModalChrome?()
            }
        }
        .onChange(of: selectedSealedProductForDetail?.id) { _, productID in
            services.isSealedDetailPresentationActive = productID != nil
            if productID != nil {
                suppressTabBarForModalChrome?()
            }
        }
        .sheet(item: $editingRecentLedgerLine) { line in
            AddManualActivityView(ledgerLineToEdit: line)
        }
        .sheet(isPresented: $showProgressTrackerSheet) {
            DashboardProgressTrackerSheet { target in
                progressTracker.add(target)
                Task { await refreshProgressSnapshots() }
            }
            .environment(services)
            .bindrTheme(accent: services.theme.accentColor)
        }
        .task(id: progressSnapshotTaskKey) {
            await refreshProgressSnapshots()
        }
    }

    private var progressSnapshotTaskKey: String {
        let targetKey = progressTracker.targets
            .map { "\($0.id.uuidString)|\($0.completionMode.rawValue)" }
            .joined(separator: ";")
        return "\(targetKey)|\(collectionItems.count)|\(dashboardDataRevision)"
    }

    @MainActor
    private func refreshProgressSnapshots() async {
        guard !progressTracker.targets.isEmpty else {
            progressSnapshots = []
            return
        }
        isLoadingProgressSnapshots = true
        defer { isLoadingProgressSnapshots = false }
        progressSnapshots = await DashboardProgressEngine.snapshots(
            for: progressTracker.targets,
            collectionItems: collectionItems,
            services: services
        )
    }

    private var dashboardPageOne: some View {
        VStack(alignment: .leading, spacing: 18) {
            heroSection
            valueAndHistoryCard

            collectionSummaryInsightCard

            if !progressTracker.targets.isEmpty {
                progressTrackingSection
            } else {
                progressTrackingAddButton
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, rootFloatingChromeInset + 10)
        .padding(.bottom, RootChromeEnvironment.floatingTabBarContentInset - 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var dashboardPageTwo: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !actionableTrades.isEmpty {
                tradeActionNotificationCard
            }

            if !upcomingReleases.isEmpty {
                upcomingReleasesSection
            }

            newsAndUpdatesSection

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, rootFloatingChromeInset + 14)
        .padding(.bottom, RootChromeEnvironment.floatingTabBarContentInset - 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func restoreTabBarAfterSheet() {
        if let restoreTabBarChrome {
            restoreTabBarChrome()
        } else {
            BindrApp.reapplyTabBarAppearanceAfterPresentation(accent: services.theme.accentColor)
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(timeGreeting)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    Text("Welcome back, ")
                    Text("Trainer.")
                        .bindrAccentForeground(services.theme.accentColor)
                }
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(dashboardPrimaryText)
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private var timeGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    private var tradeActionCardTint: Color {
        guard actionableTrades.count == 1 else { return services.theme.accentColor }
        switch actionableTrades[0].status {
        case .pending: return Color(hex: "E8B84B")
        case .countered: return Color(hex: "E8934B")
        default: return services.theme.accentColor
        }
    }

    private var tradeActionCardTitle: String {
        guard actionableTrades.count == 1 else {
            return "\(actionableTrades.count) trades need your response"
        }
        switch actionableTrades[0].status {
        case .pending: return "New trade offer"
        case .countered: return "Counter offer received"
        default: return "Trade needs your response"
        }
    }

    private var tradeActionCardSubtitle: String {
        if actionableTrades.count == 1 {
            return "Tap to review and respond"
        }
        return "Tap to review your open trade offers"
    }

    private var tradeActionNotificationCard: some View {
        Button {
            Haptics.lightImpact()
            if actionableTrades.count == 1 {
                onOpenActionableTrades?(actionableTrades[0].id)
            } else {
                onOpenActionableTrades?(nil)
            }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(tradeActionCardTint.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(tradeActionCardTint)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(tradeActionCardTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(dashboardPrimaryText)
                        .multilineTextAlignment(.leading)
                    Text(tradeActionCardSubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(dashboardSecondaryText)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(dashboardSecondaryText.opacity(0.7))
            }
            .padding(16)
            .glassInsetStyle(cornerRadius: 16)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tradeActionCardTint.opacity(0.25), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tradeActionCardTitle). \(tradeActionCardSubtitle)")
    }

    private func refreshActionableTrades() async {
        guard case .signedIn(let uid, _) = services.socialAuth.authState else {
            actionableTrades = []
            return
        }
        do {
            let trades = try await services.trade.fetchMyTrades()
            actionableTrades = trades
                .filter { $0.needsResponse(from: uid) }
                .map { (
                    id: $0.id,
                    status: $0.trade.status,
                    updatedAt: $0.trade.updatedAt ?? $0.trade.createdAt
                ) }
                .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            // Keep the last known actionable trades on transient network errors.
        }
    }

    private var valueAndHistoryCard: some View {
        let _ = chartRefreshID  // force re-evaluation when recalculate completes
        return VStack(alignment: .leading, spacing: 8) {
            dashboardValueSummary

            if !activePoints.isEmpty {
                collectionValuePeriodRow
            }

            if !activePoints.isEmpty {
                Chart(activePoints) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            yStart: .value("Min", chartMin),
                            yEnd: .value("Value", point.total)
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    services.theme.chartAccentColor.opacity(0.70),
                                    services.theme.chartAccentColor.opacity(0.28),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.total)
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(services.theme.chartAccentColor)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                        if let sel = selectedPoint, sel.date == point.date {
                            RuleMark(x: .value("Date", point.date))
                                .foregroundStyle(dashboardDividerColor)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))

                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Value", point.total)
                            )
                            .symbolSize(60)
                            .foregroundStyle(dashboardPrimaryText)
                        }
                    }
                    .chartYAxis(.hidden)
                    .chartXAxis(.hidden)
                    .chartYScale(domain: chartMin...max(chartMax, chartMin + 1))
                .frame(height: 140)
                .padding(.horizontal, -16)
                .chartOverlay { proxy in
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            guard let frame = proxy.plotFrame else { return }
                                            let x = value.location.x - geo[frame].origin.x
                                            guard let date: Date = proxy.value(atX: x) else { return }
                                            let nearest = activePoints.min(by: {
                                                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                            })
                                            if nearest?.date != selectedPoint?.date {
                                                selectedPoint = nearest
                                                Haptics.selectionChanged()
                                            }
                                        }
                                        .onEnded { _ in
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                selectedPoint = nil
                                            }
                                        }
                                )
                        }
                }
                .id(chartRefreshID)
            }
        }
    }

    private var dashboardValueSummary: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total Collection Value")
                    .font(.headline)
                    .foregroundStyle(dashboardSecondaryText)

                if (isLoadingValue || services.needsCollectionValueRecalcAfterRestore) && displayedBrandSnapshot == nil {
                    ProgressView()
                        .tint(services.theme.accentColor)
                } else if isScrubbingOrLoaded {
                    Text(formatCurrency(displayTotal))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(dashboardPrimaryText)
                        .contentTransition(.numericText())
                    Text(displayValueSubtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(dashboardSecondaryText)
                    HStack(spacing: 12) {
                        Text("Cards \(formatCurrency(displayCardsValue))")
                        Text("Sealed \(formatCurrency(displaySealedValue))")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(dashboardSecondaryText)
                } else {
                    Text("No pricing data yet")
                        .font(.headline)
                        .foregroundStyle(dashboardSecondaryText)
                }
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 6) {
                if let change = periodChangeAmount {
                    Text((change >= 0 ? "+" : "") + formatCurrency(change))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(change >= 0 ? DashboardPalette.success : DashboardPalette.danger)
                        .contentTransition(.numericText())
                } else if let gain = portfolioGain {
                    Text((gain >= 0 ? "+" : "") + formatCurrency(gain))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(portfolioGainColor)
                    Text("all-time gain")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(dashboardSecondaryText)
                }
            }
        }
    }

    private var collectionValuePeriodRow: some View {
        HStack(alignment: .center, spacing: 0) {
            collectionValuePeriodColumn(
                value: collectionValueChange31Days,
                label: "Last 31 Days"
            )

            Rectangle()
                .fill(dashboardDividerColor)
                .frame(width: 1, height: 44)

            collectionValuePeriodColumn(
                value: collectionValueChange7Days,
                label: "7 Days"
            )

            Rectangle()
                .fill(dashboardDividerColor)
                .frame(width: 1, height: 44)

            collectionValuePeriodColumn(
                value: collectionValueChange1Day,
                label: "1 Day"
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }

    private func collectionValuePeriodColumn(value: Double?, label: String) -> some View {
        VStack(alignment: .center, spacing: 4) {
            HStack(spacing: 4) {
                if let value, value != 0 {
                    Image(systemName: value > 0 ? "arrow.up" : "arrow.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(trendColor(value))
                }

                Text(formatTrendPercent(value))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(trendColor(value))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }

            Text(label)
                .font(.caption)
                .foregroundStyle(dashboardSecondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var collectionSummaryInsightCard: some View {
        HStack(alignment: .center, spacing: 0) {
            collectionOverviewStatColumn(
                icon: "square.stack.3d.up.fill",
                iconColor: DashboardPalette.purple,
                count: totalCardsCount,
                label: "Cards",
                action: onOpenCollection
            )

            collectionOverviewStatColumn(
                icon: "rectangle.stack.fill",
                iconColor: DashboardPalette.blue,
                count: uniqueCardsCount,
                label: "Unique",
                action: onOpenCollection
            )

            collectionOverviewStatColumn(
                icon: "shippingbox.fill",
                iconColor: DashboardPalette.success,
                count: sealedProductsCount,
                label: "Sealed",
                action: onOpenSealedProducts
            )

            collectionOverviewStatColumn(
                icon: "star.fill",
                iconColor: DashboardPalette.gold,
                count: wishlistedCardsCount,
                label: "Wishlist",
                action: onOpenWishlist
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func collectionOverviewStatColumn(
        icon: String,
        iconColor: Color,
        count: Int,
        label: String,
        action: (() -> Void)?
    ) -> some View {
        Button {
            action?()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)

                Text(formatCollectionCount(count))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(dashboardPrimaryText)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text(label)
                    .font(.caption)
                    .foregroundStyle(dashboardSecondaryText)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(DashboardPressStyle())
        .disabled(action == nil)
    }

    private static let collectionCountFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    private func formatCollectionCount(_ count: Int) -> String {
        Self.collectionCountFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private var progressTrackingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("TRACK PROGRESS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(dashboardSecondaryText)
                    .tracking(0.6)

                Spacer(minLength: 8)

                Button {
                    Haptics.lightImpact()
                    showProgressTrackerSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(services.theme.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Track another set or Pokémon")
            }

            if isLoadingProgressSnapshots && progressSnapshots.isEmpty {
                ProgressView()
                    .tint(services.theme.accentColor)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                GeometryReader { geo in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            HStack(spacing: 20) {
                                ForEach(progressSnapshots) { snapshot in
                                    DashboardProgressRingTile(
                                        snapshot: snapshot,
                                        accentColor: services.theme.accentColor
                                    ) {
                                        progressTracker.remove(id: snapshot.targetID)
                                        progressSnapshots.removeAll { $0.targetID == snapshot.targetID }
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minWidth: geo.size.width)
                    }
                }
                .frame(height: 132)
                .padding(.horizontal, -16)
            }
        }
    }

    private var progressTrackingAddButton: some View {
        Button {
            Haptics.lightImpact()
            showProgressTrackerSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(services.theme.accentColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Track Set / Pokémon")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(dashboardPrimaryText)
                    Text("Follow full, master, or grand master completion")
                        .font(.caption)
                        .foregroundStyle(dashboardSecondaryText)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(dashboardSecondaryText.opacity(0.7))
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(DashboardPressStyle())
    }

    private var upcomingReleasesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Upcoming Releases")
                .font(.title3.weight(.semibold))
                .foregroundStyle(dashboardPrimaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(upcomingReleases) { release in
                        upcomingReleaseTile(release)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .glassInsetStyle(cornerRadius: 20)
    }

    private func upcomingReleaseTile(_ release: UpcomingRelease) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)

                if let imageURL = release.imageURL {
                    CachedAsyncImage(
                        url: imageURL,
                        targetSize: CGSize(width: 280, height: 280)
                    ) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                    } placeholder: {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(services.theme.accentColor)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Image(systemName: "photo")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(dashboardSecondaryText.opacity(0.7))
                }
            }
            .frame(width: 148, height: 148)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(dashboardBorder.opacity(0.55), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(release.name.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(dashboardPrimaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 148, height: 40, alignment: .topLeading)

                Text(release.type.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.caption2.weight(.bold))
                    .bindrAccentForeground(services.theme.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .bindrAccentFill(
                                services.theme.accentColor.opacity(0.14),
                                logoOpacity: colorScheme == .dark ? 0.26 : 0.18
                            )
                    )

                Text(release.releaseDateLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(dashboardSecondaryText)
            }
            .frame(width: 148, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(release.name), \(release.type), releases \(release.releaseDateAccessibilityLabel)")
    }

    private var newsAndUpdatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("News & Updates")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(dashboardPrimaryText)

                Spacer(minLength: 8)

                Text("BINDR")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .bindrAccentForeground(services.theme.chartAccentColor)
            }

            VStack(spacing: 0) {
                ForEach(Array(Self.placeholderNewsUpdates.enumerated()), id: \.element.id) { index, item in
                    newsUpdateRow(item)

                    if index < Self.placeholderNewsUpdates.count - 1 {
                        Divider()
                            .overlay(dashboardDividerColor)
                            .padding(.leading, 46)
                    }
                }
            }
        }
        .padding(16)
        .glassInsetStyle(cornerRadius: 20)
    }

    private func newsUpdateRow(_ item: NewsUpdate) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(services.theme.chartAccentColor)
                .frame(width: 34, height: 34)
                .background(services.theme.chartAccentColor.opacity(0.13), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(dashboardPrimaryText)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(item.label)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(services.theme.chartAccentColor)
                }

                Text(item.summary)
                    .font(.caption)
                    .foregroundStyle(dashboardSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var recentActivityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent Activity")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(dashboardPrimaryText)
                Spacer()
                if let onViewAllActivity {
                    Button("View All") { onViewAllActivity() }
                        .font(.subheadline.weight(.medium))
                        .bindrAccentForeground(services.theme.accentColor)
                }
            }

            if recentLines.isEmpty {
                Text("No transactions yet.")
                    .font(.subheadline)
                    .foregroundStyle(dashboardSecondaryText)
            } else {
                VStack(spacing: 0) {
                    ForEach(recentLines) { line in
                        Button {
                            openRecentActivityDetail(for: line)
                        } label: {
                            dashboardActivityRow(line: line)
                        }
                        .buttonStyle(.plain)
                        if line.id != recentLines.last?.id {
                            Divider()
                                .overlay(dashboardDividerColor)
                        }
                    }
                }
            }
        }
    }

    private var dashboardBackground: some View {
        BindrPageBackground()
    }

    private var dashboardDataSignature: Int {
        // Keep this O(1) / O(recent-lines) — never iterate all collection items here.
        // dashboardDataRevision captures inventory reloads; recentLines covers activity changes.
        // hasFiredInitialLoadComplete must be included so the task re-fires once the launch
        // handoff completes — without it, the task exits early on first fire (guard returns)
        // and never retries because the rest of the signature hasn't changed.
        var h = Hasher()
        h.combine(activeBrand.rawValue)
        h.combine(dashboardDataRevision)
        h.combine(hasFiredInitialLoadComplete)
        for line in recentLines { h.combine(line.id) }
        return h.finalize()
    }

    /// Re-runs when launch handoff or catalog sync finish so daily blobs load on first paint.
    private var supplementalDashboardDataTrigger: String {
        [
            hasFiredInitialLoadComplete,
            services.isLaunchCatalogPipelineComplete,
            services.isCatalogDownloadInProgress,
        ].map { "\($0)" }.joined(separator: "|")
    }

    private func dashboardActivityRow(line: LedgerLine) -> some View {
        HStack(spacing: 12) {
            activityLeadingVisual(for: line)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(activityTitle(for: line))
                        .font(.headline)
                        .foregroundStyle(dashboardPrimaryText)
                        .lineLimit(1)

                    if badgeText(for: line) != nil {
                        Text(badgeText(for: line) ?? "")
                            .font(.caption2.weight(.semibold))
                            .bindrAccentForeground(services.theme.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .bindrAccentFill(
                                        activityBadgeBackground,
                                        logoOpacity: colorScheme == .dark ? 0.24 : 0.16
                                    )
                            )
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(
                                        services.theme.isGradientThemeSelected
                                            ? services.theme.secondaryAccentColor.opacity(0.34)
                                            : services.theme.accentColor.opacity(0.28),
                                        lineWidth: 1
                                    )
                            }
                    }

                    Spacer(minLength: 8)

                    Text(line.occurredAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(dashboardSecondaryText)
                }

                HStack(spacing: 8) {
                    Text(activitySubtitle(for: line))
                        .font(.subheadline)
                        .foregroundStyle(dashboardSecondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(dashboardSecondaryText)
                }
            }
        }
        .padding(.vertical, 12)
    }

    private var activityBadgeBackground: Color {
        services.theme.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.08)
    }

    @ViewBuilder
    private func activityLeadingVisual(for line: LedgerLine) -> some View {
        if let imageURL = activityImageURL(for: line) {
            CachedAsyncImage(url: imageURL, targetSize: CGSize(width: 120, height: 168)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } placeholder: {
                fallbackCardArtwork(for: line)
            }
            .frame(width: 48, height: 68)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(dashboardBorder, lineWidth: 1)
            )
        } else {
            fallbackCardArtwork(for: line)
        }
    }

    private func activityImageURL(for line: LedgerLine) -> URL? {
        if let cardID = cleaned(line.cardID), let imageURL = cardImageURLsByID[cardID] {
            return imageURL
        }

        guard line.productKind == ProductKind.sealedProduct.rawValue else { return nil }

        if let rawID = cleaned(line.sealedProductId),
           let productID = Int(rawID),
           let imageURL = services.sealedProducts.productsByID[productID]?.imageURL {
            return imageURL
        }

        if let cardID = cleaned(line.cardID),
           let productID = SealedProduct.parseCollectionProductID(cardID),
           let imageURL = services.sealedProducts.productsByID[productID]?.imageURL {
            return imageURL
        }

        return nil
    }

    private func fallbackCardArtwork(for line: LedgerLine) -> some View {
        let cardName: String = {
            if let cardID = cleaned(line.cardID), let name = cardNamesByID[cardID] {
                return name
            }
            return cleaned(line.lineDescription) ?? "Card"
        }()

        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(dashboardCardInsetBackground)
            .frame(width: 48, height: 68)
            .overlay {
                VStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Text(cardArtworkFallback(for: cardName))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(dashboardPrimaryText)
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(dashboardSecondaryText)
                    Spacer(minLength: 0)
                }
            .padding(.vertical, 6)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(dashboardBorder, lineWidth: 1)
            )
    }

    private func dashboardSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            content()

            Rectangle()
                .fill(dashboardDividerColor)
                .frame(height: 1)
        }
        .padding(.top, 8)
    }

    private func prepareInitialDashboardData() async {
        guard !hasPreparedInitialDashboardData, !isPreparingInitialDashboardData else { return }
        guard let svc = services.collectionValue else { return }
        isPreparingInitialDashboardData = true
        defer { isPreparingInitialDashboardData = false }

        onInitialLoadStatusChange?("Loading your collection...")
        await reloadDashboardInventory(deferForLaunch: false)
        recomputeCollectionStats()

        await svc.loadAllFromStore()
        applyValuePlaceholder(from: svc)
        // Paint the chart from persisted snapshots now — don't wait for live pricing prefetch.
        chartRefreshID += 1

        // Unblock the launch overlay with the persisted placeholder — live pricing runs after fade.
        hasPreparedInitialDashboardData = true
        fireInitialLoadCompleteIfReady()

        if collectionItems.count > 0 {
            Task { @MainActor in
                if await computeLiveValue() {
                    chartRefreshID += 1
                }
            }
        }
    }

    /// Instant placeholder while live pricing loads — never treated as authoritative.
    private func applyValuePlaceholder(from svc: CollectionValueService) {
        let placeholder = svc.brandSnapshot(for: Date())
            ?? svc.todayPersistedSnapshot()
        guard let placeholder, placeholder.total > 0 else { return }
        liveTotalGbp = placeholder.total
        livePokemonGbp = placeholder.pokemon
        liveCardsGbp = placeholder.cards
        liveSealedGbp = placeholder.sealed
    }

    private func reloadDashboardInventory(deferForLaunch: Bool) async {
        guard services.isLaunchCatalogPipelineComplete else { return }
        guard !isLoadingDashboardInventory else { return }
        isLoadingDashboardInventory = true
        defer { isLoadingDashboardInventory = false }

        if deferForLaunch {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
        }

        var wishlistDescriptor = FetchDescriptor<WishlistItem>(
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        wishlistDescriptor.fetchLimit = 500
        var collectionDescriptor = FetchDescriptor<CollectionItem>()
        collectionDescriptor.fetchLimit = 5000
        var ledgerDescriptor = FetchDescriptor<LedgerLine>(
            sortBy: [SortDescriptor(\LedgerLine.occurredAt, order: .reverse)]
        )
        ledgerDescriptor.fetchLimit = 100
        collectionItems = (try? modelContext.fetch(collectionDescriptor)) ?? []
        wishlistItems = (try? modelContext.fetch(wishlistDescriptor)) ?? []
        allLedgerLines = (try? modelContext.fetch(ledgerDescriptor)) ?? []
        binderCount = (try? modelContext.fetchCount(FetchDescriptor<Binder>())) ?? 0
        dashboardDataRevision += 1
    }

    @discardableResult
    private func computeLiveValue(validateAgainstRestore: Bool = false) async -> Bool {
        isLoadingValue = true
        defer { isLoadingValue = false }

        if services.sealedProducts.products.isEmpty {
            await services.sealedProducts.loadFromLocalIfAvailable()
        }
        if !services.pricing.isAllPokemonPricingPrefetched {
            await services.pricing.prefetchPokemonCardPricing(forSetCodes: [])
        }

        guard let svc = services.collectionValue else { return liveTotalGbp != nil }
        guard let snap = await svc.computeLiveSnapshot(for: collectionItems), snap.total > 0 else {
            return liveTotalGbp != nil
        }

        if validateAgainstRestore,
           let anchorTotal = svc.latestSnapshotTotalBeforeToday(),
           anchorTotal > 0,
           snap.total < anchorTotal * 0.75 {
            return false
        }

        var totalCost = 0.0
        for item in collectionItems {
            guard item.quantity > 0 else { continue }
            guard item.sealedStatus != SealedInventoryStatus.opened.rawValue else { continue }
            totalCost += (item.purchasePrice ?? 0) * Double(item.quantity)
        }

        liveTotalGbp = snap.total
        livePokemonGbp = snap.pokemon
        liveCardsGbp = snap.cards
        liveSealedGbp = snap.sealed
        totalCostBasis = totalCost

        _ = svc.updateTodaySnapshot(snap)
        svc.persistLastKnownValue(snap)
        await svc.loadAllFromStore()
        lastLiveValueComputedAt = Date()
        return true
    }

    private func fireInitialLoadCompleteIfReady() {
        guard !hasFiredInitialLoadComplete else { return }
        hasFiredInitialLoadComplete = true
        onInitialLoadComplete?()
        // Load chart history just past the overlay fade. loadAllFromStore reads on a background
        // ModelContext, so this only needs to clear the first interactive frame.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard let svc = services.collectionValue else { return }
            await svc.loadAllFromStore()
            chartRefreshID += 1
        }
    }

    private func sealedProductID(for item: CollectionItem) -> Int? {
        if let rawID = item.sealedProductId,
           let productID = Int(rawID) {
            return productID
        }
        return SealedProduct.parseCollectionProductID(item.cardID)
    }

    private func sealedProductID(for line: LedgerLine) -> Int? {
        if let rawID = cleaned(line.sealedProductId), let productID = Int(rawID) {
            return productID
        }
        if let cardID = cleaned(line.cardID) {
            return SealedProduct.parseCollectionProductID(cardID)
        }
        return nil
    }

    private func openRecentActivityDetail(for line: LedgerLine) {
        if line.productKind == ProductKind.sealedProduct.rawValue {
            Task {
                await services.sealedProducts.loadFromLocalIfAvailable()
                guard let productID = sealedProductID(for: line),
                      let product = services.sealedProducts.productsByID[productID]
                else { return }
                await MainActor.run { selectedSealedProductForDetail = product }
            }
            return
        }

        guard let cardID = cleaned(line.cardID) else { return }
        if let cached = services.cardData.cachedCard(masterCardId: cardID) {
            selectedCardForDetail = cached
            return
        }
        Task {
            if let card = await services.cardData.loadCard(masterCardId: cardID) {
                selectedCardForDetail = card
            }
        }
    }

    private func resolveDashboardMetadata() async {
        // Snapshot inputs on @MainActor before leaving.
        let currentMetadata = cardMetadata
        let cardIDs = Set(visibleCollectionItems.map(\.cardID) + recentLines.compactMap { cleaned($0.cardID) })
        let enabledBrands = services.brandSettings.enabledBrands
        let cardData = services.cardData

        // Do all I/O off @MainActor so intermediate awaits don't trigger SwiftUI
        // body re-renders mid-computation. One hop back at the very end to write state.
        let result = await Task.detached(priority: .userInitiated) {
            var nextNames = currentMetadata.namesByID
            var nextSets = currentMetadata.setNamesByCardID
            var nextImages = currentMetadata.imageURLsByID
            var setsByBrandAndCode: [String: String] = [:]

            for brand in enabledBrands {
                guard let sets = try? await CatalogStore.shared.fetchAllSets(for: brand) else { continue }
                for set in sets {
                    setsByBrandAndCode["\(brand.rawValue)|\(set.setCode)"] = set.name
                }
            }

            let missingIDs = cardIDs.filter {
                nextNames[$0] == nil || nextSets[$0] == nil || nextImages[$0] == nil
            }
            guard !missingIDs.isEmpty else {
                return CardMetadataCache(namesByID: nextNames, setNamesByCardID: nextSets, imageURLsByID: nextImages)
            }

            let pokemonIDs = missingIDs.filter { !$0.hasPrefix("sealed:") }

            let allCards = await cardData.loadCards(masterCardIDs: Array(pokemonIDs), catalogBrand: .pokemon)

            for card in allCards {
                let cardID = card.masterCardId
                nextNames[cardID] = card.cardName
                if nextImages[cardID] == nil {
                    nextImages[cardID] = AppConfiguration.imageURL(relativePath: card.displayImageSrc)
                }
                let brand = TCGBrand.inferredFromMasterCardId(cardID)
                if let setName = setsByBrandAndCode["\(brand.rawValue)|\(card.setCode)"] {
                    nextSets[cardID] = setName
                }
            }

            return CardMetadataCache(namesByID: nextNames, setNamesByCardID: nextSets, imageURLsByID: nextImages)
        }.value

        // Single @MainActor state write — one render pass, no interleaved re-renders.
        cardMetadata = result
    }

    private func activityTitle(for line: LedgerLine) -> String {
        if let cardID = cleaned(line.cardID), let cardName = cardNamesByID[cardID] {
            return "\(line.quantity) x \(cardName)"
        }
        if let description = cleaned(line.lineDescription) {
            return "\(line.quantity) x \(description)"
        }
        return "Collection update"
    }

    private func activitySubtitle(for line: LedgerLine) -> String {
        let setName: String? = {
            if let cardID = cleaned(line.cardID), let setName = setNamesByCardID[cardID] {
                return setName
            }
            return nil
        }()

        if case .some(.bought) = LedgerDirection(rawValue: line.direction),
           let unitPrice = line.unitPrice {
            let priceLabel = unitPrice.formatted(
                .currency(code: line.currencyCode)
                .precision(.fractionLength(2))
            )
            if let setName {
                return "\(setName) · \(priceLabel)"
            }
            return priceLabel
        }

        if let setName {
            return setName
        }
        return cleaned(line.lineDescription) ?? line.occurredAt.formatted(date: .abbreviated, time: .omitted)
    }

    private func badgeText(for line: LedgerLine) -> String? {
        guard let direction = LedgerDirection(rawValue: line.direction) else { return nil }
        switch direction {
        case .packed: return "Packed"
        case .bought: return "Bought"
        case .sold: return "Sold"
        case .tradedIn, .tradedOut: return "Traded"
        case .giftedIn, .giftedOut: return "Gifted"
        case .importedIn: return "Imported"
        case .adjustmentIn, .adjustmentOut:
            if line.sealedStatus == SealedInventoryStatus.opened.rawValue {
                return "Opened"
            }
            return "Adjusted"
        }
    }

    private func productKindTitle(for line: LedgerLine) -> String {
        guard let kind = ProductKind(rawValue: line.productKind) else { return line.productKind }
        switch kind {
        case .singleCard: return "Single card"
        case .gradedItem: return "Graded item"
        case .sealedProduct: return "Sealed product"
        case .boosterPack: return "Booster pack"
        case .etb: return "ETB"
        case .other: return "Other"
        }
    }

    private func transactionMoneySummary(for line: LedgerLine) -> String? {
        guard let unitPrice = line.unitPrice else { return nil }
        let total = unitPrice * Double(line.quantity)
        return total.formatted(
            .currency(code: line.currencyCode)
            .precision(.fractionLength(2))
        )
    }

    private func markActions(for line: LedgerLine) -> [TransactionMarkAction] {
        var actions: [TransactionMarkAction] = [
            .bought, .sold, .packed, .tradedIn, .tradedOut, .giftedIn, .giftedOut, .adjustmentIn, .adjustmentOut
        ]
        if line.productKind == ProductKind.sealedProduct.rawValue {
            actions.append(.opened)
        }
        return actions
    }

    private func markLedgerLine(_ line: LedgerLine, as action: TransactionMarkAction) {
        let isSealedProduct = line.productKind == ProductKind.sealedProduct.rawValue

        switch action {
        case .bought:
            line.direction = LedgerDirection.bought.rawValue
            line.sealedStatus = isSealedProduct ? SealedInventoryStatus.sealed.rawValue : nil
        case .sold:
            line.direction = LedgerDirection.sold.rawValue
            line.sealedStatus = isSealedProduct ? SealedInventoryStatus.sealed.rawValue : nil
        case .packed:
            line.direction = LedgerDirection.packed.rawValue
            line.sealedStatus = isSealedProduct ? SealedInventoryStatus.sealed.rawValue : nil
        case .tradedIn:
            line.direction = LedgerDirection.tradedIn.rawValue
            line.sealedStatus = isSealedProduct ? SealedInventoryStatus.sealed.rawValue : nil
        case .tradedOut:
            line.direction = LedgerDirection.tradedOut.rawValue
            line.sealedStatus = isSealedProduct ? SealedInventoryStatus.sealed.rawValue : nil
        case .giftedIn:
            line.direction = LedgerDirection.giftedIn.rawValue
            line.sealedStatus = isSealedProduct ? SealedInventoryStatus.sealed.rawValue : nil
        case .giftedOut:
            line.direction = LedgerDirection.giftedOut.rawValue
            line.sealedStatus = isSealedProduct ? SealedInventoryStatus.sealed.rawValue : nil
        case .adjustmentIn:
            line.direction = LedgerDirection.adjustmentIn.rawValue
            line.sealedStatus = isSealedProduct ? SealedInventoryStatus.sealed.rawValue : nil
        case .adjustmentOut:
            line.direction = LedgerDirection.adjustmentOut.rawValue
            line.sealedStatus = isSealedProduct ? SealedInventoryStatus.sealed.rawValue : nil
        case .opened:
            line.direction = LedgerDirection.adjustmentOut.rawValue
            line.sealedStatus = SealedInventoryStatus.opened.rawValue
        }

        do {
            try modelContext.save()
            HapticManager.notification(.success)
        } catch {
            HapticManager.notification(.error)
        }
    }

    private func rangeLabel(for date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private func xAxisLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "GBP"
        f.maximumFractionDigits = 2
        return f
    }()

    private func formatCurrency(_ value: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: value)) ?? "£\(String(format: "%.2f", value))"
    }

    private func formatCurrencyShort(_ value: Double) -> String {
        guard value >= 1000 else {
            return "£\(String(format: "%.0f", value))"
        }
        // Use extra decimal places when the visible chart range is tight enough
        // that 1 decimal place would produce duplicate Y-axis labels.
        let range = chartMax - chartMin
        if range < 200 {
            return "£\(String(format: "%.2fk", value / 1000))"
        } else if range < 500 {
            return "£\(String(format: "%.1fk", value / 1000))"
        }
        return "£\(String(format: "%.1fk", value / 1000))"
    }

    private func loadUpcomingReleases() async {
        upcomingReleases = await UpcomingReleasesService.loadReleasesPreferringNetwork()
    }

    private func formatTrendPercent(_ value: Double?) -> String {
        guard let value else { return "N/A" }
        return String(format: "%@%.2f%%", value >= 0 ? "+" : "", value)
    }

    private func trendColor(_ value: Double?) -> Color {
        guard let value else { return dashboardSecondaryText }
        if value > 0 { return DashboardPalette.success }
        if value < 0 { return DashboardPalette.danger }
        return dashboardSecondaryText
    }

    private func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func cardArtworkFallback(for cardName: String) -> String {
        let pieces = cardName.split(separator: " ")
        let initials = pieces.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return initials.isEmpty ? "TCG" : initials.uppercased()
    }

    private func directionIcon(for line: LedgerLine) -> String {
        guard let dir = LedgerDirection(rawValue: line.direction) else { return "circle.fill" }
        switch dir {
        case .bought: return "cart.fill"
        case .packed: return "shippingbox.fill"
        case .sold: return "sterlingsign.circle.fill"
        case .tradedIn: return "arrow.left.arrow.right.circle.fill"
        case .tradedOut: return "arrow.left.arrow.right.circle"
        case .giftedIn: return "gift.fill"
        case .giftedOut: return "gift"
        case .adjustmentIn: return "plus.circle.fill"
        case .adjustmentOut: return "minus.circle.fill"
        case .importedIn: return "square.and.arrow.down.fill"
        }
    }

    private func directionColor(for line: LedgerLine) -> Color {
        guard let dir = LedgerDirection(rawValue: line.direction) else { return dashboardSecondaryText }
        switch dir {
        case .bought, .packed, .tradedIn, .giftedIn, .adjustmentIn, .importedIn:
            return DashboardPalette.success
        case .sold, .tradedOut, .giftedOut, .adjustmentOut:
            return DashboardPalette.danger
        }
    }
}

private struct ChartPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let total: Double
    let pokemon: Double
    let cards: Double?
    let sealed: Double?
}

private struct DashboardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private enum DashboardPalette {
    static let purple = Color(red: 0.58, green: 0.33, blue: 1.0)
    static let blue = Color(red: 0.24, green: 0.58, blue: 1.0)
    static let success = Color(red: 0.28, green: 0.84, blue: 0.39)
    static let gold = Color(red: 0.99, green: 0.72, blue: 0.22)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.34)
}
