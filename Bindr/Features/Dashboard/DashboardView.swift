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

    @Query(sort: \LedgerLine.occurredAt, order: .reverse) private var allLedgerLines: [LedgerLine]
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
    @State private var selectedBrand: TCGBrand? = nil
    @State private var cardNamesByID: [String: String] = [:]
    @State private var setNamesByCardID: [String: String] = [:]
    @State private var cardImageURLsByID: [String: URL] = [:]
    @State private var marketTrendData: MarketTrendDailyBlob? = nil
    @State private var selectedInsightPage: Int = 0
    @State private var cardTypeBreakdown: [DashboardBreakdownEntry] = []
    @State private var energyTypeBreakdown: [DashboardBreakdownEntry] = []
    @State private var formatBreakdown: [DashboardBreakdownEntry] = []
    @State private var mostExpensiveHolding: DashboardTopHolding? = nil
    @State private var priceBandBreakdown: [DashboardBreakdownEntry] = []
    @State private var setCompletionEntries: [DashboardSetCompletionEntry] = []

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
        Set(visibleCollectionItems.map(\.cardID)).count
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
        let svc = services.collectionValue
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .year, value: -1, to: cal.startOfDay(for: Date()))!
        var points: [ChartPoint] = []
        if let svc {
            points = svc.weeklyAverages
                .filter { $0.weekStart >= cutoff }
                .map { ChartPoint(date: $0.weekStart, total: $0.totalGbp, pokemon: $0.pokemonGbp, onePiece: $0.onePieceGbp) }
            let cwAvg = svc.currentWeekAverage(liveToday: liveSnapshot)
            if cwAvg.total > 0 {
                var cal2 = Calendar(identifier: .iso8601)
                cal2.timeZone = TimeZone.current
                let thisWeekStart = cal2.date(from: cal2.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
                points.append(ChartPoint(date: thisWeekStart, total: cwAvg.total, pokemon: cwAvg.pokemon, onePiece: cwAvg.onePiece))
            }
        }
        return points
    }

    private var monthlyPoints: [ChartPoint] {
        let svc = services.collectionValue
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .year, value: -5, to: cal.startOfDay(for: Date()))!
        var points: [ChartPoint] = []
        if let svc {
            points = svc.monthlyAverages
                .filter { $0.monthStart >= cutoff }
                .map { ChartPoint(date: $0.monthStart, total: $0.totalGbp, pokemon: $0.pokemonGbp, onePiece: $0.onePieceGbp) }
            let cmAvg = svc.currentMonthAverage(liveToday: liveSnapshot)
            let currentMonthTotal = cmAvg.total > 0 ? cmAvg.total : (liveSnapshot?.total ?? 0)
            if currentMonthTotal > 0 {
                let comps = cal.dateComponents([.year, .month], from: Date())
                let thisMonthStart = cal.date(from: comps)!
                let snap = cmAvg.total > 0 ? cmAvg : liveSnapshot!
                points.append(ChartPoint(date: thisMonthStart, total: snap.total, pokemon: snap.pokemon, onePiece: snap.onePiece))
            }
        }
        return points
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
                summaryCard
                insightsCarouselSection
                if !activePoints.isEmpty {
                    valueChartCard
                    if let trend = activeMarketTrend {
                        marketTrendCard(trend: trend, updatedAt: marketTrendData?.updatedAt)
                    }
                }
                quickActionsSection
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
            await services.collectionValue?.runBackfillIfNeeded(collectionItems: collectionItems)
        }
        .task(id: dashboardDataSignature) {
            await resolveDashboardMetadata()
            await resolveInsightsData()
        }
        .task {
            await loadMarketTrendBlob()
        }
        .onAppear {
            selectedBrand = activeBrand
        }
        .onChange(of: services.brandSettings.selectedCatalogBrand) { _, brand in
            selectedBrand = brand
            selectedPoint = nil
        }
        .onChange(of: chartRange) { _, _ in
            selectedPoint = nil
            selectedBrand = activeBrand
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

    private var summaryCard: some View {
        dashboardCard {
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
            }
        }
    }

    private var insightPageCount: Int { 7 }
    private var insightPageHeight: CGFloat { 210 }

    private var insightsCarouselSection: some View {
        dashboardCard {
            VStack(spacing: 12) {
                TabView(selection: $selectedInsightPage) {
                    collectionSummaryInsightCard
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .tag(0)

                    distributionInsightCard(
                        title: "Distribution by Card Type",
                        entries: cardTypeBreakdown,
                        emptyMessage: "Add more cards to see a card-type split."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .tag(1)

                    distributionInsightCard(
                        title: "Distribution by Energy Type",
                        entries: energyTypeBreakdown,
                        emptyMessage: "No energy/type data available yet."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .tag(2)

                    setCompletionInsightCard
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .tag(3)

                    mostExpensiveCardInsightCard
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .tag(4)

                    priceBandInsightCard
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .tag(5)

                    distributionInsightCard(
                        title: "Collection Format Mix",
                        entries: formatBreakdown,
                        emptyMessage: "No format data available yet."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .tag(6)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: insightPageHeight)

                HStack(spacing: 8) {
                    ForEach(0..<insightPageCount, id: \.self) { index in
                        Capsule(style: .continuous)
                            .fill(index == selectedInsightPage ? services.theme.accentColor : dashboardDividerColor)
                            .frame(width: index == selectedInsightPage ? 18 : 8, height: 8)
                            .animation(.easeInOut(duration: 0.18), value: selectedInsightPage)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    if #available(iOS 26.0, *) {
                        Capsule(style: .continuous)
                            .fill(.clear)
                            .glassEffect(.regular, in: Capsule(style: .continuous))
                    } else {
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(dashboardBorder.opacity(0.35), lineWidth: 1)
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Most Expensive Card")
                .font(.title3.weight(.semibold))
                .foregroundStyle(dashboardPrimaryText)

            if let topCard = mostExpensiveHolding {
                HStack(spacing: 12) {
                    if let imageURL = topCard.imageURL {
                        CachedAsyncImage(url: imageURL, targetSize: CGSize(width: 120, height: 168)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(dashboardCardInsetBackground)
                                .overlay {
                                    Image(systemName: "photo")
                                        .font(.headline)
                                        .foregroundStyle(dashboardSecondaryText)
                                }
                        }
                        .frame(width: 48, height: 68)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(dashboardBorder, lineWidth: 1)
                        )
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(topCard.name)
                            .font(.headline)
                            .foregroundStyle(dashboardPrimaryText)
                            .lineLimit(1)
                        Text(topCard.setName ?? "Set unknown")
                            .font(.subheadline)
                            .foregroundStyle(dashboardSecondaryText)
                            .lineLimit(1)
                        Text("Owned: \(topCard.quantity)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(dashboardSecondaryText)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(formatCurrency(topCard.unitValue))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(dashboardPrimaryText)
                            .contentTransition(.numericText())
                        Text("per card")
                            .font(.caption)
                            .foregroundStyle(dashboardSecondaryText)
                        if topCard.quantity > 1 {
                            Text("Total: \(formatCurrency(topCard.totalValue))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(dashboardSecondaryText)
                                .lineLimit(1)
                        }
                    }
                }
            } else {
                Text("No priced cards yet.")
                    .font(.subheadline)
                    .foregroundStyle(dashboardSecondaryText)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Sets Closest to Completion")
                .font(.title3.weight(.semibold))
                .foregroundStyle(dashboardPrimaryText)

            if setCompletionEntries.isEmpty {
                Text("Add cards from sets to track completion progress.")
                    .font(.subheadline)
                    .foregroundStyle(dashboardSecondaryText)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(setCompletionEntries.prefix(3))) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(entry.setName)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(dashboardPrimaryText)
                                    .lineLimit(1)

                                Spacer(minLength: 8)

                                Text("\(entry.percentString)%")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(services.theme.accentColor)
                            }

                            ProgressView(value: entry.progress)
                                .progressViewStyle(.linear)
                                .tint(services.theme.accentColor)

                            Text("\(entry.ownedUnique)/\(entry.totalCards) cards")
                                .font(.caption)
                                .foregroundStyle(dashboardSecondaryText)
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
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(dashboardPrimaryText)

            if entries.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(dashboardSecondaryText)
            } else {
                VStack(spacing: 10) {
                    let maxValue = max(entries.map(\.value).max() ?? 1, 1)
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        insightBarRow(entry: entry, maxValue: maxValue, tint: dashboardBreakdownColor(at: index))
                    }
                }
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

    private func insightBarRow(entry: DashboardBreakdownEntry, maxValue: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(dashboardPrimaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(entry.value)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(dashboardSecondaryText)
            }

            ProgressView(value: Double(entry.value), total: Double(maxValue))
                .progressViewStyle(.linear)
                .tint(tint)
        }
    }

    private var valueChartCard: some View {
        dashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Value History")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(dashboardPrimaryText)
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
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
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

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.title3.weight(.semibold))
                .foregroundStyle(dashboardPrimaryText)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                quickActionTile(
                    title: "Scan Card",
                    icon: "camera.fill",
                    tint: DashboardPalette.purple,
                    action: onOpenScanner
                )

                quickActionTile(
                    title: "Bindrs",
                    icon: "plus.circle.fill",
                    tint: DashboardPalette.success,
                    action: onOpenCollection
                )

                quickActionTile(
                    title: "Deck Builder",
                    icon: "square.stack.3d.up.fill",
                    tint: DashboardPalette.blue,
                    action: onOpenBrowse
                )

                quickActionTile(
                    title: "Activity",
                    icon: "clock.arrow.circlepath",
                    tint: DashboardPalette.gold,
                    action: onViewAllActivity
                )
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
                            dashboardActivityRow(line: line)
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
        Color(uiColor: .systemBackground)
    }

    private func dashboardBreakdownColor(at index: Int) -> Color {
        let colors: [Color] = [
            DashboardPalette.purple,
            DashboardPalette.blue,
            DashboardPalette.success,
            DashboardPalette.gold,
            services.theme.accentColor
        ]
        return colors[index % colors.count]
    }

    private var dashboardDataSignature: String {
        let brand = activeBrand.rawValue
        let itemPart = visibleCollectionItems.map {
            [
                $0.cardID,
                "\($0.quantity)",
                $0.variantKey,
                $0.itemKind,
                $0.gradingCompany ?? "-",
                $0.sealedStatus ?? "-"
            ].joined(separator: "|")
        }.joined(separator: "§")
        let linePart = recentLines.map { cleaned($0.cardID) ?? $0.id.uuidString }.joined(separator: "§")
        return "\(brand)|\(itemPart)|\(linePart)"
    }

    private func quickActionTile(title: String, icon: String, tint: Color, action: (() -> Void)?) -> some View {
        Button {
            action?()
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(tint.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(tint)
                }

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(dashboardPrimaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 108)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(dashboardCardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(dashboardBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(DashboardPressStyle())
        .disabled(action == nil)
    }

    private func dashboardActivityRow(line: LedgerLine) -> some View {
        HStack(spacing: 12) {
            activityLeadingVisual(for: line)

            VStack(alignment: .leading, spacing: 4) {
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
                }

                Text(activitySubtitle(for: line))
                    .font(.subheadline)
                    .foregroundStyle(dashboardSecondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(line.occurredAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(dashboardSecondaryText)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(dashboardSecondaryText)
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
        services.sealedProducts.loadFromLocalIfAvailable()

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
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(dashboardCardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(dashboardBorder, lineWidth: 1)
                    )
            )
    }

    private func computeLiveValue() async {
        isLoadingValue = true
        defer { isLoadingValue = false }
        services.sealedProducts.loadFromLocalIfAvailable()

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
            guard let sets = try? CatalogStore.shared.fetchAllSets(for: brand) else { continue }
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
                let preferredPath = cleaned(card.imageHighSrc) ?? card.imageLowSrc
                nextImages[cardID] = AppConfiguration.imageURL(relativePath: preferredPath)
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
        services.sealedProducts.loadFromLocalIfAvailable()

        var nextCardType: [String: Int] = [:]
        var nextEnergyType: [String: Int] = [:]
        var nextFormat: [String: Int] = [:]
        var nextPriceBand: [String: Int] = ["£": 0, "££": 0, "£££": 0]
        var nextMostExpensive: DashboardTopHolding? = nil
        var ownedCardIDsBySetCode: [String: Set<String>] = [:]
        var cardCache: [String: Card] = [:]

        let setsForBrand = (try? CatalogStore.shared.fetchAllSets(for: activeBrand)) ?? []
        var setTotalsByCode: [String: (name: String, total: Int)] = [:]
        for set in setsForBrand {
            let total = set.cardCountOfficial ?? set.cardCountTotal ?? 0
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

            guard unitValue > 0 else { continue }
            let totalValue = unitValue * Double(quantity)
            if let currentTop = nextMostExpensive, currentTop.unitValue >= unitValue {
                continue
            }

            let preferredImagePath = cleaned(card.imageHighSrc) ?? card.imageLowSrc
            nextMostExpensive = DashboardTopHolding(
                cardID: card.masterCardId,
                name: card.cardName,
                setName: setNamesByCardID[card.masterCardId],
                imageURL: AppConfiguration.imageURL(relativePath: preferredImagePath),
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
        return cleaned(line.lineDescription) ?? "Collection update"
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
        value >= 1000
            ? "£\(String(format: "%.1fk", value / 1000))"
            : "£\(String(format: "%.0f", value))"
    }

    private func loadMarketTrendBlob() async {
        guard let data = CatalogStore.shared.dailyBlob(key: DailyBlobKey.marketTrend) else {
            marketTrendData = nil
            return
        }
        do {
            marketTrendData = try JSONDecoder().decode(MarketTrendDailyBlob.self, from: data)
        } catch {
            marketTrendData = nil
        }
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
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.34)
}
