import SwiftUI
import Charts

// MARK: - Chart range

private enum ChartRange: String, CaseIterable {
    case oneMonth = "1M"
    case threeMonths = "3M"
    case oneYear = "1Y"
}

// MARK: - Main panel

struct CardPricingPanel: View {
    @Environment(AppServices.self) private var services

    let card: Card

    // Scrydex variant keys (e.g. "holofoil", "normal")
    @State private var variantKeys: [String] = []
    @State private var selectedVariant: String? = nil

    // Grade keys available for the selected variant (e.g. "raw", "psa10")
    @State private var selectedGrade: String? = nil

    @State private var currentPrice: String = "—"
    @State private var history: CardPriceHistory? = nil
    @State private var trends: CardPriceTrends? = nil  // single entry (first/best match)
    @State private var isLoading = false
    @State private var chartRange: ChartRange = .oneMonth
    @State private var scrubPoint: PriceDataPoint? = nil

    // All variant names present in history
    private var historyVariants: [String] {
        guard let history else { return [] }
        var seen: [String] = []
        for key in history.series.keys.sorted() {
            let variant = key.components(separatedBy: "/").first ?? key
            if !seen.contains(variant) { seen.append(variant) }
        }
        return seen
    }

    // Grade names available for the currently selected variant
    private var gradesForVariant: [String] {
        guard let history, let variant = selectedVariant else { return [] }
        let gradeOrder = ["raw", "psa10", "ace10"]
        let grades = history.series.keys
            .filter { $0.hasPrefix(variant + "/") }
            .map { $0.components(separatedBy: "/").last ?? $0 }
        return grades.sorted { a, b in
            let ai = gradeOrder.firstIndex(of: a) ?? 99
            let bi = gradeOrder.firstIndex(of: b) ?? 99
            return ai < bi
        }
    }

    private var activeSeriesKey: String? {
        guard let variant = selectedVariant, let grade = selectedGrade else { return nil }
        return "\(variant)/\(grade)"
    }

    private var chartSeries: CardPriceHistory.Series? {
        guard let history, let key = activeSeriesKey else { return nil }
        return history.series[key]
    }

    private var chartPoints: [PriceDataPoint] {
        guard let series = chartSeries else { return [] }
        switch chartRange {
        case .oneMonth:    return Array(series.daily.suffix(30))
        case .threeMonths: return Array(series.weekly.suffix(13))
        case .oneYear:     return Array(series.monthly.suffix(12))
        }
    }

    private var currentTrend: CardPriceTrends? { trends }

    // Picker keys: history variants if available, else scrydex keys
    private var displayedVariants: [String] {
        historyVariants.isEmpty ? variantKeys : historyVariants
    }

    var body: some View {
        VStack(spacing: 0) {
            // Row 1: variant picker
            if !displayedVariants.isEmpty {
                chipPicker(keys: displayedVariants, selected: $selectedVariant) { variantDisplayName($0) }
                    .padding(.top, 12)
            }

            // Row 2: grade picker (only when >1 grade available)
            if gradesForVariant.count > 1 {
                chipPicker(keys: gradesForVariant, selected: $selectedGrade) { gradeDisplayName($0) }
                    .padding(.top, 6)
            }

            // Market price / scrub date label
            Text(scrubPoint != nil ? truncatedLabel(scrubPoint!.label) : "Market Price")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 12)
                .animation(.none, value: scrubPoint?.label)

            Text(scrubPoint != nil ? String(format: "£%.2f", scrubPoint!.price * services.pricing.usdToGbp) : currentPrice)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 2)
                .animation(.none, value: scrubPoint?.price)

            // % change badges
            if let trend = currentTrend {
                HStack(spacing: 12) {
                    changeBadge(label: "1D", value: trend.change1d)
                    changeBadge(label: "7D", value: trend.change7d)
                    changeBadge(label: "1M", value: trend.change30d)
                }
                .padding(.top, 8)
                .padding(.bottom, 4)
            }

            // Chart
            if !chartPoints.isEmpty {
                chartView
                    .padding(.top, 16)

                Picker("Range", selection: $chartRange) {
                    ForEach(ChartRange.allCases, id: \.self) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            } else if isLoading {
                ProgressView()
                    .tint(.white)
                    .padding(.vertical, 24)
            } else {
                Spacer().frame(height: 16)
            }
        }
        .task(id: card.masterCardId) {
            await load()
        }
        .onChange(of: selectedVariant) { _, variant in
            // Reset grade when variant changes — history is already loaded at this point
            let grades = gradesForSelectedVariant(variant: variant)
            let newGrade = grades.first(where: { $0 == "raw" }) ?? grades.first
            selectedGrade = newGrade
            Task { await refreshPrice() }
        }
        .onChange(of: selectedGrade) { _, _ in
            Task { await refreshPrice() }
        }
    }

    // MARK: - Chip picker

    @ViewBuilder
    private func chipPicker(keys: [String], selected: Binding<String?>, label: @escaping (String) -> String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(keys, id: \.self) { key in
                    Button { selected.wrappedValue = key } label: {
                        Text(label(key))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(
                                selected.wrappedValue == key ? Color.white : Color.white.opacity(0.1)
                            ))
                            .foregroundStyle(selected.wrappedValue == key ? Color.black : Color.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Chart

    private var chartView: some View {
        let points = chartPoints
        let prices = points.map(\.price)
        let minP = (prices.min() ?? 0) * 0.97
        let maxP = (prices.max() ?? 1) * 1.03
        let rate = services.pricing.usdToGbp

        return Chart(points) { point in
            LineMark(
                x: .value("Date", point.label),
                y: .value("Price", point.price)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(Color.white)

            AreaMark(
                x: .value("Date", point.label),
                yStart: .value("Min", minP),
                yEnd: .value("Price", point.price)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(LinearGradient(
                colors: [Color.white.opacity(0.25), Color.white.opacity(0.02)],
                startPoint: .top, endPoint: .bottom
            ))
        }
        .chartYScale(domain: minP...maxP)
        .chartXAxis {
            let stride = max(1, points.count / 4)
            let lastIndex = points.count - 1
            let visibleLabels = Set(points.enumerated().compactMap { i, p -> String? in
                (i == 0 || i == lastIndex || i % stride == 0) ? p.label : nil
            })
            AxisMarks(values: points.map(\.label)) { value in
                if let label = value.as(String.self), visibleLabels.contains(label) {
                    let isFirst = label == points.first?.label
                    let isLast = label == points.last?.label
                    AxisValueLabel(truncatedLabel(label), anchor: isFirst ? .topLeading : isLast ? .topTrailing : .top)
                        .foregroundStyle(Color.white.opacity(0.5))
                        .font(.system(size: 9))
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.05))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                if let price = value.as(Double.self) {
                    AxisValueLabel(String(format: "£%.2f", price * rate))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .font(.system(size: 9))
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.1))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plotFrame = geo[proxy.plotAreaFrame]

                // Scrub indicator drawn directly — no chart marks so layout never changes
                if let scrub = scrubPoint, let xPos = proxy.position(forX: scrub.label) {
                    let x = xPos + plotFrame.origin.x
                    // Vertical rule
                    Rectangle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                        .offset(x: x - 0.75)
                        .allowsHitTesting(false)

                    // Dot at price level
                    if let yPos = proxy.position(forY: scrub.price) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .offset(x: x - 4, y: plotFrame.origin.y + yPos - 4)
                            .allowsHitTesting(false)
                    }
                }

                // Gesture layer
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = value.location.x - plotFrame.origin.x
                                guard x >= 0, x <= plotFrame.width else { return }
                                if let label: String = proxy.value(atX: x) {
                                    scrubPoint = nearestPoint(to: label, in: points)
                                }
                            }
                            .onEnded { _ in
                                scrubPoint = nil
                            }
                    )
            }
        }
        .frame(height: 160)
        .padding(.horizontal, 16)
    }

    private func truncatedLabel(_ label: String) -> String {
        switch chartRange {
        case .oneMonth:
            return String(label.suffix(5))  // MM-DD
        case .threeMonths:
            // "2026-W14" → Monday date of that week e.g. "Mar 30"
            return weekLabelToDate(label)
        case .oneYear:
            // "2026-03" → "Mar"
            return monthLabelToShort(label)
        }
    }

    private func weekLabelToDate(_ label: String) -> String {
        // Format: "YYYY-Www"
        let parts = label.components(separatedBy: "-W")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let week = Int(parts[1]) else { return label }
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let date = cal.date(from: DateComponents(weekOfYear: week, yearForWeekOfYear: year)) else { return label }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: date)
    }

    private func monthLabelToShort(_ label: String) -> String {
        // Format: "YYYY-MM"
        let parts = label.components(separatedBy: "-")
        guard parts.count == 2, let month = Int(parts[1]) else { return label }
        let fmt = DateFormatter()
        return fmt.shortMonthSymbols[month - 1]
    }

    private func nearestPoint(to label: String, in points: [PriceDataPoint]) -> PriceDataPoint? {
        guard !points.isEmpty else { return nil }
        if let exact = points.first(where: { $0.label == label }) { return exact }
        let sorted = points.sorted { $0.label < $1.label }
        for (i, p) in sorted.enumerated() {
            if p.label > label {
                return i == 0 ? p : sorted[i - 1]
            }
        }
        return sorted.last
    }

    // MARK: - Badge

    @ViewBuilder
    private func changeBadge(label: String, value: Double?) -> some View {
        if let value {
            HStack(spacing: 3) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Image(systemName: value >= 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 9, weight: .bold))
                Text(String(format: "%.1f%%", abs(value)))
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(value >= 0 ? Color.green : Color.red)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill((value >= 0 ? Color.green : Color.red).opacity(0.15)))
        }
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        async let keysTask = services.pricing.variantKeys(for: card)
        async let historyTask = services.pricing.priceHistory(for: card)
        async let trendsTask = services.pricing.priceTrends(for: card)

        let (keys, hist, trnd) = await (keysTask, historyTask, trendsTask)

        // Set history first so grade lookups work immediately
        variantKeys = keys
        history = hist
        trends = trnd

        // Derive available variants from history series keys
        var historyVariantsSeen: [String] = []
        for key in (hist?.series.keys ?? [:].keys) {
            let v = key.components(separatedBy: "/").first ?? key
            if !historyVariantsSeen.contains(v) { historyVariantsSeen.append(v) }
        }
        let availableVariants = historyVariantsSeen.isEmpty ? keys : historyVariantsSeen

        // Pick default variant
        let preferredVariants = ["holofoil", "normal", "reverseHolofoil"]
        let defaultVariant = preferredVariants.first(where: { availableVariants.contains($0) }) ?? availableVariants.first
        selectedVariant = defaultVariant

        // Pick default grade directly (don't rely on onChange firing in time)
        let grades = gradesForSelectedVariant(variant: defaultVariant)
        selectedGrade = grades.first(where: { $0 == "raw" }) ?? grades.first

        await refreshPrice()
    }

    private func refreshPrice() async {
        currentPrice = "—"
        guard let variant = selectedVariant, !variant.isEmpty else { return }
        let grade = selectedGrade ?? "raw"
        if let gbp = await services.pricing.gbpPriceForVariantAndGrade(for: card, variantKey: variant, grade: grade) {
            currentPrice = String(format: "£%.2f", gbp)
        }
    }

    private func gradesForSelectedVariant(variant: String?) -> [String] {
        guard let history, let variant else { return [] }
        let gradeOrder = ["raw", "psa10", "ace10"]
        let grades = history.series.keys
            .filter { $0.hasPrefix(variant + "/") }
            .map { $0.components(separatedBy: "/").last ?? $0 }
        return grades.sorted {
            (gradeOrder.firstIndex(of: $0) ?? 99) < (gradeOrder.firstIndex(of: $1) ?? 99)
        }
    }

    // MARK: - Display names

    private func variantDisplayName(_ key: String) -> String {
        let spaced = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return spaced.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func gradeDisplayName(_ key: String) -> String {
        switch key {
        case "raw":   return "Raw"
        case "psa10": return "PSA 10"
        case "ace10": return "ACE 10"
        default:      return key.uppercased()
        }
    }
}
