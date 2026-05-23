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

    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @Environment(\.scenePhase) private var scenePhase

    // Fetch only the 100 most-recent ledger lines — the dashboard shows at most
    // 5 (``recentLines``). Loading every entry in a large collection blocked the
    // main thread on cold launch for several seconds; a 100-row cap makes the
    // query near-instant while still covering any brand-filtering scenario.
    //
    // ``fetchLimit`` is a stored property on FetchDescriptor (not an initializer
    // parameter), so we build the descriptor in a static lazy property and
    // reference it here — that's the only way to use it with @Query.
    @Query(DashboardView.ledgerDescriptor) private var allLedgerLines: [LedgerLine]

    private static let ledgerDescriptor: FetchDescriptor<LedgerLine> = {
        var d = FetchDescriptor<LedgerLine>(
            sortBy: [SortDescriptor(\LedgerLine.occurredAt, order: .reverse)]
        )
        d.fetchLimit = 100
        return d
    }()
    @Query private var collectionItems: [CollectionItem]
    @Query(sort: \WishlistItem.dateAdded, order: .reverse) private var wishlistItems: [WishlistItem]
    @Query private var binders: [Binder]
    
    @AppStorage("dismissedMilestones") private var dismissedMilestonesData: Data = Data()

    @State private var liveTotalGbp: Double? = nil
    @State private var livePokemonGbp: Double = 0
    @State private var liveOnePieceGbp: Double = 0
    @State private var totalCostBasis: Double = 0
    @State private var isLoadingValue = false
    @State private var selectedPoint: ChartPoint? = nil
    @State private var chartRange: ChartRange = .daily
    @State private var chartRefreshID: Int = 0
    @State private var selectedBrand: TCGBrand? = nil
    @State private var cardNamesByID: [String: String] = [:]
    @State private var setNamesByCardID: [String: String] = [:]
    @State private var cardImageURLsByID: [String: URL] = [:]
    @State private var marketTrendData: MarketTrendDailyBlob? = nil
    @State private var cardTypeBreakdown: [DashboardBreakdownEntry] = []
    @State private var energyTypeBreakdown: [DashboardBreakdownEntry] = []
    @State private var formatBreakdown: [DashboardBreakdownEntry] = []
    @State private var mostExpensiveHolding: DashboardTopHolding? = nil
    @State private var priceBandBreakdown: [DashboardBreakdownEntry] = []
    @State private var setCompletionEntries: [DashboardSetCompletionEntry] = []
    @State private var editingRecentLedgerLine: LedgerLine?
    @State private var marketBiggestGainer7Days: MarketTrendMover? = nil
    @State private var marketBiggestDecliner7Days: MarketTrendMover? = nil
    @State private var selectedCardForDetail: Card? = nil

    private var liveSnapshot: BrandSnapshot? {
        guard let t = liveTotalGbp else { return nil }
        return BrandSnapshot(total: t, pokemon: livePokemonGbp, onePiece: liveOnePieceGbp)
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

    private var totalCardsCount: Int {
        visibleCollectionItems.reduce(0) { $0 + max($1.quantity, 0) }
    }

    private var uniqueCardsCount: Int {
        Set(visibleCardCollectionItems.map(\.cardID)).count
    }

    private var sealedProductsCount: Int {
        visibleCollectionItems.reduce(0) { total, item in
            guard sealedProductID(for: item) != nil else { return total }
            guard item.sealedStatus != SealedInventoryStatus.opened.rawValue else { return total }
            return total + max(item.quantity, 0)
        }
    }

    private var wishlistedCardsCount: Int {
        Set(visibleWishlistItems.map(\.cardID)).count
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
        "\(services.collectionValue == nil ? "nil" : "ready"):\(collectionItems.count)"
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
                    onePiece: snapshot.onePieceGbp
                )
            }
        }
        if let live = liveTotalGbp {
            let today = cal.startOfDay(for: Date())
            // Always use today's live value so the chart matches the summary value card.
            pointsByDay[today] = ChartPoint(date: today, total: live, pokemon: livePokemonGbp, onePiece: liveOnePieceGbp)
        }
        return pointsByDay.keys.sorted().compactMap { pointsByDay[$0] }
    }

    private var weeklyPoints: [ChartPoint] {
        guard let svc = services.collectionValue else { return [] }
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .year, value: -1, to: cal.startOfDay(for: Date()))!
        return svc.weeklyAverages
            .filter { $0.weekStart >= cutoff }
            .map { ChartPoint(date: $0.weekStart, total: $0.totalGbp, pokemon: $0.pokemonGbp, onePiece: $0.onePieceGbp) }
    }

    private var monthlyPoints: [ChartPoint] {
        guard let svc = services.collectionValue else { return [] }
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .year, value: -5, to: cal.startOfDay(for: Date()))!
        return svc.monthlyAverages
            .filter { $0.monthStart >= cutoff }
            .map { ChartPoint(date: $0.monthStart, total: $0.totalGbp, pokemon: $0.pokemonGbp, onePiece: $0.onePieceGbp) }
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
            return ChartPoint(date: point.date, total: total, pokemon: point.pokemon, onePiece: point.onePiece)
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
        .task(id: collectionItems.count) {
            await computeLiveValue()
        }
        .task(id: backfillTrigger) {
            guard services.collectionValue != nil else { return }
            if liveSnapshot == nil {
                await computeLiveValue()
            }
            await services.collectionValue?.runBackfillIfNeeded(
                collectionItems: collectionItems,
                preferredTodaySnapshot: liveSnapshot
            )
        }
        .task(id: dashboardDataSignature) {
            await resolveDashboardMetadata()
            await resolveInsightsData()
        }
        .task {
            await loadMarketTrendBlob()
        }
        .task(id: services.dashboardMarketReloadToken) {
            guard services.dashboardMarketReloadToken > 0 else { return }
            await computeLiveValue()
            chartRefreshID += 1
            await loadMarketTrendBlob()
            await resolveInsightsData()
        }
        .onChange(of: services.isCatalogDownloadInProgress) { _, inProgress in
            guard !inProgress else { return }
            Task {
                await computeLiveValue()
                if let snap = liveSnapshot {
                    await services.collectionValue?.forceRecalculate(
                        liveSnapshot: snap,
                        collectionItems: collectionItems
                    )
                }
                await loadMarketTrendBlob()
                await resolveInsightsData()
            }
        }
        .onAppear {
            selectedBrand = activeBrand
        }
        .onChange(of: services.brandSettings.selectedCatalogBrand) { _, brand in
            selectedBrand = brand
            selectedPoint = nil
            Task {
                await resolveMarketMoversFromPriceTrendsBlob()
            }
        }
        .onChange(of: chartRange) { _, _ in
            selectedPoint = nil
            selectedBrand = activeBrand
        }
        .onChange(of: services.pricing.usdToGbp) { _, _ in
            Task {
                await computeLiveValue()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, let snapshot = liveSnapshot {
                services.collectionValue?.persistLastKnownValue(snapshot)
            }
        }
        .sheet(item: $selectedCardForDetail) { card in
            CardDetailSheet(cards: [card], startIndex: 0)
                .environment(services)
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
        if !binders.isEmpty && !dismissed.contains("first_bindr") {
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

    private var mostExpensiveCardInsightCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Most Expensive Card")
                .font(.title3.weight(.bold))
                .foregroundStyle(dashboardPrimaryText)

            if let topCard = mostExpensiveHolding {
                HStack(spacing: 16) {
                    // Premium Card Artwork Frame
                    ZStack {
                        if let imageURL = topCard.imageURL {
                            CachedAsyncImage(url: imageURL, targetSize: CGSize(width: 120, height: 168)) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } placeholder: {
                                Color.white.opacity(0.1)
                            }
                        } else {
                            Color.white.opacity(0.1)
                                .overlay {
                                    Image(systemName: "photo")
                                        .font(.headline)
                                        .foregroundStyle(dashboardSecondaryText)
                                }
                        }
                    }
                    .frame(width: 58, height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: services.theme.accentColor.opacity(0.25), radius: 10, x: 0, y: 4)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(services.theme.accentColor.opacity(0.4), lineWidth: 1)
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(topCard.name)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(dashboardPrimaryText)
                            .lineLimit(1)
                        
                        Text(topCard.setName ?? "Set unknown")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(dashboardSecondaryText)
                            .lineLimit(1)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "tag.fill")
                                .font(.caption2)
                            Text("Owned: \(topCard.quantity)")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(services.theme.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(services.theme.accentColor.opacity(0.1), in: Capsule())
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(formatCurrency(topCard.unitValue))
                            .font(.title2.weight(.black))
                            .foregroundStyle(dashboardPrimaryText)
                            .contentTransition(.numericText())
                        
                        Text("per card")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(dashboardSecondaryText)
                            .textCase(.uppercase)

                        if topCard.quantity > 1 {
                            Text(formatCurrency(topCard.totalValue))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DashboardPalette.success)
                        }
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("No priced cards yet.")
                    .font(.subheadline)
                    .foregroundStyle(dashboardSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
        }
    }

    private var priceBandInsightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Distribution by Price")
                .font(.title3.weight(.semibold))
                .foregroundStyle(dashboardPrimaryText)

            if priceBandBreakdown.allSatisfy({ $0.value == 0 }) {
                Text("No priced cards yet.")
                    .font(.subheadline)
                    .foregroundStyle(dashboardSecondaryText)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(priceBandBreakdown.enumerated()), id: \.element.id) { index, entry in
                        insightBarRow(
                            entry: entry,
                            maxValue: max(priceBandBreakdown.map(\.value).max() ?? 1, 1),
                            tint: dashboardBreakdownColor(at: index)
                        )
                    }
                }
            }
        }
    }

    private var setCompletionInsightCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sets Closest to Completion")
                .font(.title3.weight(.bold))
                .foregroundStyle(dashboardPrimaryText)

            if setCompletionEntries.isEmpty {
                Text("Add cards from sets to track completion progress.")
                    .font(.subheadline)
                    .foregroundStyle(dashboardSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 14) {
                    ForEach(Array(setCompletionEntries.prefix(3))) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(entry.setName)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(dashboardPrimaryText)
                                    .lineLimit(1)

                                Spacer(minLength: 8)

                                Text("\(entry.percentString)%")
                                    .font(.subheadline.weight(.heavy))
                                    .foregroundStyle(services.theme.accentColor)
                                    .italic()
                            }

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    // Exp Bar Track
                                    Capsule()
                                        .fill(dashboardCardInsetBackground)
                                        .frame(height: 10)
                                    
                                    // Exp Bar Fill
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [services.theme.accentColor, services.theme.accentColor.opacity(0.7)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(0, geo.size.width * CGFloat(entry.progress)), height: 10)
                                        .shadow(color: services.theme.accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
                                        
                                    // Glossy Overlay
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [.white.opacity(0.2), .clear],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(width: max(0, geo.size.width * CGFloat(entry.progress)), height: 4)
                                        .padding(.top, 1)
                                        .padding(.horizontal, 2)
                                }
                            }
                            .frame(height: 10)

                            HStack {
                                Label("\(entry.ownedUnique)/\(entry.totalCards)", systemImage: "square.grid.3x2.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(dashboardSecondaryText)
                                
                                Spacer()
                                
                                Text("Remaining: \(entry.totalCards - entry.ownedUnique)")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(dashboardSecondaryText)
                            }
                        }
                    }
                }
            }
        }
    }

    private func distributionInsightCard(
        title: String,
        entries: [DashboardBreakdownEntry],
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(dashboardPrimaryText)

            if entries.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(dashboardSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 12) {
                    let maxValue = max(entries.map(\.value).max() ?? 1, 1)
                    ForEach(Array(entries.prefix(4).enumerated()), id: \.element.id) { index, entry in
                        insightBarRow(
                            entry: entry, 
                            maxValue: maxValue, 
                            tint: dashboardBreakdownColor(at: index, label: entry.label)
                        )
                    }
                }
            }
        }
    }

    private func insightBarRow(entry: DashboardBreakdownEntry, maxValue: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(dashboardPrimaryText)
                
                Spacer()
                
                Text("\(entry.value)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(dashboardSecondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(dashboardCardInsetBackground, in: Capsule())
                    .overlay(Capsule().stroke(dashboardBorder.opacity(0.5), lineWidth: 0.5))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(dashboardCardInsetBackground)
                        .frame(height: 8)
                    
                    // Bar
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint, tint.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geo.size.width * CGFloat(entry.value) / CGFloat(maxValue)), height: 8)
                        .shadow(color: tint.opacity(0.3), radius: 4, x: 0, y: 2)
                }
            }
            .frame(height: 8)
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

                Text("Movers")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(dashboardSecondaryText)

                HStack(spacing: 10) {
                    moverCell(
                        title: "Biggest 7D Gain",
                        mover: biggestGainerMover(from: trend),
                        fallbackColor: DashboardPalette.success
                    )
                    moverCell(
                        title: "Biggest 7D Drop",
                        mover: biggestDeclinerMover(from: trend),
                        fallbackColor: DashboardPalette.danger
                    )
                }
            }
        }
    }

    private func biggestGainerMover(from trend: MarketTrendMetrics) -> MarketTrendMover? {
        marketBiggestGainer7Days
    }

    private func biggestDeclinerMover(from trend: MarketTrendMetrics) -> MarketTrendMover? {
        marketBiggestDecliner7Days
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
                                guard let cardID = cleaned(line.cardID) else { return }
                                Task {
                                    if let card = await services.cardData.loadCard(masterCardId: cardID) {
                                        await MainActor.run { selectedCardForDetail = card }
                                    }
                                }
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

    private func energyColor(for type: String) -> Color {
        let normalized = type.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized {
        case "grass": return Color(hex: "7AC74C")
        case "fire": return Color(hex: "EE8130")
        case "water": return Color(hex: "6390F0")
        case "lightning", "electric": return Color(hex: "F7D02C")
        case "psychic": return Color(hex: "F95587")
        case "fighting": return Color(hex: "C22E28")
        case "darkness", "dark": return Color(hex: "705746")
        case "metal", "steel": return Color(hex: "B7B7CE")
        case "fairy": return Color(hex: "D685AD")
        case "dragon": return Color(hex: "6F35FC")
        case "colorless", "normal": return Color(hex: "A8A77A")
        default: return services.theme.accentColor
        }
    }

    private func dashboardBreakdownColor(at index: Int, label: String = "") -> Color {
        if !label.isEmpty {
            let col = energyColor(for: label)
            if col != services.theme.accentColor {
                return col
            }
        }
        
        let palette = [
            DashboardPalette.purple,
            DashboardPalette.blue,
            DashboardPalette.success,
            DashboardPalette.gold,
            DashboardPalette.orange,
            DashboardPalette.danger
        ]
        return palette[index % palette.count]
    }

    private var dashboardDataSignature: Int {
        var h = Hasher()
        h.combine(activeBrand.rawValue)
        for item in visibleCollectionItems {
            h.combine(item.cardID)
            h.combine(item.quantity)
            h.combine(item.variantKey)
            h.combine(item.itemKind)
            h.combine(item.gradingCompany)
            h.combine(item.sealedStatus)
        }
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

    private func computeLiveValue() async {
        isLoadingValue = true
        defer { isLoadingValue = false }
        await services.sealedProducts.loadFromLocalIfAvailable()

        var totalValue = 0.0
        var pokemonValue = 0.0
        var onePieceValue = 0.0
        var totalCost = 0.0

        for item in collectionItems {
            let quantity = max(item.quantity, 0)
            guard quantity > 0 else { continue }
            guard item.sealedStatus != SealedInventoryStatus.opened.rawValue else { continue }

            totalCost += (item.purchasePrice ?? 0) * Double(quantity)

            if let sealedProductID = sealedProductID(for: item),
               let sealedPriceUSD = services.sealedProducts.marketPriceUSD(for: sealedProductID) {
                let gbp = sealedPriceUSD * Double(quantity) * services.pricing.usdToGbp
                totalValue += gbp

                switch TCGBrand.inferredFromMasterCardId(item.cardID) {
                case .pokemon: pokemonValue += gbp
                case .onePiece: onePieceValue += gbp
                }
                continue
            }

            guard let card = await services.cardData.loadCard(masterCardId: item.cardID) else { continue }
            let gradeKey: String = {
                guard let company = item.gradingCompany else { return "raw" }
                switch company.uppercased() {
                case "PSA": return "psa10"
                case "ACE": return "ace10"
                default: return "raw"
                }
            }()
            let usdPrice = await services.pricing.usdPriceForVariantAndGrade(for: card, variantKey: item.variantKey, grade: gradeKey) ?? 0
            let gbp = usdPrice * Double(quantity) * services.pricing.usdToGbp
            totalValue += gbp

            switch TCGBrand.inferredFromMasterCardId(item.cardID) {
            case .pokemon: pokemonValue += gbp
            case .onePiece: onePieceValue += gbp
            }
        }

        liveTotalGbp = totalValue > 0 ? totalValue : nil
        livePokemonGbp = pokemonValue
        liveOnePieceGbp = onePieceValue
        totalCostBasis = totalCost

        // Keep today's snapshot current throughout the day so the chart always shows live data
        if let snap = liveSnapshot {
            let changed = services.collectionValue?.updateTodaySnapshot(snap) ?? false
            if changed { services.collectionValue?.aggregateCurrentPeriods() }
        }
    }

    private func sealedProductID(for item: CollectionItem) -> Int? {
        if let rawID = item.sealedProductId,
           let productID = Int(rawID) {
            return productID
        }
        return SealedProduct.parseCollectionProductID(item.cardID)
    }

    private func resolveDashboardMetadata() async {
        var nextNames = cardNamesByID
        var nextSets = setNamesByCardID
        var nextImages = cardImageURLsByID
        var setsByBrandAndCode: [String: String] = [:]

        for brand in services.brandSettings.enabledBrands {
            guard let sets = try? await CatalogStore.shared.fetchAllSets(for: brand) else { continue }
            for set in sets {
                setsByBrandAndCode["\(brand.rawValue)|\(set.setCode)"] = set.name
            }
        }

        let cardIDs = Set(visibleCollectionItems.map(\.cardID) + recentLines.compactMap { cleaned($0.cardID) })

        for cardID in cardIDs {
            guard nextNames[cardID] == nil || nextSets[cardID] == nil || nextImages[cardID] == nil else { continue }
            guard let card = await services.cardData.loadCard(masterCardId: cardID) else { continue }
            nextNames[cardID] = card.cardName
            if nextImages[cardID] == nil {
                nextImages[cardID] = AppConfiguration.imageURL(relativePath: card.imageLowSrc)
            }

            let brand = TCGBrand.inferredFromMasterCardId(cardID)
            if let setName = setsByBrandAndCode["\(brand.rawValue)|\(card.setCode)"] {
                nextSets[cardID] = setName
            }
        }

        cardNamesByID = nextNames
        setNamesByCardID = nextSets
        cardImageURLsByID = nextImages
    }

    private func resolveInsightsData() async {
        await services.sealedProducts.loadFromLocalIfAvailable()

        var nextCardType: [String: Int] = [:]
        var nextEnergyType: [String: Int] = [:]
        var nextFormat: [String: Int] = [:]
        var nextPriceBand: [String: Int] = ["£": 0, "££": 0, "£££": 0]
        var nextMostExpensive: DashboardTopHolding? = nil
        var ownedCardIDsBySetCode: [String: Set<String>] = [:]
        var cardCache: [String: Card] = [:]
        var nextTopGainer: MarketTrendMover? = nil
        var nextTopDecliner: MarketTrendMover? = nil

        let setsForBrand = (try? await CatalogStore.shared.fetchAllSets(for: activeBrand)) ?? []
        var setTotalsByCode: [String: (name: String, total: Int)] = [:]
        for set in setsForBrand {
            let total = set.cardCountTotal ?? set.cardCountOfficial ?? 0
            guard total > 0 else { continue }
            setTotalsByCode[set.setCode] = (set.name, total)
        }

        for item in visibleCollectionItems {
            let quantity = max(item.quantity, 0)
            guard quantity > 0 else { continue }
            guard item.sealedStatus != SealedInventoryStatus.opened.rawValue else { continue }

            nextFormat[formatLabel(for: item), default: 0] += quantity

            // Distribution cards requested by the dashboard are specifically card-focused.
            if sealedProductID(for: item) != nil { continue }
            let card: Card
            if let cached = cardCache[item.cardID] {
                card = cached
            } else {
                guard let loaded = await services.cardData.loadCard(masterCardId: item.cardID) else { continue }
                card = loaded
                cardCache[item.cardID] = loaded
            }

            nextCardType[cardTypeLabel(for: card), default: 0] += quantity

            for energy in energyLabels(for: card) {
                nextEnergyType[energy, default: 0] += quantity
            }

            ownedCardIDsBySetCode[card.setCode, default: []].insert(card.masterCardId)

            let unitValue = await unitPriceGBP(for: item, card: card)
            nextPriceBand[priceBandLabel(for: unitValue), default: 0] += quantity

            if let change7d = await sevenDayChangePercent(for: item, card: card) {
                let mover = MarketTrendMover(
                    cardID: card.masterCardId,
                    displayName: card.cardName,
                    percentChange: change7d,
                    imageURL: AppConfiguration.imageURL(relativePath: card.imageLowSrc)
                )
                if nextTopGainer == nil || change7d > (nextTopGainer?.percentChange ?? -.infinity) {
                    nextTopGainer = mover
                }
                if nextTopDecliner == nil || change7d < (nextTopDecliner?.percentChange ?? .infinity) {
                    nextTopDecliner = mover
                }
            }

            guard unitValue > 0 else { continue }
            let totalValue = unitValue * Double(quantity)
            if let currentTop = nextMostExpensive, currentTop.unitValue >= unitValue {
                continue
            }

            nextMostExpensive = DashboardTopHolding(
                cardID: card.masterCardId,
                name: card.cardName,
                setName: setNamesByCardID[card.masterCardId],
                imageURL: AppConfiguration.imageURL(relativePath: card.imageLowSrc),
                unitValue: unitValue,
                totalValue: totalValue,
                quantity: quantity
            )
        }

        cardTypeBreakdown = sortedBreakdown(from: nextCardType)
        energyTypeBreakdown = sortedBreakdown(from: nextEnergyType)
        formatBreakdown = sortedBreakdown(from: nextFormat)
        priceBandBreakdown = [
            DashboardBreakdownEntry(label: "£ (< £1)", value: nextPriceBand["£"] ?? 0),
            DashboardBreakdownEntry(label: "££ (£1 - £25)", value: nextPriceBand["££"] ?? 0),
            DashboardBreakdownEntry(label: "£££ (£25+)", value: nextPriceBand["£££"] ?? 0)
        ]
        setCompletionEntries = ownedCardIDsBySetCode.compactMap { setCode, ownedIDs in
            guard let setMeta = setTotalsByCode[setCode] else { return nil }
            let ownedUnique = ownedIDs.count
            guard ownedUnique > 0 else { return nil }
            let progress = min(Double(ownedUnique) / Double(setMeta.total), 1.0)
            return DashboardSetCompletionEntry(
                setCode: setCode,
                setName: setMeta.name,
                ownedUnique: ownedUnique,
                totalCards: setMeta.total,
                progress: progress
            )
        }
        .sorted { lhs, rhs in
            if lhs.progress == rhs.progress {
                if lhs.ownedUnique == rhs.ownedUnique {
                    return lhs.setName.localizedCaseInsensitiveCompare(rhs.setName) == .orderedAscending
                }
                return lhs.ownedUnique > rhs.ownedUnique
            }
            return lhs.progress > rhs.progress
        }
        .prefix(4)
        .map { $0 }
        mostExpensiveHolding = nextMostExpensive
    }

    private func sevenDayChangePercent(for item: CollectionItem, card: Card) async -> Double? {
        guard let trends = await services.pricing.priceTrends(for: card) else { return nil }

        let gradeKey: String = {
            guard let company = item.gradingCompany else { return "raw" }
            switch company.uppercased() {
            case "PSA": return "psa10"
            case "ACE": return "ace10"
            default: return "raw"
            }
        }()

        let preferredVariant = cleaned(item.variantKey) ?? trends.variant
        let direct = trends.changes(for: preferredVariant, grade: gradeKey).change7d
        if let direct { return direct }

        if let variantMap = trends.allVariants[preferredVariant] {
            if let anyGrade = variantMap.values.compactMap(\.change7d).first {
                return anyGrade
            }
        }

        return trends.change7d
    }

    private func sortedBreakdown(from source: [String: Int], limit: Int = 5) -> [DashboardBreakdownEntry] {
        source
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(limit)
            .map { DashboardBreakdownEntry(label: $0.key, value: $0.value) }
    }

    private func formatLabel(for item: CollectionItem) -> String {
        switch ProductKind(rawValue: item.itemKind) {
        case .sealedProduct, .boosterPack, .etb:
            return "Sealed"
        case .gradedItem:
            return "Graded"
        case .singleCard:
            return "Raw"
        case .other, .none:
            return "Other"
        }
    }

    private func cardTypeLabel(for card: Card) -> String {
        if let category = cleaned(card.category) {
            let lowercased = category.lowercased()
            if lowercased.contains("pokemon") { return "Pokemon" }
            if lowercased.contains("trainer") { return "Trainer" }
            if lowercased.contains("energy") { return "Energy" }
            return category.capitalized
        }
        if cleaned(card.trainerType) != nil {
            return "Trainer"
        }
        if cleaned(card.energyType) != nil {
            return "Energy"
        }
        return "Other"
    }

    private func energyLabels(for card: Card) -> [String] {
        if let types = card.elementTypes?
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty }) {
            let unique = Array(Set(types))
            if !unique.isEmpty {
                return unique.sorted()
            }
        }
        if let fallback = cleaned(card.energyType) {
            return [fallback.capitalized]
        }
        return []
    }

    private func unitPriceGBP(for item: CollectionItem, card: Card) async -> Double {
        let gradeKey: String = {
            guard let company = item.gradingCompany else { return "raw" }
            switch company.uppercased() {
            case "PSA": return "psa10"
            case "ACE": return "ace10"
            default: return "raw"
            }
        }()
        let usdPrice = await services.pricing.usdPriceForVariantAndGrade(
            for: card,
            variantKey: item.variantKey,
            grade: gradeKey
        ) ?? 0
        return usdPrice * services.pricing.usdToGbp
    }

    private func priceBandLabel(for value: Double) -> String {
        if value < 1 { return "£" }
        if value <= 25 { return "££" }
        return "£££"
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
            await resolveMarketMoversFromPriceTrendsBlob()
            return
        }
        do {
            marketTrendData = try JSONDecoder().decode(MarketTrendDailyBlob.self, from: data)
        } catch {
            marketTrendData = nil
        }
        await resolveMarketMoversFromPriceTrendsBlob()
    }

    private func resolveMarketMoversFromPriceTrendsBlob() async {
        do {
            try await CatalogStore.shared.open()
        } catch {
            marketBiggestGainer7Days = nil
            marketBiggestDecliner7Days = nil
            return
        }

        let sets = (try? await CatalogStore.shared.fetchAllSets(for: activeBrand)) ?? []
        guard !sets.isEmpty else {
            marketBiggestGainer7Days = nil
            marketBiggestDecliner7Days = nil
            return
        }

        var candidates: [TrendMoverCandidate] = []

        for set in sets {
            guard let trendsBlob = await loadPriceTrendsBlobForSet(setCode: set.setCode) else { continue }
            collectSetTrendCandidates(from: trendsBlob, setCode: set.setCode, into: &candidates)
        }

        // If per-set rows are unavailable, fall back to the aggregate daily blob parser.
        if candidates.isEmpty,
           let aggregate = await CatalogStore.shared.dailyBlob(key: DailyBlobKey.priceTrends),
           let raw = try? JSONSerialization.jsonObject(with: aggregate) {
            collectTrendMoverCandidates(from: raw, inheritedCardID: nil, into: &candidates)
        }

        let scoped = candidates.filter(matchesActiveBrand)
        let finalCandidates = scoped.isEmpty ? candidates : scoped

        let topGain = finalCandidates.max(by: { $0.change7d < $1.change7d })
        let topDrop = finalCandidates.min(by: { $0.change7d < $1.change7d })

        if let topGain {
            marketBiggestGainer7Days = await buildMover(from: topGain)
        } else {
            marketBiggestGainer7Days = nil
        }

        if let topDrop {
            marketBiggestDecliner7Days = await buildMover(from: topDrop)
        } else {
            marketBiggestDecliner7Days = nil
        }
    }

    private func collectSetTrendCandidates(from trendsBlob: Data, setCode: String, into candidates: inout [TrendMoverCandidate]) {
        guard let root = try? JSONSerialization.jsonObject(with: trendsBlob) as? [String: Any] else { return }
        for (cardID, rawEntry) in root {
            guard let entry = rawEntry as? [String: Any] else { continue }
            let parsed = CardPriceTrends.parse(from: entry)
            let change7d = extractRawSevenDayChange(parsed: parsed, entry: entry)
            guard let change7d else { continue }
            candidates.append(
                TrendMoverCandidate(
                    cardID: cardID,
                    displayName: (entry["cardName"] as? String)
                        ?? (entry["card_name"] as? String)
                        ?? (entry["name"] as? String)
                        ?? (entry["title"] as? String),
                    imageURL: nil,
                    change7d: change7d,
                    brandHint: nil,
                    setCode: setCode
                )
            )
        }
    }

    private func loadPriceTrendsBlobForSet(setCode: String) async -> Data? {
        if let exact = await CatalogStore.shared.fetchPriceTrendsData(setCode: setCode, brand: activeBrand) {
            return exact
        }
        let lowercased = setCode.lowercased()
        if lowercased != setCode {
            if let lower = await CatalogStore.shared.fetchPriceTrendsData(setCode: lowercased, brand: activeBrand) {
                return lower
            }
        }

        // One Piece network fallback (per-set files still live on R2).
        // Pokemon trends come from daily sync into SQLite only — no network fallback.
        if activeBrand == .onePiece {
            for stem in onePieceTrendStemVariants(for: setCode) {
                let url = AppConfiguration.r2OnePiecePriceTrendsURL(setCodeStem: stem)
                if let data = await fetchHTTPBodyIfOK(from: url) {
                    return data
                }
            }
        }
        return nil
    }

    private func onePieceTrendStemVariants(for setCode: String) -> [String] {
        let s = setCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return [] }
        var stems: [String] = []
        func add(_ candidate: String) {
            let value = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty, !stems.contains(value) {
                stems.append(value)
            }
        }
        add(s)
        add(s.uppercased())
        add(s.lowercased())
        return stems
    }

    private func fetchHTTPBodyIfOK(from url: URL) async -> Data? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  !data.isEmpty else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private func extractSetEntrySevenDayChange(from entry: [String: Any]) -> Double? {
        if let weekly = entry["weekly"] as? [String: Any] {
            // Only accept explicit percent fields. Some feeds include `weekly.value`
            // as a raw price/value metric, which can inflate dashboard movers.
            for key in ["changePct", "change_pct", "pct", "percent", "percentChange", "percent_change"] {
                if let raw = weekly[key], let number = parseAnyNumber(raw) {
                    return number
                }
            }
        }
        for key in ["change7d", "change_7d", "change7Days", "change_7_days", "percentChange", "percent_change"] {
            if let raw = entry[key], let number = parseAnyNumber(raw) {
                return number
            }
        }
        return nil
    }

    private func extractRawSevenDayChange(parsed: CardPriceTrends?, entry: [String: Any]) -> Double? {
        if let parsed {
            // Prefer RAW for the trend row's primary variant so dashboard movers
            // match the same per-card variant context the detail chart starts from.
            let preferredVariant = parsed.variant.trimmingCharacters(in: .whitespacesAndNewlines)
            if !preferredVariant.isEmpty,
               let preferredRaw = parsed.allVariants[preferredVariant]?["raw"]?.change7d {
                return preferredRaw
            }

            // If the top-level trend row itself is RAW, use it.
            if parsed.grade.lowercased() == "raw", let topLevelRaw = parsed.change7d {
                return topLevelRaw
            }

            // Fallback: if there is exactly one RAW value across variants, use it.
            let rawCandidates = parsed.allVariants.values.compactMap { $0["raw"]?.change7d }
            if rawCandidates.count == 1, let loneRaw = rawCandidates.first {
                return loneRaw
            }
        }

        // Dynamic JSON fallback when strong parsing misses: only accept entries marked RAW.
        if let grade = (entry["grade"] as? String)?.lowercased(), grade == "raw" {
            return extractSetEntrySevenDayChange(from: entry)
        }

        return nil
    }

    private func collectTrendMoverCandidates(
        from value: Any,
        inheritedCardID: String?,
        into candidates: inout [TrendMoverCandidate]
    ) {
        if let dict = value as? [String: Any] {
            let cardID = (dict["masterCardId"] as? String)
                ?? (dict["master_card_id"] as? String)
                ?? (dict["cardId"] as? String)
                ?? (dict["card_id"] as? String)
                ?? inheritedCardID
            let displayName = (dict["cardName"] as? String)
                ?? (dict["card_name"] as? String)
                ?? (dict["name"] as? String)
                ?? (dict["title"] as? String)
            let imageURL = parseImageURL(from: dict)
            let brandHint = (dict["brand"] as? String) ?? (dict["tcg"] as? String) ?? (dict["game"] as? String)
            let parsed = CardPriceTrends.parse(from: dict)
            if let change7d = extractRawSevenDayChange(parsed: parsed, entry: dict) {
                candidates.append(
                    TrendMoverCandidate(
                        cardID: cardID,
                        displayName: displayName,
                        imageURL: imageURL,
                        change7d: change7d,
                        brandHint: brandHint,
                        setCode: nil
                    )
                )
            }
            for (key, child) in dict {
                let nextCardID = extractCardID(from: key) ?? cardID
                collectTrendMoverCandidates(from: child, inheritedCardID: nextCardID, into: &candidates)
            }
            return
        }

        if let array = value as? [Any] {
            for child in array {
                collectTrendMoverCandidates(from: child, inheritedCardID: inheritedCardID, into: &candidates)
            }
        }
    }

    private func extractCardID(from key: String) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.lowercased()
        if normalized == "weekly" || normalized == "daily" || normalized == "monthly" || normalized == "allvariants" {
            return nil
        }
        if normalized.contains("-"), normalized.rangeOfCharacter(from: .decimalDigits) != nil {
            return trimmed
        }
        return nil
    }

    private func parseImageURL(from dict: [String: Any]) -> URL? {
        for key in ["imageURL", "imageUrl", "image_url", "image", "thumbnail", "thumb"] {
            guard let raw = dict[key] as? String else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let absolute = URL(string: trimmed), absolute.scheme != nil {
                return absolute
            }
            return AppConfiguration.imageURL(relativePath: trimmed)
        }
        return nil
    }

    private func matchesActiveBrand(_ candidate: TrendMoverCandidate) -> Bool {
        if let cardID = candidate.cardID {
            return TCGBrand.inferredFromMasterCardId(cardID) == activeBrand
        }
        if let hint = candidate.brandHint?.lowercased() {
            switch activeBrand {
            case .pokemon:
                return hint.contains("pokemon")
            case .onePiece:
                return hint.contains("onepiece") || hint.contains("one_piece") || hint.contains("one piece")
            }
        }
        return false
    }

    private func parseAnyNumber(_ raw: Any) -> Double? {
        switch raw {
        case let number as Double: return number
        case let number as Float: return Double(number)
        case let number as Int: return Double(number)
        case let number as NSNumber: return number.doubleValue
        case let string as String: return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }

    private func buildMover(from candidate: TrendMoverCandidate) async -> MarketTrendMover {
        var displayName: String? = candidate.displayName
        var imageURL: URL? = candidate.imageURL
        var resolvedCardID: String? = nil

        if let cardID = candidate.cardID,
           let card = await services.cardData.loadCard(masterCardId: cardID) {
            resolvedCardID = card.masterCardId
            if displayName == nil {
                displayName = card.cardName
            }
            if imageURL == nil {
                imageURL = AppConfiguration.imageURL(relativePath: card.imageLowSrc)
            }
        } else if let candidateID = candidate.cardID {
            // Per-set trend files can use alternate card keys; do a best-effort match.
            let normalizedCandidate = normalizeTrendKey(candidateID)
            let setScopedCards: [Card]
            if let setCode = candidate.setCode {
                setScopedCards = await services.cardData.loadCards(forSetCode: setCode, catalogBrand: activeBrand)
            } else {
                setScopedCards = []
            }

            if let matched = setScopedCards.first(where: { card in
                if card.masterCardId.caseInsensitiveCompare(candidateID) == .orderedSame {
                    return true
                }
                if let externalId = cleaned(card.externalId),
                   externalId.caseInsensitiveCompare(candidateID) == .orderedSame {
                    return true
                }
                if let tcgplayerProductId = cleaned(card.tcgplayerProductId),
                   tcgplayerProductId == candidateID {
                    return true
                }
                let normalizedMaster = normalizeTrendKey(card.masterCardId)
                let normalizedExternal = normalizeTrendKey(cleaned(card.externalId) ?? "")
                return normalizedMaster == normalizedCandidate
                    || (!normalizedExternal.isEmpty && normalizedExternal == normalizedCandidate)
            }) {
                resolvedCardID = matched.masterCardId
                if displayName == nil { displayName = matched.cardName }
                if imageURL == nil {
                    imageURL = AppConfiguration.imageURL(relativePath: matched.imageLowSrc)
                }
            }
        }

        return MarketTrendMover(
            cardID: resolvedCardID ?? candidate.cardID,
            displayName: displayName ?? readableTrendKey(candidate.cardID),
            percentChange: candidate.change7d,
            imageURL: imageURL
        )
    }

    private func normalizeTrendKey(_ raw: String) -> String {
        raw.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func readableTrendKey(_ raw: String?) -> String {
        guard let raw else { return "Unknown card" }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown card" }
        return trimmed.replacingOccurrences(of: "::", with: " ")
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

    private func moverCell(title: String, mover: MarketTrendMover?, fallbackColor: Color) -> some View {
        Button {
            guard let cardID = mover?.cardID else { return }
            Task {
                if let card = await services.cardData.loadCard(masterCardId: cardID) {
                    await MainActor.run {
                        selectedCardForDetail = card
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(dashboardSecondaryText)

                HStack(spacing: 10) {
                    if let imageURL = mover?.imageURL {
                        CachedAsyncImage(url: imageURL, targetSize: CGSize(width: 120, height: 168)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(dashboardCardInsetBackground)
                                .overlay {
                                    Image(systemName: "photo")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(dashboardSecondaryText)
                                }
                        }
                        .frame(width: 42, height: 60)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(dashboardBorder, lineWidth: 1)
                        )
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(dashboardCardInsetBackground)
                            .frame(width: 42, height: 60)
                            .overlay {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(dashboardSecondaryText)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(dashboardBorder, lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top) {
                            Text(mover?.displayName ?? "No data")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(dashboardPrimaryText)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            
                            Spacer(minLength: 4)
                            
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(dashboardSecondaryText.opacity(0.8))
                        }

                        Text(formatTrendPercent(mover?.percentChange))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(mover?.percentChange == nil ? fallbackColor : trendColor(mover?.percentChange))
                            .contentTransition(.numericText())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(dashboardCardInsetBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(dashboardBorder.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(DashboardPressStyle())
        .disabled(mover?.cardID == nil)
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
    let biggestGainer7Days: MarketTrendMover?
    let biggestDecliner7Days: MarketTrendMover?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        change1Day = container.decodeDouble(forKeys: ["change1Day", "change_1_day", "change1d", "change_1d"])
        change7Days = container.decodeDouble(forKeys: ["change7Days", "change_7_days", "change7d", "change_7d"])
        change31Days = container.decodeDouble(forKeys: ["change31Days", "change_31_days", "change31d", "change_31d"])

        biggestGainer7Days = container.decodeMover(
            forKeys: ["biggestGainer7Days", "biggest_gainer_7_days", "topGainer7Days", "top_gainer_7_days"]
        )
        biggestDecliner7Days = container.decodeMover(
            forKeys: ["biggestDecliner7Days", "biggest_decliner_7_days", "topDecliner7Days", "top_decliner_7_days", "biggestLoser7Days", "biggest_loser_7_days"]
        )
    }
}

private struct MarketTrendMover: Decodable {
    let cardID: String?
    let displayName: String
    let percentChange: Double?
    let imageURL: URL?

    init(cardID: String?, displayName: String, percentChange: Double?, imageURL: URL?) {
        self.cardID = cardID
        self.displayName = displayName
        self.percentChange = percentChange
        self.imageURL = imageURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        cardID = container.decodeString(forKeys: ["cardID", "card_id", "id", "masterCardId", "master_card_id"])
        displayName = container.decodeString(forKeys: ["cardName", "card_name", "name", "title"]) ?? "Unknown card"
        percentChange = container.decodeDouble(forKeys: ["percentChange", "percent_change", "change7Days", "change_7_days", "change7d", "change_7d"])
        imageURL = container.decodeURL(
            forKeys: ["imageURL", "imageUrl", "image_url", "image", "thumbnail", "thumb"]
        )
    }
}

private struct TrendMoverCandidate {
    let cardID: String?
    let displayName: String?
    let imageURL: URL?
    let change7d: Double
    let brandHint: String?
    let setCode: String?
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

    func decodeMover(forKeys keys: [String]) -> MarketTrendMover? {
        for key in keys {
            guard let codingKey = AnyCodingKey(stringValue: key) else { continue }
            do {
                if let mover = try decodeIfPresent(MarketTrendMover.self, forKey: codingKey) {
                    return mover
                }
            } catch {
                continue
            }
        }
        return nil
    }

    func decodeURL(forKeys keys: [String]) -> URL? {
        for key in keys {
            guard let codingKey = AnyCodingKey(stringValue: key) else { continue }
            do {
                if let raw = try decodeIfPresent(String.self, forKey: codingKey) {
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    if let absolute = URL(string: trimmed), absolute.scheme != nil {
                        return absolute
                    }
                    return AppConfiguration.imageURL(relativePath: trimmed)
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
}

private struct DashboardBreakdownEntry: Identifiable {
    var id: String { label }
    let label: String
    let value: Int
}

private struct DashboardTopHolding {
    let cardID: String
    let name: String
    let setName: String?
    let imageURL: URL?
    let unitValue: Double
    let totalValue: Double
    let quantity: Int
}

private struct DashboardSetCompletionEntry: Identifiable {
    var id: String { setCode }
    let setCode: String
    let setName: String
    let ownedUnique: Int
    let totalCards: Int
    let progress: Double

    var percentString: String {
        String(format: "%.0f", progress * 100)
    }
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
    static let chartLine = Color(red: 0.12, green: 0.52, blue: 1.0)
    static let success = Color(red: 0.28, green: 0.84, blue: 0.39)
    static let gold = Color(red: 0.99, green: 0.72, blue: 0.22)
    static let orange = Color(red: 1.0, green: 0.58, blue: 0.22)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.34)
}
