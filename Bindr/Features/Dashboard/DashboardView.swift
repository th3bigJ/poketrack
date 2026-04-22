import SwiftUI
import SwiftData
import Charts

private enum ChartRange: String, CaseIterable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
}

struct DashboardView: View {
    var onViewAllActivity: (() -> Void)? = nil
    var onOpenScanner: (() -> Void)? = nil
    var onOpenCollection: (() -> Void)? = nil
    var onOpenBrowse: (() -> Void)? = nil

    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset

    @Query(sort: \LedgerLine.occurredAt, order: .reverse) private var allLedgerLines: [LedgerLine]
    @Query private var collectionItems: [CollectionItem]
    @Query(sort: \WishlistItem.dateAdded, order: .reverse) private var wishlistItems: [WishlistItem]

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
        Color(uiColor: .secondarySystemBackground)
    }

    private var dashboardCardInsetBackground: Color {
        Color(uiColor: .tertiarySystemFill)
    }

    private var dashboardBorder: Color {
        Color(uiColor: .separator).opacity(colorScheme == .dark ? 0.28 : 0.16)
    }

    private var dashboardDividerColor: Color {
        Color(uiColor: .separator).opacity(colorScheme == .dark ? 0.22 : 0.14)
    }

    private var backfillTrigger: String {
        "\(services.collectionValue == nil ? "nil" : "ready"):\(collectionItems.count)"
    }

    private var dailyPoints: [ChartPoint] {
        let svc = services.collectionValue
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -31, to: cal.startOfDay(for: Date()))!
        var points: [ChartPoint] = []
        if let svc {
            points = svc.snapshots
                .filter { $0.date >= cutoff }
                .map { ChartPoint(date: $0.date, total: $0.totalGbp, pokemon: $0.pokemonGbp, onePiece: $0.onePieceGbp) }
        }
        if let live = liveTotalGbp {
            points.append(ChartPoint(date: cal.startOfDay(for: Date()), total: live, pokemon: livePokemonGbp, onePiece: liveOnePieceGbp))
        }
        return points
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
                summaryCard
                statsStrip
                if !activePoints.isEmpty {
                    valueChartCard
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

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hello, Trainer.")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(dashboardPrimaryText)
        }
        .frame(maxWidth: .infinity, alignment: .center)
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
                                .tint(DashboardPalette.chartLine)
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

    private var statsStrip: some View {
        dashboardCard {
            HStack(spacing: 0) {
                dashboardStat(
                    icon: "square.stack.3d.up.fill",
                    iconColor: DashboardPalette.purple,
                    value: "\(totalCardsCount)",
                    label: "Total Cards"
                )

                statDivider

                dashboardStat(
                    icon: "rectangle.stack.fill",
                    iconColor: DashboardPalette.blue,
                    value: "\(uniqueCardsCount)",
                    label: "Unique Cards"
                )

                statDivider

                dashboardStat(
                    icon: "star.fill",
                    iconColor: DashboardPalette.gold,
                    value: "\(wishlistedCardsCount)",
                    label: "Wishlisted Cards"
                )
            }
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
                    Picker("Range", selection: $chartRange) {
                        ForEach(ChartRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 270)
                }

                Chart(activePoints) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Min", chartMin),
                        yEnd: .value("Value", point.total)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [DashboardPalette.chartLine.opacity(0.3), DashboardPalette.chartLine.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.total)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(DashboardPalette.chartLine)
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
                            .foregroundStyle(DashboardPalette.purple)
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

    private var statDivider: some View {
        Rectangle()
            .fill(dashboardDividerColor)
            .frame(width: 1, height: 52)
    }

    private var dashboardDataSignature: String {
        let brand = activeBrand.rawValue
        let itemPart = visibleCollectionItems.map { "\($0.cardID)|\($0.quantity)" }.joined(separator: "§")
        let linePart = recentLines.map { cleaned($0.cardID) ?? $0.id.uuidString }.joined(separator: "§")
        return "\(brand)|\(itemPart)|\(linePart)"
    }

    private func dashboardStat(icon: String, iconColor: Color, value: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(iconColor)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(dashboardPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(dashboardSecondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
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
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(DashboardPalette.purple.opacity(0.35))
                            )
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

    @ViewBuilder
    private func activityLeadingVisual(for line: LedgerLine) -> some View {
        if let cardID = cleaned(line.cardID), let imageURL = cardImageURLsByID[cardID] {
            CachedAsyncImage(url: imageURL, targetSize: CGSize(width: 120, height: 168)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                fallbackCardArtwork(for: line)
            }
            .frame(width: 48, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(dashboardBorder, lineWidth: 1)
            )
        } else {
            fallbackCardArtwork(for: line)
        }
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

        var totalValue = 0.0
        var pokemonValue = 0.0
        var onePieceValue = 0.0
        var totalCost = 0.0

        for item in collectionItems {
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
            let gbp = usdPrice * Double(item.quantity) * services.pricing.usdToGbp
            totalValue += gbp

            switch TCGBrand.inferredFromMasterCardId(item.cardID) {
            case .pokemon: pokemonValue += gbp
            case .onePiece: onePieceValue += gbp
            }

            totalCost += (item.purchasePrice ?? 0) * Double(item.quantity)
        }

        liveTotalGbp = totalValue > 0 ? totalValue : nil
        livePokemonGbp = pokemonValue
        liveOnePieceGbp = onePieceValue
        totalCostBasis = totalCost
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
        case .adjustmentIn, .adjustmentOut: return "Adjusted"
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

private struct ChartPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let total: Double
    let pokemon: Double
    let onePiece: Double
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
