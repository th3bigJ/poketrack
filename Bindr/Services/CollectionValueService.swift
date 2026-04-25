import Foundation
import SwiftData
import Observation

/// Computes and stores daily snapshots, completed-week averages, and completed-month averages.
///
/// Daily rules:
/// - No historical backfill.
/// - Capture at most one snapshot for today when the app runs.
///
/// Weekly rules:
/// - A week average is written once the week (Mon–Sun) is fully complete and the user opens
///   the app on or after the following Monday.
/// - The *current incomplete week* average is computed live from existing daily snapshots.
///
/// Monthly rules:
/// - A month average is written once the month is fully complete (user opens on or after the 1st
///   of the following month).
/// - The *current incomplete month* average is computed live from existing daily snapshots.
@Observable
@MainActor
final class CollectionValueService {
    private let modelContext: ModelContext
    private let pricing: PricingService
    private let cardData: CardDataService

    private(set) var snapshots: [CollectionValueSnapshot] = []
    private(set) var weeklyAverages: [CollectionWeeklyAverage] = []
    private(set) var monthlyAverages: [CollectionMonthlyAverage] = []
    private(set) var isBackfilling = false

    // MARK: - Live partial-period averages (current incomplete week / month)

    /// Average of daily snapshots in the current (incomplete) week, including today's live value if provided.
    func currentWeekAverage(liveToday: BrandSnapshot?) -> BrandSnapshot {
        let cal = weekCalendar
        let today = cal.startOfDay(for: Date())
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        let daysInWeek = snapshots.filter { $0.date >= weekStart && $0.date < today }
        return average(of: daysInWeek.map(\.asBrandSnapshot) + (liveToday.map { [$0] } ?? []))
    }

    /// Average of daily snapshots in the current (incomplete) month, including today's live value if provided.
    func currentMonthAverage(liveToday: BrandSnapshot?) -> BrandSnapshot {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let comps = cal.dateComponents([.year, .month], from: today)
        let monthStart = cal.date(from: comps)!
        let daysInMonth = snapshots.filter { $0.date >= monthStart && $0.date < today }
        return average(of: daysInMonth.map(\.asBrandSnapshot) + (liveToday.map { [$0] } ?? []))
    }

    // MARK: - Init

    init(modelContext: ModelContext, pricing: PricingService, cardData: CardDataService) {
        self.modelContext = modelContext
        self.pricing = pricing
        self.cardData = cardData
        loadAll()
    }

    // MARK: - Public entry point

    func runBackfillIfNeeded(collectionItems: [CollectionItem]) async {
        guard !isBackfilling else { return }
        purgeZeroValueSnapshots()
        await captureTodaySnapshotIfMissing(collectionItems: collectionItems)

        aggregateWeeklyIfNeeded()
        aggregateMonthlyIfNeeded()
        loadAll()
    }

    private func captureTodaySnapshotIfMissing(collectionItems: [CollectionItem]) async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard !snapshotExists(for: today) else { return }

        let hasInventory = collectionItems.contains { $0.quantity > 0 }
        guard hasInventory else {
            print("[CollectionValue] Skipping daily snapshot (no inventory).")
            return
        }

        isBackfilling = true
        let result = await computeValue(for: collectionItems, on: today)
        isBackfilling = false
        guard result.total > 0 else {
            print("[CollectionValue] Skipping daily snapshot (value is zero).")
            return
        }

        print("[CollectionValue] Saving snapshot for \(today.formatted(date: .abbreviated, time: .omitted)) → total=\(result.total)")
        let snapshot = CollectionValueSnapshot(
            date: today,
            totalGbp: result.total,
            pokemonGbp: result.pokemon,
            onePieceGbp: result.onePiece
        )
        modelContext.insert(snapshot)
        try? modelContext.save()
        loadAll()
    }

    // MARK: - Weekly aggregation

    private func aggregateWeeklyIfNeeded() {
        let cal = weekCalendar
        let today = cal.startOfDay(for: Date())
        // Current week start (Monday)
        let thisWeekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!

        // Find all completed weeks for which we have ≥1 daily snapshot but no stored average yet
        // Completed weeks = any week starting before thisWeekStart
        let allSnapshots = fetchAllSnapshots()
        guard !allSnapshots.isEmpty else { return }

        // Group snapshots by their ISO week start (Monday)
        var byWeek: [Date: [CollectionValueSnapshot]] = [:]
        for snap in allSnapshots {
            let ws = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: snap.date))!
            if ws < thisWeekStart {
                byWeek[ws, default: []].append(snap)
            }
        }

        let existingWeekStarts = Set(weeklyAverages.map {
            cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0.weekStart))!
        })

        for (weekStart, days) in byWeek {
            guard !existingWeekStarts.contains(weekStart) else { continue }
            let avg = average(of: days.map(\.asBrandSnapshot))
            let record = CollectionWeeklyAverage(
                weekStart: weekStart,
                totalGbp: avg.total,
                pokemonGbp: avg.pokemon,
                onePieceGbp: avg.onePiece
            )
            modelContext.insert(record)
            print("[CollectionValue] Saved weekly avg for week of \(weekStart.formatted(date: .abbreviated, time: .omitted)): \(avg.total)")
        }
        try? modelContext.save()
    }

    // MARK: - Monthly aggregation

    private func aggregateMonthlyIfNeeded() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let thisMonthComps = cal.dateComponents([.year, .month], from: today)
        let thisMonthStart = cal.date(from: thisMonthComps)!

        let allSnapshots = fetchAllSnapshots()
        guard !allSnapshots.isEmpty else { return }

        var byMonth: [Date: [CollectionValueSnapshot]] = [:]
        for snap in allSnapshots {
            let comps = cal.dateComponents([.year, .month], from: snap.date)
            let ms = cal.date(from: comps)!
            if ms < thisMonthStart {
                byMonth[ms, default: []].append(snap)
            }
        }

        let existingMonthStarts = Set(monthlyAverages.map {
            let comps = cal.dateComponents([.year, .month], from: $0.monthStart)
            return cal.date(from: comps)!
        })

        for (monthStart, days) in byMonth {
            guard !existingMonthStarts.contains(monthStart) else { continue }
            let avg = average(of: days.map(\.asBrandSnapshot))
            let record = CollectionMonthlyAverage(
                monthStart: monthStart,
                totalGbp: avg.total,
                pokemonGbp: avg.pokemon,
                onePieceGbp: avg.onePiece
            )
            modelContext.insert(record)
            print("[CollectionValue] Saved monthly avg for \(monthStart.formatted(date: .abbreviated, time: .omitted)): \(avg.total)")
        }
        try? modelContext.save()
    }

    private func snapshotExists(for date: Date) -> Bool {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        var descriptor = FetchDescriptor<CollectionValueSnapshot>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        descriptor.fetchLimit = 1
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    // MARK: - Value computation

    private func computeValue(for items: [CollectionItem], on date: Date) async -> BrandSnapshot {
        var pokemonItems: [CollectionItem] = []
        var onePieceItems: [CollectionItem] = []

        for item in items {
            switch TCGBrand.inferredFromMasterCardId(item.cardID) {
            case .pokemon:  pokemonItems.append(item)
            case .onePiece: onePieceItems.append(item)
            }
        }

        let pokemonItemsCopy = pokemonItems
        let onePieceItemsCopy = onePieceItems
        async let p = computeBrandValue(items: pokemonItemsCopy, on: date)
        async let o = computeBrandValue(items: onePieceItemsCopy, on: date)
        let (pv, ov) = await (p, o)
        return BrandSnapshot(total: pv + ov, pokemon: pv, onePiece: ov)
    }

    private func computeBrandValue(items: [CollectionItem], on date: Date) async -> Double {
        var total = 0.0
        for item in items {
            guard let card = await cardData.loadCard(masterCardId: item.cardID) else { continue }
            let grade = resolvedGradeKey(for: item)
            let usd = await usdPrice(for: card, variantKey: item.variantKey, grade: grade, on: date)
            total += usd * Double(item.quantity) * pricing.usdToGbp
        }
        return total
    }

    /// Maps a CollectionItem's grading fields to the pricing grade key used by PricingService.
    private func resolvedGradeKey(for item: CollectionItem) -> String {
        guard let company = item.gradingCompany else { return "raw" }
        switch company.uppercased() {
        case "PSA": return "psa10"
        case "ACE": return "ace10"
        default: return "raw"
        }
    }

    private func usdPrice(for card: Card, variantKey: String, grade: String, on date: Date) async -> Double {
        if let historicalPrice = await historicalUsdPrice(for: card, variantKey: variantKey, grade: grade, on: date) {
            return historicalPrice
        }
        return await pricing.usdPriceForVariantAndGrade(for: card, variantKey: variantKey, grade: grade) ?? 0
    }

    private func historicalUsdPrice(for card: Card, variantKey: String, grade: String, on date: Date) async -> Double? {
        guard let history = await pricing.priceHistory(for: card) else { return nil }

        let seriesKey = "\(variantKey)/\(grade)"
        let series = history.series[seriesKey]
            ?? history.series.first(where: { $0.key.hasPrefix(variantKey + "/") })?.value
            ?? history.series.values.first

        guard let dailySeries = series, !dailySeries.daily.isEmpty else { return nil }

        let cal = Calendar.current
        let targetDay = cal.startOfDay(for: date)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        var bestPoint: PriceDataPoint?
        var bestDiff: TimeInterval = .infinity

        for point in dailySeries.daily {
            guard let pointDate = dateFormatter.date(from: point.label) else { continue }
            let diff = abs(cal.startOfDay(for: pointDate).timeIntervalSince(targetDay))
            if diff < bestDiff { bestDiff = diff; bestPoint = point }
        }

        guard let point = bestPoint, bestDiff <= 14 * 24 * 3600 else { return nil }
        return point.price
    }

    // MARK: - Helpers

    private func average(of snapshots: [BrandSnapshot]) -> BrandSnapshot {
        guard !snapshots.isEmpty else { return BrandSnapshot(total: 0, pokemon: 0, onePiece: 0) }
        let count = Double(snapshots.count)
        return BrandSnapshot(
            total:    snapshots.map(\.total).reduce(0, +) / count,
            pokemon:  snapshots.map(\.pokemon).reduce(0, +) / count,
            onePiece: snapshots.map(\.onePiece).reduce(0, +) / count
        )
    }

    private func fetchAllSnapshots() -> [CollectionValueSnapshot] {
        let descriptor = FetchDescriptor<CollectionValueSnapshot>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// ISO week calendar: week starts Monday
    private var weekCalendar: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.locale = Locale.current
        cal.timeZone = TimeZone.current
        return cal
    }

    // MARK: - Load / purge

    private func purgeZeroValueSnapshots() {
        let descriptor = FetchDescriptor<CollectionValueSnapshot>(
            predicate: #Predicate { $0.totalGbp == 0 }
        )
        let zeros = (try? modelContext.fetch(descriptor)) ?? []
        guard !zeros.isEmpty else { return }
        print("[CollectionValue] Purging \(zeros.count) zero-value snapshot(s)")
        for s in zeros { modelContext.delete(s) }
        try? modelContext.save()
    }

    private func loadAll() {
        snapshots = fetchAllSnapshots()
        weeklyAverages = {
            let d = FetchDescriptor<CollectionWeeklyAverage>(
                sortBy: [SortDescriptor(\.weekStart, order: .forward)]
            )
            return (try? modelContext.fetch(d)) ?? []
        }()
        monthlyAverages = {
            let d = FetchDescriptor<CollectionMonthlyAverage>(
                sortBy: [SortDescriptor(\.monthStart, order: .forward)]
            )
            return (try? modelContext.fetch(d)) ?? []
        }()
    }
}

// MARK: - Shared value type

struct BrandSnapshot {
    var total: Double
    var pokemon: Double
    var onePiece: Double
}

extension CollectionValueSnapshot {
    var asBrandSnapshot: BrandSnapshot {
        BrandSnapshot(total: totalGbp, pokemon: pokemonGbp, onePiece: onePieceGbp)
    }
}
