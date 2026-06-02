import SwiftUI
import SwiftData
import Charts

private enum ChartRange: String, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"

    var id: String { rawValue }
}

struct DashboardView: View {
    var onViewAllActivity: (() -> Void)? = nil
    var onOpenScanner: (() -> Void)? = nil
    var onOpenCollection: (() -> Void)? = nil
    var onOpenSealedProducts: (() -> Void)? = nil
    var onOpenWishlist: (() -> Void)? = nil
    var onOpenBrowse: (() -> Void)? = nil
    var onInitialLoadStatusChange: ((String) -> Void)? = nil
    var onInitialLoadComplete: (() -> Void)? = nil

    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @Environment(\.scenePhase) private var scenePhase

    // Manual @State instead of @Query so CloudKit background syncs don't trigger
    // DashboardView body re-renders. @Query fires on every SwiftData save — including
    // every CloudKit record delivery — which blocked the main thread for 8-9 seconds
    // after launch with 1000+ collection items. Ledger lines are refreshed explicitly
    // in reloadDashboardInventory and via a debounced SwiftData notification observer.
    @State private var allLedgerLines: [LedgerLine] = []
    @State private var ledgerRefreshDebounceTask: Task<Void, Never>? = nil
    @AppStorage("dismissedMilestones") private var dismissedMilestonesData: Data = Data()

    @State private var collectionItems: [CollectionItem] = []
    @State private var wishlistItems: [WishlistItem] = []
    @State private var binderCount = 0
    @State private var dashboardDataRevision = 0
    @State private var isLoadingDashboardInventory = false
    @State private var isPreparingInitialDashboardData = false
    @State private var hasPreparedInitialDashboardData = false
    @State private var liveTotalGbp: Double? = nil
    @State private var livePokemonGbp: Double = 0
    @State private var liveOnePieceGbp: Double = 0
    @State private var liveCardsGbp: Double = 0
    @State private var liveSealedGbp: Double = 0
    @State private var totalCostBasis: Double = 0
    @State private var isLoadingValue = false
    @State private var hasFiredInitialLoadComplete = false
    @State private var selectedPoint: ChartPoint? = nil
    @State private var chartRange: ChartRange = .daily
    @State private var chartRefreshID: Int = 0
    @State private var selectedBrand: TCGBrand? = nil
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
    @State private var marketTrendData: MarketTrendDailyBlob? = nil
    @State private var editingRecentLedgerLine: LedgerLine?
    @State private var selectedCardForDetail: Card? = nil
    @State private var selectedSealedProductForDetail: SealedProduct? = nil

    // Cached collection stats — updated via task when collectionItems/brand changes,
    // so SwiftUI body evaluation never pays the O(n) cost of iterating 997+ items.
    @State private var cachedTotalCardsCount: Int = 0
    @State private var cachedUniqueCardsCount: Int = 0
    @State private var cachedSealedProductsCount: Int = 0
    @State private var cachedWishlistedCardsCount: Int = 0

    private var liveSnapshot: BrandSnapshot? {
        guard let t = liveTotalGbp else { return nil }
        return BrandSnapshot(
            total: t,
            pokemon: livePokemonGbp,
            onePiece: liveOnePieceGbp,
            cards: liveCardsGbp,
            sealed: liveSealedGbp
        )
    }

    private var displayTotal: Double {
        let point = selectedPoint
        switch selectedBrand {
        case .pokemon:  return point?.pokemon ?? livePokemonGbp
        case .onePiece: return point?.onePiece ?? liveOnePieceGbp
        case nil:       return point?.total ?? liveTotalGbp ?? 0
        }
    }

    private var isScrubbingOrLoaded: Bool { selectedPoint != nil || liveTotalGbp != nil }
    private var displayCardsValue: Double {
        if let point = selectedPoint, let cards = point.cards { return cards }
        return liveCardsGbp
    }
    private var displaySealedValue: Double {
        if let point = selectedPoint, let sealed = point.sealed { return sealed }
        return liveSealedGbp
    }
    private var activeBrand: TCGBrand { services.brandSettings.selectedCatalogBrand }
    private var activeMarketTrend: MarketTrendMetrics? {
        guard let marketTrendData else { return nil }
        switch activeBrand {
        case .pokemon: return marketTrendData.pokemon
        case .onePiece: return marketTrendData.onepiece
        }
    }

    private var visibleCollectionItems: [CollectionItem] {
        collectionItems.filter { TCGBrand.inferredFromMasterCardId($0.cardID) == activeBrand }
    }

    private var visibleCardCollectionItems: [CollectionItem] {
        visibleCollectionItems.filter { sealedProductID(for: $0) == nil }
    }

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
        cachedTotalCardsCount = visible.reduce(0) { $0 + max($1.quantity, 0) }
        cachedUniqueCardsCount = Set(visible.filter { sealedProductID(for: $0) == nil }.map(\.cardID)).count
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
        colorScheme == .dark ? .black : .white
    }

    private var dashboardCardInsetBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)
    }

    private var dashboardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private var dashboardDividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)
    }

    private var backfillTrigger: String {
        "\(services.collectionValue == nil ? "nil" : "ready"):\(collectionItems.count):\(services.isLaunchCatalogPipelineComplete)"
    }

    private var dailyPoints: [ChartPoint] {
        let svc = services.collectionValue
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -31, to: cal.startOfDay(for: Date()))!
        var pointsByDay: [Date: ChartPoint] = [:]
        if let svc {
            for snapshot in svc.snapshots {
                let day = cal.startOfDay(for: snapshot.date)
                guard day >= cutoff else { continue }
                pointsByDay[day] = ChartPoint(
                    date: day,
                    total: snapshot.totalGbp,
                    pokemon: snapshot.pokemonGbp,
                    onePiece: snapshot.onePieceGbp,
                    cards: snapshot.cardsGbp > 0 || snapshot.sealedGbp > 0 ? snapshot.cardsGbp : snapshot.totalGbp,
                    sealed: snapshot.cardsGbp > 0 || snapshot.sealedGbp > 0 ? snapshot.sealedGbp : 0
                )
            }
        }
        if let live = liveTotalGbp {
            let today = cal.startOfDay(for: Date())
            // Always use today's live value so the chart matches the summary value card.
            pointsByDay[today] = ChartPoint(
                date: today,
                total: live,
                pokemon: livePokemonGbp,
                onePiece: liveOnePieceGbp,
                cards: liveCardsGbp,
                sealed: liveSealedGbp
            )
        }
        return pointsByDay.keys.sorted().compactMap { pointsByDay[$0] }
    }

    private var weeklyPoints: [ChartPoint] {
        guard let svc = services.collectionValue else { return [] }
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .year, value: -1, to: cal.startOfDay(for: Date()))!
        return svc.weeklyAverages
            .filter { $0.weekStart >= cutoff }
            .map {
                let hasExplicitSplit = $0.cardsGbp > 0 || $0.sealedGbp > 0
                return ChartPoint(
                    date: $0.weekStart,
                    total: $0.totalGbp,
                    pokemon: $0.pokemonGbp,
                    onePiece: $0.onePieceGbp,
                    cards: hasExplicitSplit ? $0.cardsGbp : $0.totalGbp,
                    sealed: hasExplicitSplit ? $0.sealedGbp : 0
                )
            }
    }

    private var monthlyPoints: [ChartPoint] {
        guard let svc = services.collectionValue else { return [] }
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .year, value: -5, to: cal.startOfDay(for: Date()))!
        return svc.monthlyAverages
            .filter { $0.monthStart >= cutoff }
            .map {
                let hasExplicitSplit = $0.cardsGbp > 0 || $0.sealedGbp > 0
                return ChartPoint(
                    date: $0.monthStart,
                    total: $0.totalGbp,
                    pokemon: $0.pokemonGbp,
                    onePiece: $0.onePieceGbp,
                    cards: hasExplicitSplit ? $0.cardsGbp : $0.totalGbp,
                    sealed: hasExplicitSplit ? $0.sealedGbp : 0
                )
            }
    }

    private var activePoints: [ChartPoint] {
        let base: [ChartPoint]
        switch chartRange {
        case .daily: base = dailyPoints
        case .weekly: base = weeklyPoints
        case .monthly: base = monthlyPoints
        }
        guard let brand = selectedBrand else { return base }
        return base.map { point in
            let total: Double
            switch brand {
            case .pokemon: total = point.pokemon
            case .onePiece: total = point.onePiece
            }
            return ChartPoint(
                date: point.date,
                total: total,
                pokemon: point.pokemon,
                onePiece: point.onePiece,
                cards: point.cards,
                sealed: point.sealed
            )
        }
    }

    private var chartMin: Double { (activePoints.map(\.total).min() ?? 0) * 0.95 }
    private var chartMax: Double { (activePoints.map(\.total).max() ?? 0) * 1.05 }

    private var chartXAxisDates: [Date] {
        let points = activePoints
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

    private var periodChange: (amount: Double, pct: Double, label: String)? {
        let points = activePoints
        guard points.count >= 2 else { return nil }

        let currentIndex: Int
        if let sel = selectedPoint, let idx = points.firstIndex(where: { $0.date == sel.date }) {
            guard idx > 0 else { return nil }
            currentIndex = idx
        } else {
            currentIndex = points.count - 1
        }

        let current = points[currentIndex].total
        let previous = points[currentIndex - 1].total
        guard previous > 0 else { return nil }

        let amount = current - previous
        let pct = (amount / previous) * 100

        let label: String
        switch chartRange {
        case .daily: label = "vs prev day"
        case .weekly: label = "vs prev week"
        case .monthly: label = "vs prev month"
        }

        return (amount, pct, label)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                heroSection
                milestoneBanner
                valueAndHistoryCard
                dashboardCard { collectionSummaryInsightCard }
                if let trend = activeMarketTrend {
                    marketTrendCard(trend: trend, updatedAt: marketTrendData?.updatedAt)
                }
                recentActivityCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .safeAreaPadding(.top, rootFloatingChromeInset)
        .background(dashboardBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(services.collectionValue != nil):\(services.isLaunchCatalogPipelineComplete)") {
            guard services.collectionValue != nil else { return }
            guard services.isLaunchCatalogPipelineComplete else { return }
            await prepareInitialDashboardData()
        }
        .task(id: "\(collectionItems.count):\(services.isLaunchCatalogPipelineComplete)") {
            guard collectionItems.count > 0, services.isLaunchCatalogPipelineComplete else { return }
            guard hasFiredInitialLoadComplete, !hasPreparedInitialDashboardData else { return }
            // Let the first interactive frame settle before recomputing the live value.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, !hasPreparedInitialDashboardData else { return }
            await computeLiveValue()
            hasPreparedInitialDashboardData = true
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
            print("[Dashboard⏱] runBackfillIfNeeded start")
            let t = ContinuousClock().now
            await svc.runBackfillIfNeeded(
                collectionItems: collectionItems,
                preferredTodaySnapshot: liveSnapshot
            )
            print("[Dashboard⏱] runBackfillIfNeeded: \(ContinuousClock().now - t)")
        }
        .task(id: dashboardDataSignature) {
            guard hasFiredInitialLoadComplete else { return }
            guard visibleCollectionItems.count > 0 || allLedgerLines.count > 0 else { return }
            // Defer card metadata + market trend just past the overlay fade so they don't
            // compete with the first interactive frame.
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            let t = ContinuousClock().now
            await resolveDashboardMetadata()
            print("[Dashboard⏱] resolveDashboardMetadata: \(ContinuousClock().now - t)")
            let t2 = ContinuousClock().now
            await loadMarketTrendBlob()
            print("[Dashboard⏱] loadMarketTrendBlob: \(ContinuousClock().now - t2)")
        }
        .task(id: services.dashboardMarketReloadToken) {
            guard services.dashboardMarketReloadToken > 0 else { return }
            guard hasFiredInitialLoadComplete else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await reloadDashboardInventory(deferForLaunch: false)
            await computeLiveValue()
            chartRefreshID += 1
            await loadMarketTrendBlob()
        }
        .onChange(of: services.isCatalogDownloadInProgress) { _, inProgress in
            guard !inProgress else { return }
            Task {
                guard hasFiredInitialLoadComplete else { return }
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                await reloadDashboardInventory(deferForLaunch: false)
                await computeLiveValue()
                if let snap = liveSnapshot {
                    await services.collectionValue?.forceRecalculate(
                        liveSnapshot: snap,
                        collectionItems: collectionItems
                    )
                }
                await loadMarketTrendBlob()
            }
        }
        .onAppear {
            selectedBrand = activeBrand
        }
        .task(id: "\(dashboardDataRevision):\(activeBrand.rawValue)") {
            recomputeCollectionStats()
        }
        .onChange(of: services.brandSettings.selectedCatalogBrand) { _, brand in
            selectedBrand = brand
            selectedPoint = nil
        }
        .onChange(of: chartRange) { _, _ in
            selectedPoint = nil
            selectedBrand = activeBrand
        }
        .onChange(of: services.pricing.usdToGbp) { old, new in
            // Skip recompute if the rate change is < 0.5% (daily FX moves are tiny).
            let delta = abs(new - old) / max(old, 1e-9)
            guard delta >= 0.005 else { return }
            print("[Dashboard] usdToGbp changed \(String(format: "%.4f", old))→\(String(format: "%.4f", new)) (\(String(format: "%.2f", delta * 100))%) — recomputing live value")
            Task {
                let t = ContinuousClock().now
                await computeLiveValue()
                print("[Dashboard] usdToGbp recompute done: \(ContinuousClock().now - t)")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, let snapshot = liveSnapshot {
                services.collectionValue?.persistLastKnownValue(snapshot)
            }
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
                // and recompute live value.
                let freshItems = (try? modelContext.fetch(FetchDescriptor<CollectionItem>())) ?? []
                let freshSignature = freshItems.reduce(into: (count: 0, totalQty: 0)) {
                    $0.count += 1
                    $0.totalQty += $1.quantity
                }
                let currentSignature = collectionItems.reduce(into: (count: 0, totalQty: 0)) {
                    $0.count += 1
                    $0.totalQty += $1.quantity
                }
                guard freshSignature != currentSignature else { return }
                await reloadDashboardInventory(deferForLaunch: false)
                // If a concurrent reload was in-flight, reloadDashboardInventory returns early
                // without updating collectionItems. Use freshItems directly so computeLiveValue
                // always sees the latest collection regardless.
                if collectionItems.count != freshSignature.count || collectionItems.reduce(0, { $0 + $1.quantity }) != freshSignature.totalQty {
                    collectionItems = freshItems
                }
                recomputeCollectionStats()
                await computeLiveValue()
            }
        }
        .sheet(item: $selectedCardForDetail) { card in
            CardDetailSheet(cards: [card], startIndex: 0)
                .environment(services)
        }
        .sheet(item: $selectedSealedProductForDetail) { product in
            SealedProductBrowseDetailView(products: [product], startProductID: product.id)
                .environment(services)
        }
        .onChange(of: selectedSealedProductForDetail?.id) { _, productID in
            services.isSealedDetailPresentationActive = (productID != nil)
        }
        .sheet(item: $editingRecentLedgerLine) { line in
            AddManualActivityView(ledgerLineToEdit: line)
        }
    }

    private var milestoneBanner: some View {
        guard let milestone = activeMilestone else { return AnyView(EmptyView()) }
        
        return AnyView(
            HStack(spacing: 12) {
                Image(systemName: "trophy.fill")
                    .font(.title3)
                    .foregroundStyle(Color(hex: "f59e0b"))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(milestone.title)
                        .font(.subheadline.weight(.bold))
                    Text(milestone.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    dismissMilestone(milestone.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: "f59e0b").opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(hex: "f59e0b").opacity(0.2), lineWidth: 1)
                    }
            }
        )
    }

    private struct Milestone: Identifiable {
        let id: String
        let title: String
        let description: String
    }

    private var activeMilestone: Milestone? {
        let dismissed = getDismissedMilestones()
        
        // 1. First Scan
        if totalCardsCount > 0 && !dismissed.contains("first_scan") {
            return Milestone(id: "first_scan", title: "First Scan Complete!", description: "You've started your journey as a Master Trainer.")
        }
        
        // 2. £100 Milestone
        if (liveTotalGbp ?? 0) >= 100 && !dismissed.contains("value_100") {
            return Milestone(id: "value_100", title: "Century Club!", description: "Your collection value has crossed £100.")
        }
        
        // 3. First Binder
        if binderCount > 0 && !dismissed.contains("first_bindr") {
            return Milestone(id: "first_bindr", title: "Organized!", description: "You've created your first Binder.")
        }
        
        return nil
    }

    private func getDismissedMilestones() -> Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: dismissedMilestonesData)) ?? []
    }

    private func dismissMilestone(_ id: String) {
        var dismissed = getDismissedMilestones()
        dismissed.insert(id)
        if let data = try? JSONEncoder().encode(dismissed) {
            dismissedMilestonesData = data
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
                        .foregroundStyle(services.theme.accentColor)
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

    private var valueAndHistoryCard: some View {
        dashboardCard {
            let _ = chartRefreshID  // force re-evaluation when recalculate completes
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Total Collection Value")
                            .font(.headline)
                            .foregroundStyle(dashboardSecondaryText)

                        if isLoadingValue && liveTotalGbp == nil {
                            ProgressView()
                                .tint(services.theme.accentColor)
                        } else if isScrubbingOrLoaded {
                            Text(formatCurrency(displayTotal))
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(dashboardPrimaryText)
                                .contentTransition(.numericText())
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
                        if let change = periodChange {
                            Text((change.amount >= 0 ? "+" : "") + formatCurrency(change.amount))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(change.amount >= 0 ? DashboardPalette.success : DashboardPalette.danger)
                                .contentTransition(.numericText())

                            Text(String(format: "%.1f%% %@", change.pct, change.label))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(dashboardSecondaryText)
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

                if !activePoints.isEmpty {
                    HStack {
                        Spacer()
                        SlidingSegmentedPicker(
                            selection: $chartRange,
                            items: ChartRange.allCases,
                            title: { $0.rawValue }
                        )
                        .frame(maxWidth: 240)
                    }

                    Chart(activePoints) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            yStart: .value("Min", chartMin),
                            yEnd: .value("Value", point.total)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [services.theme.accentColor.opacity(0.3), services.theme.accentColor.opacity(0.03)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.total)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(services.theme.accentColor)
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
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [4]))
                                .foregroundStyle(dashboardDividerColor)
                            AxisValueLabel {
                                if let d = value.as(Double.self) {
                                    Text(formatCurrencyShort(d))
                                        .font(.caption2)
                                        .foregroundStyle(dashboardSecondaryText)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: chartXAxisDates) { value in
                            AxisValueLabel {
                                if let d = value.as(Date.self) {
                                    Text(xAxisLabel(for: d))
                                        .font(.caption2)
                                        .foregroundStyle(dashboardSecondaryText)
                                }
                            }
                        }
                    }
                    .chartYScale(domain: chartMin...max(chartMax, chartMin + 1))
                    .frame(height: 220)
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
                }
            }
        }
    }

    private var collectionSummaryInsightCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Collection Summary")
                .font(.title3.weight(.semibold))
                .foregroundStyle(dashboardPrimaryText)

            HStack(spacing: 8) {
                insightMetricTile(
                    icon: "square.stack.3d.up.fill",
                    iconColor: DashboardPalette.purple,
                    value: "\(totalCardsCount)",
                    label: "Total Cards",
                    action: onOpenCollection
                )

                insightMetricTile(
                    icon: "rectangle.stack.fill",
                    iconColor: DashboardPalette.blue,
                    value: "\(uniqueCardsCount)",
                    label: "Unique Cards",
                    action: onOpenCollection
                )

                insightMetricTile(
                    icon: "shippingbox.fill",
                    iconColor: DashboardPalette.success,
                    value: "\(sealedProductsCount)",
                    label: "Sealed",
                    action: onOpenSealedProducts
                )

                insightMetricTile(
                    icon: "star.fill",
                    iconColor: DashboardPalette.gold,
                    value: "\(wishlistedCardsCount)",
                    label: "Wishlisted",
                    action: onOpenWishlist
                )
            }
        }
    }

    private func insightMetricTile(
        icon: String,
        iconColor: Color,
        value: String,
        label: String,
        action: (() -> Void)?
    ) -> some View {
        Button {
            action?()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(iconColor)
                Text(value)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(dashboardPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(dashboardSecondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 104)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(dashboardCardInsetBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(dashboardBorder.opacity(0.6), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(DashboardPressStyle())
        .disabled(action == nil)
    }


    private func trendCell(title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(dashboardSecondaryText)
            Text(formatTrendPercent(value))
                .font(.title3.weight(.bold))
                .foregroundStyle(trendColor(value))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(dashboardCardInsetBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(dashboardBorder.opacity(0.5), lineWidth: 1)
        )
    }

    private func marketTrendCard(trend: MarketTrendMetrics, updatedAt: Date?) -> some View {
        dashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Market Trend")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(dashboardPrimaryText)
                    Spacer()
                    if let updatedAt {
                        Text(updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(dashboardSecondaryText)
                    }
                }

                HStack(spacing: 10) {
                    trendCell(title: "31D", value: trend.change31Days)
                    trendCell(title: "7D", value: trend.change7Days)
                    trendCell(title: "1D", value: trend.change1Day)
                }

            }
        }
    }

    private var recentActivityCard: some View {
        dashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Recent Activity")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(dashboardPrimaryText)
                    Spacer()
                    if let onViewAllActivity {
                        Button("View All") { onViewAllActivity() }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(services.theme.accentColor)
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
    }

    private var dashboardBackground: some View {
        BindrPageBackground()
    }

    private var dashboardDataSignature: Int {
        // Keep this O(1) / O(recent-lines) — never iterate all collection items here.
        // dashboardDataRevision captures inventory reloads; recentLines covers activity changes.
        var h = Hasher()
        h.combine(activeBrand.rawValue)
        h.combine(dashboardDataRevision)
        for line in recentLines { h.combine(line.id) }
        return h.finalize()
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
                            .foregroundStyle(services.theme.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(activityBadgeBackground)
                            )
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(services.theme.accentColor.opacity(0.28), lineWidth: 1)
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
        Task { await services.sealedProducts.loadFromLocalIfAvailable() }

        if let rawID = cleaned(line.sealedProductId),
           let productID = Int(rawID),
           let imageURL = services.sealedProducts.products.first(where: { $0.id == productID })?.imageURL {
            return imageURL
        }

        if let cardID = cleaned(line.cardID),
           let productID = SealedProduct.parseCollectionProductID(cardID),
           let imageURL = services.sealedProducts.products.first(where: { $0.id == productID })?.imageURL {
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

    private func dashboardCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .glassCardStyle(cornerRadius: 16, interactive: false)
    }

    private func prepareInitialDashboardData() async {
        guard !hasPreparedInitialDashboardData, !isPreparingInitialDashboardData else { return }
        guard let svc = services.collectionValue else { return }
        isPreparingInitialDashboardData = true
        defer { isPreparingInitialDashboardData = false }

        let launchStart = ContinuousClock().now
        LaunchTraceProfiler.begin("prepareInitialDashboardData")

        onInitialLoadStatusChange?("Loading your collection...")
        LaunchTraceProfiler.begin("reloadDashboardInventory")
        await reloadDashboardInventory(deferForLaunch: false)
        LaunchTraceProfiler.end("reloadDashboardInventory")

        LaunchTraceProfiler.begin("recomputeCollectionStats")
        recomputeCollectionStats()
        LaunchTraceProfiler.end("recomputeCollectionStats")

        onInitialLoadStatusChange?("Checking saved pricing...")
        if let persisted = svc.todayPersistedSnapshot() {
            liveTotalGbp = persisted.total
            livePokemonGbp = persisted.pokemon
            liveOnePieceGbp = persisted.onePiece
            liveCardsGbp = persisted.cards
            liveSealedGbp = persisted.sealed
        } else if collectionItems.count > 0 {
            print("[Dashboard⏱] no persisted snapshot — computing live value")
            onInitialLoadStatusChange?("Calculating your collection value...")
            LaunchTraceProfiler.begin("computeLiveValue")
            await computeLiveValue()
            LaunchTraceProfiler.end("computeLiveValue")
        }

        // Value is established — unblock the launch overlay immediately.
        // loadAllFromStore, resolveDashboardMetadata, and loadMarketTrendBlob are
        // driven by the existing .task(id:) handlers above and run after the fade.
        hasPreparedInitialDashboardData = true
        LaunchTraceProfiler.end("prepareInitialDashboardData")
        print("[Dashboard⏱] prepareInitialDashboardData: \(ContinuousClock().now - launchStart)")
        fireInitialLoadCompleteIfReady()
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

        let t = ContinuousClock().now
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
        print("[Dashboard⏱] reloadDashboardInventory: \(ContinuousClock().now - t) collection=\(collectionItems.count) wishlist=\(wishlistItems.count) binders=\(binderCount)")
    }

    private func computeLiveValue() async {
        isLoadingValue = true
        defer { isLoadingValue = false }
        let _t0 = ContinuousClock().now
        await services.sealedProducts.loadFromLocalIfAvailable()
        print("[Dashboard⏱]   sealedProducts.loadFromLocal: \(ContinuousClock().now - _t0)")

        // Pre-warm the full pricing cache (one SQLite scan, decode off @MainActor).
        let _t2 = ContinuousClock().now
        await services.pricing.prefetchPokemonCardPricing(forSetCodes: [])
        print("[Dashboard⏱]   prefetchPokemonCardPricing: \(ContinuousClock().now - _t2)")

        // Build the masterCardId→pricing index for all collection cards so the pricing
        // loop below hits the O(1) fast path instead of falling back to per-card SQLite
        // fetches. indexPricingForCards is a no-op for cards already in the index.
        let _tIndex = ContinuousClock().now
        let pokemonCollectionIDs = collectionItems.compactMap { item -> String? in
            guard !item.cardID.hasPrefix("sealed:"), !item.cardID.contains("::") else { return nil }
            return item.cardID
        }
        let onePieceCollectionIDs = collectionItems.compactMap { item -> String? in
            guard item.cardID.contains("::") else { return nil }
            return item.cardID
        }
        async let pokemonCards = services.cardData.loadCards(masterCardIDs: pokemonCollectionIDs, catalogBrand: .pokemon)
        async let onePieceCards = services.cardData.loadCards(masterCardIDs: onePieceCollectionIDs, catalogBrand: .onePiece)
        let (pCards, opCards) = await (pokemonCards, onePieceCards)
        await services.pricing.indexPricingForCards(pCards + opCards)
        print("[Dashboard⏱]   indexPricingForCards: \(ContinuousClock().now - _tIndex) cards=\(pCards.count + opCards.count)")

        let _t3 = ContinuousClock().now
        var totalValue = 0.0
        var pokemonValue = 0.0
        var onePieceValue = 0.0
        var cardsValue = 0.0
        var sealedValue = 0.0
        var totalCost = 0.0
        var cacheMissIDs: [String] = []

        // Yield every 100 items so the main thread stays responsive during large collections.
        var yieldCounter = 0
        for item in collectionItems {
            yieldCounter += 1
            if yieldCounter % 100 == 0 { await Task.yield() }

            guard item.quantity > 0 else { continue }
            guard item.sealedStatus != SealedInventoryStatus.opened.rawValue else { continue }
            totalCost += (item.purchasePrice ?? 0) * Double(item.quantity)

            if sealedProductID(for: item) != nil {
                guard let pid = sealedProductID(for: item),
                      let priceUSD = services.sealedProducts.marketPriceUSD(for: pid) else { continue }
                let gbp = priceUSD * Double(item.quantity) * services.pricing.usdToGbp
                totalValue += gbp
                sealedValue += gbp
                switch TCGBrand.inferredFromMasterCardId(item.cardID) {
                case .pokemon:  pokemonValue += gbp
                case .onePiece: onePieceValue += gbp
                }
            } else if !item.cardID.hasPrefix("sealed:") {
                let gradeKey: String = {
                    guard let company = item.gradingCompany else { return "raw" }
                    switch company.uppercased() {
                    case "PSA": return "psa10"
                    case "ACE": return "ace10"
                    default: return "raw"
                    }
                }()
                if let usdPrice = services.pricing.cachedUsdPriceForCardID(
                    item.cardID, variantKey: item.variantKey, grade: gradeKey
                ) {
                    let gbp = usdPrice * Double(item.quantity) * services.pricing.usdToGbp
                    totalValue += gbp
                    cardsValue += gbp
                    switch TCGBrand.inferredFromMasterCardId(item.cardID) {
                    case .pokemon:  pokemonValue += gbp
                    case .onePiece: onePieceValue += gbp
                    }
                } else {
                    // Cache miss — collect for fallback card load (rare: externalId/tcgdex_id needed).
                    cacheMissIDs.append(item.cardID)
                }
            }
        }

        // Fallback: load full Card objects only for items that missed the ID-based cache lookup.
        if !cacheMissIDs.isEmpty {
            let pokemonMissIDs = cacheMissIDs.filter { !$0.contains("::") }
            let onePieceMissIDs = cacheMissIDs.filter { $0.contains("::") }
            async let pMiss = services.cardData.loadCards(masterCardIDs: pokemonMissIDs, catalogBrand: .pokemon)
            async let opMiss = services.cardData.loadCards(masterCardIDs: onePieceMissIDs, catalogBrand: .onePiece)
            let (pm, opm) = await (pMiss, opMiss)
            let allMissedCards = pm + opm
            // Index loaded cards so future calls (FX recompute, market reload) avoid this fallback.
            await services.pricing.indexPricingForCards(allMissedCards)
            let cardByID = Dictionary(allMissedCards.map { ($0.masterCardId, $0) }, uniquingKeysWith: { f, _ in f })
            print("[Dashboard⏱]   cache miss fallback: \(cacheMissIDs.count) cards loaded=\(pm.count + opm.count)")
            for item in collectionItems where cacheMissIDs.contains(item.cardID) {
                guard item.quantity > 0, item.sealedStatus != SealedInventoryStatus.opened.rawValue else { continue }
                guard let card = cardByID[item.cardID] else { continue }
                let gradeKey: String = {
                    guard let company = item.gradingCompany else { return "raw" }
                    switch company.uppercased() {
                    case "PSA": return "psa10"
                    case "ACE": return "ace10"
                    default: return "raw"
                    }
                }()
                let usdPrice = services.pricing.cachedUsdPriceForVariantAndGrade(
                    for: card, variantKey: item.variantKey, grade: gradeKey
                ) ?? 0
                let gbp = usdPrice * Double(item.quantity) * services.pricing.usdToGbp
                totalValue += gbp
                cardsValue += gbp
                switch TCGBrand.inferredFromMasterCardId(item.cardID) {
                case .pokemon:  pokemonValue += gbp
                case .onePiece: onePieceValue += gbp
                }
            }
        }

        print("[Dashboard⏱]   pricing loop: \(ContinuousClock().now - _t3) cards=\(collectionItems.count) misses=\(cacheMissIDs.count)")
        liveTotalGbp = totalValue > 0 ? totalValue : nil
        livePokemonGbp = pokemonValue
        liveOnePieceGbp = onePieceValue
        liveCardsGbp = cardsValue
        liveSealedGbp = sealedValue
        totalCostBasis = totalCost

        // Keep today's snapshot current throughout the day so the chart always shows live data.
        if let snap = liveSnapshot {
            let changed = services.collectionValue?.updateTodaySnapshot(snap) ?? false
            if changed { services.collectionValue?.aggregateCurrentPeriods() }
        }
    }

    private func fireInitialLoadCompleteIfReady() {
        guard !hasFiredInitialLoadComplete else { return }
        hasFiredInitialLoadComplete = true
        print("[Launch] dashboard initial load complete — firing onInitialLoadComplete")
        onInitialLoadComplete?()
        // Load chart history just past the overlay fade. loadAllFromStore reads on a background
        // ModelContext, so this only needs to clear the first interactive frame.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard let svc = services.collectionValue else { return }
            await svc.loadAllFromStore()
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
                      let product = services.sealedProducts.products.first(where: { $0.id == productID })
                else { return }
                await MainActor.run { selectedSealedProductForDetail = product }
            }
            return
        }

        guard let cardID = cleaned(line.cardID) else { return }
        Task {
            if let card = await services.cardData.loadCard(masterCardId: cardID) {
                await MainActor.run { selectedCardForDetail = card }
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

            let pokemonIDs = missingIDs.filter { !$0.contains("::") && !$0.hasPrefix("sealed:") }
            let onePieceIDs = missingIDs.filter { $0.contains("::") }

            async let pokemonCards = cardData.loadCards(masterCardIDs: Array(pokemonIDs), catalogBrand: .pokemon)
            async let onePieceCards = cardData.loadCards(masterCardIDs: Array(onePieceIDs), catalogBrand: .onePiece)
            let allCards = await pokemonCards + onePieceCards

            for card in allCards {
                let cardID = card.masterCardId
                nextNames[cardID] = card.cardName
                if nextImages[cardID] == nil {
                    nextImages[cardID] = AppConfiguration.imageURL(relativePath: card.imageLowSrc)
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
            print("[Dashboard] Failed to mark ledger line: \(error.localizedDescription)")
        }
    }

    private func rangeLabel(for date: Date) -> String {
        switch chartRange {
        case .daily:
            return date.formatted(date: .abbreviated, time: .omitted)
        case .weekly:
            let end = Calendar.current.date(byAdding: .day, value: 6, to: date) ?? date
            return "w/c \(date.formatted(.dateTime.day().month(.abbreviated))) - \(end.formatted(.dateTime.day().month(.abbreviated)))"
        case .monthly:
            return date.formatted(.dateTime.month(.wide).year())
        }
    }

    private func xAxisLabel(for date: Date) -> String {
        switch chartRange {
        case .daily:
            return date.formatted(.dateTime.day().month(.abbreviated))
        case .weekly:
            return "w/c \(date.formatted(.dateTime.day().month(.abbreviated)))"
        case .monthly:
            return date.formatted(.dateTime.month(.abbreviated).year())
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "GBP"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "£\(String(format: "%.2f", value))"
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

    private func loadMarketTrendBlob() async {
        guard let data = await CatalogStore.shared.dailyBlob(key: DailyBlobKey.marketTrend) else {
            marketTrendData = nil
            return
        }
        do {
            marketTrendData = try JSONDecoder().decode(MarketTrendDailyBlob.self, from: data)
        } catch {
            marketTrendData = nil
        }
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
        }
    }

    private func directionColor(for line: LedgerLine) -> Color {
        guard let dir = LedgerDirection(rawValue: line.direction) else { return dashboardSecondaryText }
        switch dir {
        case .bought, .packed, .tradedIn, .giftedIn, .adjustmentIn:
            return DashboardPalette.success
        case .sold, .tradedOut, .giftedOut, .adjustmentOut:
            return DashboardPalette.danger
        }
    }
}

private struct MarketTrendDailyBlob: Decodable {
    let pokemon: MarketTrendMetrics
    let onepiece: MarketTrendMetrics
    let updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case pokemon
        case onepiece
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pokemon = try container.decode(MarketTrendMetrics.self, forKey: .pokemon)
        onepiece = try container.decode(MarketTrendMetrics.self, forKey: .onepiece)

        if let rawUpdatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) {
            updatedAt = Self.iso8601WithFractional.date(from: rawUpdatedAt)
                ?? Self.iso8601Basic.date(from: rawUpdatedAt)
        } else {
            updatedAt = nil
        }
    }

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Basic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private struct MarketTrendMetrics: Decodable {
    let change1Day: Double?
    let change7Days: Double?
    let change31Days: Double?
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        change1Day = container.decodeDouble(forKeys: ["change1Day", "change_1_day", "change1d", "change_1d"])
        change7Days = container.decodeDouble(forKeys: ["change7Days", "change_7_days", "change7d", "change_7d"])
        change31Days = container.decodeDouble(forKeys: ["change31Days", "change_31_days", "change31d", "change_31d"])
    }
}

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer where K == AnyCodingKey {
    func decodeString(forKeys keys: [String]) -> String? {
        for key in keys {
            guard let codingKey = AnyCodingKey(stringValue: key) else { continue }
            do {
                if let value = try decodeIfPresent(String.self, forKey: codingKey),
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            } catch {
                continue
            }
        }
        return nil
    }

    func decodeDouble(forKeys keys: [String]) -> Double? {
        for key in keys {
            guard let codingKey = AnyCodingKey(stringValue: key) else { continue }
            do {
                if let value = try decodeIfPresent(Double.self, forKey: codingKey) {
                    return value
                }
                if let stringValue = try decodeIfPresent(String.self, forKey: codingKey),
                   let parsed = Double(stringValue) {
                    return parsed
                }
            } catch {
                continue
            }
        }
        return nil
    }

}

private struct ChartPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let total: Double
    let pokemon: Double
    let onePiece: Double
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
