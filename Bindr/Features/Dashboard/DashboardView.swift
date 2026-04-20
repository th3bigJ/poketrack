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
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset

    @Query(sort: \LedgerLine.occurredAt, order: .reverse) private var allLedgerLines: [LedgerLine]
    @Query private var collectionItems: [CollectionItem]

    @State private var liveTotalGbp: Double? = nil
    @State private var livePokemonGbp: Double = 0
    @State private var liveOnePieceGbp: Double = 0
    @State private var totalCostBasis: Double = 0
    @State private var isLoadingValue = false
    @State private var selectedPoint: ChartPoint? = nil
    @State private var chartRange: ChartRange = .daily
    @State private var selectedBrand: TCGBrand? = nil

    // MARK: - Display values (live or scrubbed)

    private var liveSnapshot: BrandSnapshot? {
        guard let t = liveTotalGbp else { return nil }
        return BrandSnapshot(total: t, pokemon: livePokemonGbp, onePiece: liveOnePieceGbp)
    }

    private func brandValue(_ point: ChartPoint) -> Double {
        switch selectedBrand {
        case .pokemon:  return point.pokemon
        case .onePiece: return point.onePiece
        case nil:       return point.total
        }
    }

    private var displayTotal: Double {
        let point = selectedPoint
        switch selectedBrand {
        case .pokemon:  return point?.pokemon  ?? livePokemonGbp
        case .onePiece: return point?.onePiece ?? liveOnePieceGbp
        case nil:       return point?.total    ?? liveTotalGbp ?? 0
        }
    }
    private var displayPokemon: Double  { selectedPoint?.pokemon  ?? livePokemonGbp }
    private var displayOnePiece: Double { selectedPoint?.onePiece ?? liveOnePieceGbp }
    private var isScrubbingOrLoaded: Bool { selectedPoint != nil || liveTotalGbp != nil }

    private var activeBrand: TCGBrand { services.brandSettings.selectedCatalogBrand }
    private var recentLines: [LedgerLine] {
        Array(
            allLedgerLines.filter { line in
                guard let cardID = line.cardID?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !cardID.isEmpty else {
                    return false
                }
                return TCGBrand.inferredFromMasterCardId(cardID) == activeBrand
            }
            .prefix(5)
        )
    }

    /// The point whose value we're comparing against (the one before the displayed point).
    private var periodChange: (amount: Double, pct: Double, label: String)? {
        let points = activePoints
        guard points.count >= 2 else { return nil }

        // When scrubbing: compare selected point to the one before it.
        // When not scrubbing: compare the last point (live/today) to the second-to-last.
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
        case .daily:   label = "vs prev day"
        case .weekly:  label = "vs prev week"
        case .monthly: label = "vs prev month"
        }
        return (amount, pct, label)
    }

    private var backfillTrigger: String {
        "\(services.collectionValue == nil ? "nil" : "ready"):\(collectionItems.count)"
    }

    // MARK: - Chart points for each range

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
            // Append current incomplete week average
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
            // Current month: average past days this month + today's live value.
            // Falls back to just today's live value if no past-days exist yet.
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
        case .daily:   base = dailyPoints
        case .weekly:  base = weeklyPoints
        case .monthly: base = monthlyPoints
        }
        guard let brand = selectedBrand else { return base }
        return base.map { p in
            let v: Double
            switch brand {
            case .pokemon:  v = p.pokemon
            case .onePiece: v = p.onePiece
            }
            return ChartPoint(date: p.date, total: v, pokemon: p.pokemon, onePiece: p.onePiece)
        }
    }

    private var chartMin: Double { (activePoints.map(\.total).min() ?? 0) * 0.95 }
    private var chartMax: Double { (activePoints.map(\.total).max() ?? 0) * 1.05 }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                valueHeaderCard
                if !activePoints.isEmpty {
                    valueChartCard
                }
                brandBreakdownRow
                recentActivityCard
            }
            .padding(16)
        }
        .safeAreaPadding(.top, rootFloatingChromeInset)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: collectionItems.count) {
            await computeLiveValue()
        }
        .task(id: backfillTrigger) {
            guard services.collectionValue != nil else { return }
            await services.collectionValue?.runBackfillIfNeeded(collectionItems: collectionItems)
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

    // MARK: - Cards

    private var valueHeaderCard: some View {
        DashboardCard(title: selectedBrand.map { "\($0.displayTitle) Value" } ?? "Collection Value") {
            if isLoadingValue && liveTotalGbp == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else if isScrubbingOrLoaded {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(formatCurrency(displayTotal))
                            .font(.title.bold())
                            .contentTransition(.numericText())
                        Spacer()
                        if let change = periodChange {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text((change.amount >= 0 ? "+" : "") + formatCurrency(change.amount))
                                    .font(.headline)
                                    .foregroundStyle(change.amount >= 0 ? .green : .red)
                                    .contentTransition(.numericText())
                                HStack(spacing: 4) {
                                    Text(String(format: "%.1f%%", change.pct))
                                        .foregroundStyle(change.pct >= 0 ? .green : .red)
                                    Text(change.label)
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                            }
                        }
                    }
                    if let point = selectedPoint {
                        Text(rangeLabel(for: point.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("No pricing data yet")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var valueChartCard: some View {
        DashboardCard(title: "Value History") {
            VStack(spacing: 12) {
                Picker("Range", selection: $chartRange) {
                    ForEach(ChartRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                Chart(activePoints) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Min", chartMin),
                        yEnd: .value("Value", point.total)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.total)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    if let sel = selectedPoint, sel.date == point.date {
                        RuleMark(x: .value("Date", point.date))
                            .foregroundStyle(Color.secondary.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.total)
                        )
                        .symbolSize(60)
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(Color.secondary.opacity(0.3))
                        AxisValueLabel {
                            if let d = value.as(Double.self) {
                                Text(formatCurrencyShort(d))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartYScale(domain: chartMin...max(chartMax, chartMin + 1))
                .frame(height: 180)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let x = value.location.x - geo[proxy.plotFrame!].origin.x
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

    private var brandBreakdownRow: some View {
        return HStack(spacing: 8) {
            if activeBrand == .pokemon {
                BrandValueTile(brand: "Pokémon", value: displayPokemon, isSelected: selectedBrand == .pokemon, hasSelection: selectedBrand != nil, formatter: formatCurrency) {
                    selectedBrand = .pokemon
                    selectedPoint = nil
                }
            }
            if activeBrand == .onePiece {
                BrandValueTile(brand: "ONE PIECE", value: displayOnePiece, isSelected: selectedBrand == .onePiece, hasSelection: selectedBrand != nil, formatter: formatCurrency) {
                    selectedBrand = .onePiece
                    selectedPoint = nil
                }
            }
        }
    }

    private var recentActivityCard: some View {
        DashboardCard(title: "Recent Activity", trailing: {
            if let onViewAllActivity {
                Button("View All") { onViewAllActivity() }
                    .font(.caption)
            }
        }) {
            if recentLines.isEmpty {
                Text("No transactions yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(recentLines) { line in
                        HStack(spacing: 10) {
                            Image(systemName: directionIcon(for: line))
                                .font(.caption)
                                .foregroundStyle(directionColor(for: line))
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(line.lineDescription)
                                    .font(.caption)
                                    .lineLimit(1)
                                Text(line.occurredAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("×\(line.quantity)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                        if line.id != recentLines.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Live value computation

    private func computeLiveValue() async {
        isLoadingValue = true
        defer { isLoadingValue = false }

        var totalValue = 0.0
        var pokemonValue = 0.0
        var onePieceValue = 0.0
        var totalCost = 0.0

        for item in collectionItems {
            guard let card = await services.cardData.loadCard(masterCardId: item.cardID) else { continue }
            let usdPrice = await services.pricing.usdPriceForVariant(for: card, variantKey: item.variantKey) ?? 0
            let gbp = usdPrice * Double(item.quantity) * services.pricing.usdToGbp
            totalValue += gbp

            switch TCGBrand.inferredFromMasterCardId(item.cardID) {
            case .pokemon:  pokemonValue += gbp
            case .onePiece: onePieceValue += gbp
            }

            totalCost += (item.purchasePrice ?? 0) * Double(item.quantity)
        }

        liveTotalGbp = totalValue > 0 ? totalValue : nil
        livePokemonGbp = pokemonValue
        liveOnePieceGbp = onePieceValue
        totalCostBasis = totalCost
    }

    // MARK: - Helpers

    private func rangeLabel(for date: Date) -> String {
        switch chartRange {
        case .daily:
            return date.formatted(date: .abbreviated, time: .omitted)
        case .weekly:
            let end = Calendar.current.date(byAdding: .day, value: 6, to: date) ?? date
            return "w/c \(date.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
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

    private func directionIcon(for line: LedgerLine) -> String {
        guard let dir = LedgerDirection(rawValue: line.direction) else { return "circle" }
        switch dir {
        case .bought:        return "cart.fill"
        case .packed:        return "shippingbox.fill"
        case .sold:          return "dollarsign.circle.fill"
        case .tradedIn:      return "arrow.left.arrow.right.circle.fill"
        case .tradedOut:     return "arrow.left.arrow.right.circle"
        case .giftedIn:      return "gift.fill"
        case .giftedOut:     return "gift"
        case .adjustmentIn:  return "plus.circle.fill"
        case .adjustmentOut: return "minus.circle.fill"
        }
    }

    private func directionColor(for line: LedgerLine) -> Color {
        guard let dir = LedgerDirection(rawValue: line.direction) else { return .secondary }
        switch dir {
        case .bought, .packed, .tradedIn, .giftedIn, .adjustmentIn:   return .green
        case .sold, .tradedOut, .giftedOut, .adjustmentOut:            return .red
        }
    }
}

// MARK: - Supporting types

private struct ChartPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let total: Double
    let pokemon: Double
    let onePiece: Double
}

private struct BrandValueTile: View {
    let brand: String
    let value: Double
    let isSelected: Bool
    let hasSelection: Bool
    let formatter: (Double) -> String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(brand)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(formatter(value))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(isSelected ? .primary : (hasSelection ? .secondary : (value > 0 ? .primary : .secondary)))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .opacity(hasSelection && !isSelected ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .animation(.easeInOut(duration: 0.18), value: hasSelection)
    }
}

private struct DashboardCard<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                trailing()
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
