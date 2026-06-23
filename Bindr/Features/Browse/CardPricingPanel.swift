import SwiftUI
import Charts
import UIKit

// MARK: - Chart range

private enum ChartRange: String, CaseIterable {
    case oneDay = "1D"
    case sevenDays = "7D"
    case oneMonth = "1M"
    case threeMonths = "3M"
    case oneYear = "1Y"
    case all = "ALL"

    /// Ranges exposed in the card-detail picker. The other cases stay in the
    /// enum so the resolve logic keeps working, they're just not shown.
    static let selectable: [ChartRange] = [.oneMonth, .oneYear, .all]
}

private enum ChartDataResolution {
    case daily
    case weekly
    case monthly
}

// MARK: - Main panel

struct CardPricingPanel: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    let card: Card
    /// Pre-select this variant when the panel first loads. If nil the panel picks its own default.
    var initialVariant: String? = nil
    /// When true, skips the panel's own background so the caller can apply glass styling.
    var useGlass: Bool = false
    /// Fixed chart height. When nil, the chart expands to fill available vertical space
    /// (used by the one-screen card detail layout).
    var chartHeight: CGFloat? = 220
    /// Card-type accent supplied by the detail screen. Falls back to the active app theme.
    var chartAccent: Color? = nil
    /// Changing this value forces the panel to reload pricing (e.g. the detail footer's refresh button).
    var reloadToken: Int = 0

    // Scrydex variant keys (e.g. "holofoil", "normal")
    @State private var variantKeys: [String] = []
    @State private var selectedVariant: String? = nil

    // Grade keys available for the selected variant (e.g. "raw", "psa10")
    @State private var selectedGrade: String? = nil

    @State private var currentPrice: String = "—"
    @State private var livePriceUSD: Double?
    @State private var history: CardPriceHistory? = nil
    @State private var trends: CardPriceTrends? = nil  // single entry (first/best match)
    @State private var isLoading = false
    @State private var chartRange: ChartRange = .oneMonth
    @State private var scrubPoint: PriceDataPoint? = nil

    private var activeChartAccent: Color {
        if let chartAccent {
            return chartAccent
        }
        if let firstType = (card.elementTypes ?? []).compactMap({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).first(where: { !$0.isEmpty }),
           let accentColor = PokemonTypeBadge.backgroundAccent(for: firstType) {
            return accentColor
        }
        return services.theme.chartAccentColor
    }

    // All variant names present in history
    private var historyVariants: [String] {
        guard let history else { return [] }
        var seen: [String] = []
        for key in history.series.keys.sorted() {
            let variant = key.components(separatedBy: "/").first ?? key
            if variant == "default" { continue }
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

    private var resolvedChart: (points: [PriceDataPoint], resolution: ChartDataResolution) {
        let dailyWithToday = (chartSeries?.daily ?? []).pinningTodayPrice(livePriceUSD)
        let daily2 = Array(dailyWithToday.suffix(2))
        let daily7 = Array(dailyWithToday.suffix(7))
        let daily31 = Array(dailyWithToday.suffix(31))
        let weeklySource = chartSeries.flatMap { $0.weekly.isEmpty ? nil : $0.weekly } ?? weeklyFromDaily(dailyWithToday)
        let weekly13 = Array(weeklySource.suffix(13))
        let monthlySource = chartSeries.flatMap { $0.monthly.isEmpty ? nil : $0.monthly } ?? monthlyFromDaily(dailyWithToday)
        let monthly12 = Array(monthlySource.suffix(12))

        switch chartRange {
        case .oneDay:
            if !daily2.isEmpty { return (daily2, .daily) }
            if !daily7.isEmpty { return (daily7, .daily) }
            if !weekly13.isEmpty { return (weekly13, .weekly) }
        case .sevenDays:
            if !daily7.isEmpty { return (daily7, .daily) }
            if !weekly13.isEmpty { return (weekly13, .weekly) }
            if !monthly12.isEmpty { return (monthly12, .monthly) }
        case .oneMonth:
            if !daily31.isEmpty { return (daily31, .daily) }
            if !weekly13.isEmpty { return (weekly13, .weekly) }
            if !monthly12.isEmpty { return (monthly12, .monthly) }
        case .threeMonths:
            if !weekly13.isEmpty { return (weekly13, .weekly) }
            if !daily31.isEmpty { return (daily31, .daily) }
            if !monthly12.isEmpty { return (monthly12, .monthly) }
        case .oneYear:
            if !monthly12.isEmpty { return (monthly12, .monthly) }
            if !weekly13.isEmpty { return (weekly13, .weekly) }
            if !daily31.isEmpty { return (daily31, .daily) }
        case .all:
            if !dailyWithToday.isEmpty { return (dailyWithToday, .daily) }
            if !weeklySource.isEmpty { return (weeklySource, .weekly) }
            if !monthlySource.isEmpty { return (monthlySource, .monthly) }
        }
        return ([], .daily)
    }

    private func weeklyFromDaily(_ daily: [PriceDataPoint]) -> [PriceDataPoint] {
        let tuples = daily.map { [$0.label, String($0.price)] }
        return BucketDateMath.weeklyAverages(from: tuples, limit: 13).compactMap { pair in
            guard pair.count >= 2, let price = Double(pair[1]) else { return nil }
            return PriceDataPoint(id: pair[0], label: pair[0], price: price)
        }
    }

    private func monthlyFromDaily(_ daily: [PriceDataPoint]) -> [PriceDataPoint] {
        let tuples = daily.map { [$0.label, String($0.price)] }
        return BucketDateMath.monthlyAverages(from: tuples, limit: 12).compactMap { pair in
            guard pair.count >= 2, let price = Double(pair[1]) else { return nil }
            return PriceDataPoint(id: pair[0], label: pair[0], price: price)
        }
    }

    private var currentTrendChanges: (change1d: Double?, change7d: Double?, change30d: Double?)? {
        guard let trends, let variant = selectedVariant else { return nil }
        let grade = selectedGrade ?? "raw"
        return trends.changes(for: variant, grade: grade)
    }

    // Picker keys: merge history + Scrydex so labels like `specialIllustrationRare` (history) and `holofoil` (Scrydex) both appear.
    private var displayedVariants: [String] {
        if variantKeys.isEmpty { return historyVariants }
        if historyVariants.isEmpty { return variantKeys }
        var seen = Set<String>()
        var out: [String] = []
        for k in historyVariants + variantKeys where !seen.contains(k) {
            out.append(k)
            seen.insert(k)
        }
        return out
    }

    /// Show variant chips only when the catalog row includes a `variant` key.
    private var shouldShowVariantChips: Bool {
        guard !displayedVariants.isEmpty else { return false }
        if card.masterCardId.contains("::") {
            return card.pricingVariants != nil && !(card.pricingVariants?.isEmpty ?? true)
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scrubPoint != nil ? scrubLabel(scrubPoint!.label) : "Market Price")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .animation(.none, value: scrubPoint?.label)

                    Text(scrubPoint != nil ? services.priceDisplay.currency.format(amountUSD: scrubPoint!.price, usdToGbp: services.pricing.usdToGbp) : currentPrice)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .animation(.none, value: scrubPoint?.price)

                    if let dailyChange = currentTrendChanges?.change1d {
                        HStack(spacing: 5) {
                            Image(systemName: dailyChange >= 0 ? "arrow.up" : "arrow.down")
                            Text("\(String(format: "%.1f%%", abs(dailyChange))) today")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(dailyChange >= 0 ? PricingPanelPalette.success : PricingPanelPalette.danger)
                    }
                }

                Spacer(minLength: 0)
                variantAndGradeMenu
            }

            if !resolvedChart.points.isEmpty {
                chartRangePicker
                chartView
            } else if isLoading {
                ProgressView()
                    .tint(.primary)
                    .padding(.vertical, 24)
            } else {
                Spacer().frame(height: 16)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Group {
                if !useGlass {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(panelCardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .stroke(panelBorder, lineWidth: 1)
                        )
                }
            }
        )
        .task(id: card.masterCardId) {
            await load()
        }
        .task(id: reloadToken) {
            guard reloadToken != 0 else { return }
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
        .onChange(of: services.priceDisplay.currency) { _, _ in
            Task { await refreshPrice() }
        }
        .onChange(of: services.pricing.usdToGbp) { _, _ in
            Task { await refreshPrice() }
        }
    }

    @ViewBuilder
    private var variantAndGradeMenu: some View {
        if shouldShowVariantChips || !gradesForVariant.isEmpty {
            Menu {
                if shouldShowVariantChips {
                    Section("Variant") {
                        ForEach(displayedVariants, id: \.self) { key in
                            Button {
                                selectedVariant = key
                            } label: {
                                if selectedVariant == key {
                                    Label(variantDisplayName(key), systemImage: "checkmark")
                                } else {
                                    Text(variantDisplayName(key))
                                }
                            }
                        }
                    }
                }

                if !gradesForVariant.isEmpty {
                    Section("Grade") {
                        ForEach(gradesForVariant, id: \.self) { key in
                            Button {
                                selectedGrade = key
                            } label: {
                                if selectedGrade == key {
                                    Label(gradeDisplayName(key), systemImage: "checkmark")
                                } else {
                                    Text(gradeDisplayName(key))
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectionMenuTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(.primary)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
        }
    }

    private var selectionMenuTitle: String {
        let variant = selectedVariant.map(variantDisplayName) ?? "Variant"
        guard let selectedGrade else { return variant }
        return "\(variant) (\(gradeDisplayName(selectedGrade)))"
    }

    // MARK: - Chip styles (system adaptive — matches Settings-style pills)

    private func chipBackground(selected: Bool) -> Color {
        selected ? services.theme.accentColor : BindrGlassStyle.insetFill(colorScheme)
    }

    private func chipForeground(selected: Bool) -> Color {
        selected ? Color.white : Color.primary.opacity(0.9)
    }

    private var panelCardBackground: Color {
        colorScheme == .dark ? .black : .white
    }

    private var panelBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private var panelDivider: Color {
        BindrGlassStyle.insetBorder(colorScheme)
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
                            .background {
                                let isSelected = selected.wrappedValue == key
                                Capsule()
                                    .bindrAccentFill(chipBackground(selected: isSelected), usesLogoGradient: isSelected)
                            }
                            .foregroundStyle(chipForeground(selected: selected.wrappedValue == key))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private var chartRangePicker: some View {
        HStack(spacing: 0) {
            ForEach(ChartRange.selectable, id: \.self) { range in
                let isSelected = chartRange == range
                Button {
                    guard chartRange != range else { return }
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        chartRange = range
                    }
                    Haptics.lightImpact()
                } label: {
                    Text(range.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .primary.opacity(0.82))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if isSelected {
                                Capsule(style: .continuous)
                                    .fill(activeChartAccent)
                                    .shadow(
                                        color: activeChartAccent.opacity(0.20),
                                        radius: 4,
                                        y: 2
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Chart

    private var chartView: some View {
        let points = resolvedChart.points
        let prices = points.map(\.price)
        let minP = (prices.min() ?? 0) * 0.97
        let maxP = (prices.max() ?? 1) * 1.03
        return Chart(points) { point in
            AreaMark(
                x: .value("Date", point.label),
                yStart: .value("Min", minP),
                yEnd: .value("Price", point.price)
            )
            .interpolationMethod(.linear)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        activeChartAccent.opacity(0.70),
                        activeChartAccent.opacity(0.28),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Date", point.label),
                y: .value("Price", point.price)
            )
            .interpolationMethod(.linear)
            .foregroundStyle(activeChartAccent)
            .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        .chartYScale(domain: minP...maxP)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let plotAnchor = proxy.plotFrame {
                    let plotFrame = geo[plotAnchor]

                    // Scrub indicator drawn directly — no chart marks so layout never changes
                    if let scrub = scrubPoint, let xPos = proxy.position(forX: scrub.label) {
                        let x = xPos + plotFrame.origin.x
                        Rectangle()
                            .fill(panelDivider)
                            .frame(width: 1.5)
                            .frame(maxHeight: .infinity)
                            .offset(x: x - 0.75)
                            .allowsHitTesting(false)

                        if let yPos = proxy.position(forY: scrub.price) {
                            Circle()
                                .fill(activeChartAccent)
                                .frame(width: 8, height: 8)
                                .offset(x: x - 4, y: plotFrame.origin.y + yPos - 4)
                                .allowsHitTesting(false)
                        }
                    }

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
        }
        .modifier(ChartSizing(height: chartHeight))
        .padding(.horizontal, -16)
    }

    // Axis tick labels (short)
    private func truncatedLabel(_ label: String) -> String {
        switch resolvedChart.resolution {
        case .daily:
            // "2026-03-21" → "21/03"
            return dailyToShortUK(label)
        case .weekly:
            // "2026-W14" → "30/03"
            return weekLabelToShortUK(label)
        case .monthly:
            // "2026-03" → "Mar"
            return monthLabelToShort(label)
        }
    }

    // Scrub overlay label (full dd/mm/yy)
    private func scrubLabel(_ label: String) -> String {
        switch resolvedChart.resolution {
        case .daily:
            return dailyToFullUK(label)
        case .weekly:
            return weekLabelToFullUK(label)
        case .monthly:
            let parts = label.components(separatedBy: "-")
            guard parts.count == 2, let month = Int(parts[1]) else { return label }
            let fmt = DateFormatter()
            return "\(fmt.shortMonthSymbols[month - 1]) \(parts[0])"
        }
    }

    private func dailyToShortUK(_ label: String) -> String {
        // "2026-03-21" → "21/03"
        let parts = label.components(separatedBy: "-")
        guard parts.count == 3 else { return label }
        return "\(parts[2])/\(parts[1])"
    }

    private func dailyToFullUK(_ label: String) -> String {
        // "2026-03-21" → "21/03/26"
        let parts = label.components(separatedBy: "-")
        guard parts.count == 3, parts[0].count == 4 else { return label }
        let yy = String(parts[0].suffix(2))
        return "\(parts[2])/\(parts[1])/\(yy)"
    }

    private func weekLabelToShortUK(_ label: String) -> String {
        guard let date = weekLabelToDate(label) else { return label }
        let fmt = DateFormatter()
        fmt.dateFormat = "dd/MM"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: date)
    }

    private func weekLabelToFullUK(_ label: String) -> String {
        guard let date = weekLabelToDate(label) else { return label }
        let fmt = DateFormatter()
        fmt.dateFormat = "dd/MM/yy"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: date)
    }

    private func weekLabelToDate(_ label: String) -> Date? {
        // Format: "YYYY-Www"
        let parts = label.components(separatedBy: "-W")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let week = Int(parts[1]) else { return nil }
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(weekOfYear: week, yearForWeekOfYear: year))
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
                    .foregroundStyle(.secondary)
                Image(systemName: value >= 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 9, weight: .bold))
                Text(String(format: "%.1f%%", abs(value)))
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(value >= 0 ? PricingPanelPalette.success : PricingPanelPalette.danger)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill((value >= 0 ? PricingPanelPalette.success : PricingPanelPalette.danger).opacity(0.15))
            )
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
        variantKeys = keys.filter { $0 != "default" }
        history = hist
        trends = trnd

        // Derive available variants from history series keys
        var historyVariantsSeen: [String] = []
        for key in (hist?.series.keys ?? [:].keys) {
            let v = key.components(separatedBy: "/").first ?? key
            if v == "default" { continue }
            if !historyVariantsSeen.contains(v) { historyVariantsSeen.append(v) }
        }
        let scrydexKeys = Set(keys)

        // Pick default variant: prefer keys that exist in both history and Scrydex.
        let preferredVariants = ["holofoil", "normal", "reverseHolofoil"]
        let defaultVariant: String?
        if card.masterCardId.contains("::") {
            if let cv = card.pricingVariants?.first, !cv.isEmpty {
                if historyVariantsSeen.isEmpty || historyVariantsSeen.contains(cv) {
                    defaultVariant = cv
                } else {
                    defaultVariant = historyVariantsSeen.first ?? cv
                }
            } else {
                defaultVariant = historyVariantsSeen.first ?? keys.first
            }
        } else if !historyVariantsSeen.isEmpty, !scrydexKeys.isEmpty {
            defaultVariant = preferredVariants.first(where: { historyVariantsSeen.contains($0) && scrydexKeys.contains($0) })
                ?? historyVariantsSeen.first(where: { scrydexKeys.contains($0) })
                ?? preferredVariants.first(where: { scrydexKeys.contains($0) })
                ?? historyVariantsSeen.first
        } else if !historyVariantsSeen.isEmpty {
            defaultVariant = preferredVariants.first(where: { historyVariantsSeen.contains($0) }) ?? historyVariantsSeen.first
        } else {
            defaultVariant = preferredVariants.first(where: { keys.contains($0) }) ?? keys.first
        }
        selectedVariant = initialVariant ?? defaultVariant

        // Pick default grade directly (don't rely on onChange firing in time)
        let grades = gradesForSelectedVariant(variant: selectedVariant)
        selectedGrade = grades.first(where: { $0 == "raw" }) ?? grades.first

        await refreshPrice()
    }

    private func refreshPrice() async {
        currentPrice = "—"
        livePriceUSD = nil
        guard let variant = selectedVariant, !variant.isEmpty else { return }
        let grade = selectedGrade ?? "raw"
        if let usd = await services.pricing.usdPriceForVariantAndGrade(for: card, variantKey: variant, grade: grade) {
            livePriceUSD = usd
            currentPrice = services.priceDisplay.currency.format(amountUSD: usd, usdToGbp: services.pricing.usdToGbp)
            return
        }
        if let usd = await services.pricing.latestHistoryPriceUSD(for: card, variantKey: variant, grade: grade) {
            livePriceUSD = usd
            currentPrice = services.priceDisplay.currency.format(amountUSD: usd, usdToGbp: services.pricing.usdToGbp)
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

private enum PricingPanelPalette {
    static let chartLine = Color(red: 0.12, green: 0.52, blue: 1.0)
    static let success = Color(red: 0.28, green: 0.84, blue: 0.39)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.34)
}

/// Applies a fixed chart height, or lets the chart fill available vertical space when `height` is nil.
private struct ChartSizing: ViewModifier {
    let height: CGFloat?

    func body(content: Content) -> some View {
        if let height {
            content.frame(height: height)
        } else {
            content.frame(maxHeight: .infinity)
        }
    }
}
