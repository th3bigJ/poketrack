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
    private let sealedProducts: SealedProductService

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

    init(
        modelContext: ModelContext,
        pricing: PricingService,
        cardData: CardDataService,
        sealedProducts: SealedProductService
    ) {
        self.modelContext = modelContext
        self.pricing = pricing
        self.cardData = cardData
        self.sealedProducts = sealedProducts
    }

    func loadAllFromStore() {
        loadAll()
    }

    // MARK: - Persisted last-known value (for yesterday's snapshot on new-day launch)

    private enum LastKnownValueKey {
        static let total   = "collectionValue.lastKnown.total"
        static let pokemon = "collectionValue.lastKnown.pokemon"
        static let onePiece = "collectionValue.lastKnown.onePiece"
        static let cards = "collectionValue.lastKnown.cards"
        static let sealed = "collectionValue.lastKnown.sealed"
        static let date    = "collectionValue.lastKnown.date"
    }

    /// Returns the persisted value if it was saved today, so startup can skip a full recompute.
    func todayPersistedSnapshot() -> BrandSnapshot? {
        let defaults = UserDefaults.standard
        guard let savedDate = defaults.object(forKey: LastKnownValueKey.date) as? Date else { return nil }
        let cal = Calendar.current
        guard cal.isDateInToday(savedDate) else { return nil }
        let total = defaults.double(forKey: LastKnownValueKey.total)
        guard total > 0 else { return nil }
        return BrandSnapshot(
            total: total,
            pokemon: defaults.double(forKey: LastKnownValueKey.pokemon),
            onePiece: defaults.double(forKey: LastKnownValueKey.onePiece),
            cards: defaults.double(forKey: LastKnownValueKey.cards),
            sealed: defaults.double(forKey: LastKnownValueKey.sealed)
        )
    }

    /// Call this when the app moves to the background so the value is available on next launch.
    func persistLastKnownValue(_ snapshot: BrandSnapshot) {
        guard snapshot.total > 0 else { return }
        let defaults = UserDefaults.standard
        defaults.set(snapshot.total,    forKey: LastKnownValueKey.total)
        defaults.set(snapshot.pokemon,  forKey: LastKnownValueKey.pokemon)
        defaults.set(snapshot.onePiece, forKey: LastKnownValueKey.onePiece)
        defaults.set(snapshot.cards,    forKey: LastKnownValueKey.cards)
        defaults.set(snapshot.sealed,   forKey: LastKnownValueKey.sealed)
        defaults.set(Date(),            forKey: LastKnownValueKey.date)
    }

    private func saveYesterdaySnapshotFromPersistedValueIfNeeded() {
        let defaults = UserDefaults.standard
        guard let savedDate = defaults.object(forKey: LastKnownValueKey.date) as? Date else { return }
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date()))!
        guard cal.startOfDay(for: savedDate) == yesterday else { return }
        guard !snapshotExists(for: yesterday) else { return }

        let total    = defaults.double(forKey: LastKnownValueKey.total)
        let pokemon  = defaults.double(forKey: LastKnownValueKey.pokemon)
        let onePiece = defaults.double(forKey: LastKnownValueKey.onePiece)
        let cards    = defaults.double(forKey: LastKnownValueKey.cards)
        let sealed   = defaults.double(forKey: LastKnownValueKey.sealed)
        guard total > 0 else { return }

        print("[CollectionValue] Saving yesterday's snapshot from persisted value → \(yesterday.formatted(date: .abbreviated, time: .omitted)) total=\(total)")
        let snapshot = CollectionValueSnapshot(
            date: yesterday,
            totalGbp: total,
            pokemonGbp: pokemon,
            onePieceGbp: onePiece,
            cardsGbp: cards,
            sealedGbp: sealed
        )
        modelContext.insert(snapshot)
        try? modelContext.save()
        loadAll()
    }

    // MARK: - Public entry point

    func runBackfillIfNeeded(
        collectionItems: [CollectionItem],
        preferredTodaySnapshot: BrandSnapshot? = nil
    ) async {
        guard !isBackfilling else { return }
        let _t0 = ContinuousClock().now
        await sealedProducts.loadFromLocalIfAvailable()
        print("[CollectionValue] runBackfillIfNeeded: sealedProducts.loadFromLocal \(ContinuousClock().now - _t0)")
        let _t1 = ContinuousClock().now
        purgeZeroValueSnapshots()
        saveYesterdaySnapshotFromPersistedValueIfNeeded()
        print("[CollectionValue] runBackfillIfNeeded: purge+yesterday \(ContinuousClock().now - _t1)")
        let _t2 = ContinuousClock().now
        await captureTodaySnapshotIfMissing(
            collectionItems: collectionItems,
            preferredSnapshot: preferredTodaySnapshot
        )
        print("[CollectionValue] runBackfillIfNeeded: captureTodaySnapshot \(ContinuousClock().now - _t2)")
        let _t3 = ContinuousClock().now
        await fillSnapshotGapsIfNeeded(collectionItems: collectionItems)
        print("[CollectionValue] runBackfillIfNeeded: fillGaps \(ContinuousClock().now - _t3)")
        let _t4 = ContinuousClock().now
        let freshSnapshots = fetchAllSnapshots()
        aggregateWeeklyIfNeeded(using: freshSnapshots)
        aggregateMonthlyIfNeeded(using: freshSnapshots)
        loadAll()
        print("[CollectionValue] runBackfillIfNeeded: aggregate+load \(ContinuousClock().now - _t4)")
    }

    /// Fills gaps between the oldest existing snapshot and yesterday using the closest available
    /// historical price. This recovers days lost if snapshots were accidentally deleted — the values
    /// won't be exact (they use today's card prices) but restore chart continuity.
    private func fillSnapshotGapsIfNeeded(collectionItems: [CollectionItem]) async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        // Only fill if we have at least one existing snapshot to anchor from
        guard let oldest = snapshots.map({ cal.startOfDay(for: $0.date) }).min(),
              oldest < yesterday else { return }

        let existingDays = Set(snapshots.map { cal.startOfDay(for: $0.date) })

        // Collect all days between oldest snapshot and yesterday that are missing
        var cursor = oldest
        var missingDays: [Date] = []
        while cursor <= yesterday {
            if !existingDays.contains(cursor) {
                missingDays.append(cursor)
            }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        guard !missingDays.isEmpty else { return }

        print("[CollectionValue] Filling \(missingDays.count) missing snapshot gap(s)")
        isBackfilling = true
        defer { isBackfilling = false }

        for date in missingDays {
            let value = await computeValue(for: collectionItems, on: date)
            guard value.total > 0 else { continue }
            let record = CollectionValueSnapshot(
                date: date,
                totalGbp: value.total,
                pokemonGbp: value.pokemon,
                onePieceGbp: value.onePiece,
                cardsGbp: value.cards,
                sealedGbp: value.sealed
            )
            modelContext.insert(record)
        }
        try? modelContext.save()
        loadAll()
    }

    /// Replaces today's snapshot with the given live value and re-aggregates weekly/monthly averages.
    /// Historical daily snapshots are left untouched — we only have 31 days of per-card price history
    /// so recomputing older snapshots would silently overwrite them with today's prices anyway.
    func forceRecalculate(liveSnapshot: BrandSnapshot, collectionItems: [CollectionItem]) async {
        guard !isBackfilling, liveSnapshot.total > 0 else {
            print("[CollectionValue] forceRecalculate skipped — isBackfilling=\(isBackfilling) total=\(liveSnapshot.total)")
            return
        }
        isBackfilling = true
        defer { isBackfilling = false }
        print("[CollectionValue] forceRecalculate starting — snapshots=\(snapshots.count) weekly=\(weeklyAverages.count) monthly=\(monthlyAverages.count)")

        // Replace today's snapshot with the fresh live value.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        purgeTodaySnapshot()
        let todayRecord = CollectionValueSnapshot(
            date: today,
            totalGbp: liveSnapshot.total,
            pokemonGbp: liveSnapshot.pokemon,
            onePieceGbp: liveSnapshot.onePiece,
            cardsGbp: liveSnapshot.cards,
            sealedGbp: liveSnapshot.sealed
        )
        modelContext.insert(todayRecord)
        try? modelContext.save()
        loadAll()

        // Re-aggregate weekly/monthly from the full set of daily snapshots (history intact + new today).
        purgeAllWeeklyAverages()
        purgeAllMonthlyAverages()
        let freshSnapshots = fetchAllSnapshots()
        aggregateWeeklyIfNeeded(using: freshSnapshots)
        aggregateMonthlyIfNeeded(using: freshSnapshots)
        loadAll()
        print("[CollectionValue] forceRecalculate done — snapshots=\(snapshots.count) weekly=\(weeklyAverages.count) monthly=\(monthlyAverages.count)")
    }

    private func purgeAllSnapshots() {
        let all = fetchAllSnapshots()
        guard !all.isEmpty else { return }
        print("[CollectionValue] Purging \(all.count) daily snapshot(s) for recomputation")
        for s in all { modelContext.delete(s) }
        try? modelContext.save()
    }

    private func purgeTodaySnapshot() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: today)!
        let descriptor = FetchDescriptor<CollectionValueSnapshot>(
            predicate: #Predicate { $0.date >= today && $0.date < end }
        )
        let toDelete = (try? modelContext.fetch(descriptor)) ?? []
        guard !toDelete.isEmpty else { return }
        print("[CollectionValue] Purging \(toDelete.count) today snapshot(s) for recalculation")
        for s in toDelete { modelContext.delete(s) }
        try? modelContext.save()
    }

    private func purgeAllWeeklyAverages() {
        let descriptor = FetchDescriptor<CollectionWeeklyAverage>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        guard !all.isEmpty else { return }
        print("[CollectionValue] Purging \(all.count) weekly average(s) for recalculation")
        for r in all { modelContext.delete(r) }
        try? modelContext.save()
    }

    private func purgeAllMonthlyAverages() {
        let descriptor = FetchDescriptor<CollectionMonthlyAverage>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        guard !all.isEmpty else { return }
        print("[CollectionValue] Purging \(all.count) monthly average(s) for recalculation")
        for r in all { modelContext.delete(r) }
        try? modelContext.save()
    }

    /// Re-aggregates weekly and monthly averages from current daily snapshots and reloads.
    /// Call after updating today's snapshot to keep chart averages current.
    func aggregateCurrentPeriods() {
        aggregateWeeklyIfNeeded()
        aggregateMonthlyIfNeeded()
        loadAll()
    }

    /// Updates today's snapshot to the given value if it has changed by more than 1p.
    /// Returns true if the snapshot was actually written (value changed or didn't exist).
    @discardableResult
    func updateTodaySnapshot(_ snapshot: BrandSnapshot) -> Bool {
        guard snapshot.total > 0 else { return false }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Only write if value moved by more than £0.01 to avoid constant SwiftData churn
        if let existing = snapshots.first(where: { cal.startOfDay(for: $0.date) == today }),
           abs(existing.totalGbp - snapshot.total) <= 0.01 {
            return false
        }
        purgeTodaySnapshot()
        let record = CollectionValueSnapshot(
            date: today,
            totalGbp: snapshot.total,
            pokemonGbp: snapshot.pokemon,
            onePieceGbp: snapshot.onePiece,
            cardsGbp: snapshot.cards,
            sealedGbp: snapshot.sealed
        )
        modelContext.insert(record)
        try? modelContext.save()
        loadAll()
        return true
    }

    private func captureTodaySnapshotIfMissing(
        collectionItems: [CollectionItem],
        preferredSnapshot: BrandSnapshot?
    ) async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard !snapshotExists(for: today) else { return }

        let hasInventory = collectionItems.contains { item in
            guard item.quantity > 0 else { return false }
            if item.itemKind == ProductKind.sealedProduct.rawValue {
                return item.sealedStatus != SealedInventoryStatus.opened.rawValue
            }
            return true
        }
        guard hasInventory else {
            print("[CollectionValue] Skipping daily snapshot (no inventory).")
            return
        }

        let result: BrandSnapshot
        if let preferredSnapshot, preferredSnapshot.total > 0 {
            result = preferredSnapshot
        } else {
            isBackfilling = true
            result = await computeValue(for: collectionItems, on: today)
            isBackfilling = false
        }
        guard result.total > 0 else {
            print("[CollectionValue] Skipping daily snapshot (value is zero).")
            return
        }

        print("[CollectionValue] Saving snapshot for \(today.formatted(date: .abbreviated, time: .omitted)) → total=\(result.total)")
        let snapshot = CollectionValueSnapshot(
            date: today,
            totalGbp: result.total,
            pokemonGbp: result.pokemon,
            onePieceGbp: result.onePiece,
            cardsGbp: result.cards,
            sealedGbp: result.sealed
        )
        modelContext.insert(snapshot)
        try? modelContext.save()
        loadAll()
    }

    // MARK: - Weekly aggregation

    private func aggregateWeeklyIfNeeded(using allSnapshots: [CollectionValueSnapshot]? = nil) {
        let cal = weekCalendar

        let allSnapshots = allSnapshots ?? fetchAllSnapshots()
        guard !allSnapshots.isEmpty else { return }

        // Group ALL snapshots by ISO week start, including the current week
        var byWeek: [Date: [CollectionValueSnapshot]] = [:]
        for snap in allSnapshots {
            let ws = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: snap.date))!
            byWeek[ws, default: []].append(snap)
        }

        // Build a lookup of existing records by week start so we can upsert
        var existingByWeekStart: [Date: CollectionWeeklyAverage] = [:]
        for record in weeklyAverages {
            let ws = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: record.weekStart))!
            existingByWeekStart[ws] = record
        }

        for (weekStart, days) in byWeek {
            let avg = average(of: days.map(\.asBrandSnapshot))
            if let existing = existingByWeekStart[weekStart] {
                // Only update if value changed meaningfully (avoids constant churn on current week)
                if abs(existing.totalGbp - avg.total) > 0.01 ||
                    abs(existing.cardsGbp - avg.cards) > 0.01 ||
                    abs(existing.sealedGbp - avg.sealed) > 0.01 {
                    existing.totalGbp = avg.total
                    existing.pokemonGbp = avg.pokemon
                    existing.onePieceGbp = avg.onePiece
                    existing.cardsGbp = avg.cards
                    existing.sealedGbp = avg.sealed
                    print("[CollectionValue] Updated weekly avg for week of \(weekStart.formatted(date: .abbreviated, time: .omitted)): \(avg.total)")
                }
            } else {
                let record = CollectionWeeklyAverage(
                    weekStart: weekStart,
                    totalGbp: avg.total,
                    pokemonGbp: avg.pokemon,
                    onePieceGbp: avg.onePiece,
                    cardsGbp: avg.cards,
                    sealedGbp: avg.sealed
                )
                modelContext.insert(record)
                print("[CollectionValue] Saved weekly avg for week of \(weekStart.formatted(date: .abbreviated, time: .omitted)): \(avg.total)")
            }
        }
        try? modelContext.save()
    }

    // MARK: - Monthly aggregation

    private func aggregateMonthlyIfNeeded(using allSnapshots: [CollectionValueSnapshot]? = nil) {
        let cal = Calendar.current

        let allSnapshots = allSnapshots ?? fetchAllSnapshots()
        guard !allSnapshots.isEmpty else { return }

        // Group ALL snapshots by month start, including the current month
        var byMonth: [Date: [CollectionValueSnapshot]] = [:]
        for snap in allSnapshots {
            let comps = cal.dateComponents([.year, .month], from: snap.date)
            let ms = cal.date(from: comps)!
            byMonth[ms, default: []].append(snap)
        }

        // Build a lookup of existing records by month start so we can upsert
        var existingByMonthStart: [Date: CollectionMonthlyAverage] = [:]
        for record in monthlyAverages {
            let comps = cal.dateComponents([.year, .month], from: record.monthStart)
            let ms = cal.date(from: comps)!
            existingByMonthStart[ms] = record
        }

        for (monthStart, days) in byMonth {
            let avg = average(of: days.map(\.asBrandSnapshot))
            if let existing = existingByMonthStart[monthStart] {
                if abs(existing.totalGbp - avg.total) > 0.01 ||
                    abs(existing.cardsGbp - avg.cards) > 0.01 ||
                    abs(existing.sealedGbp - avg.sealed) > 0.01 {
                    existing.totalGbp = avg.total
                    existing.pokemonGbp = avg.pokemon
                    existing.onePieceGbp = avg.onePiece
                    existing.cardsGbp = avg.cards
                    existing.sealedGbp = avg.sealed
                    print("[CollectionValue] Updated monthly avg for \(monthStart.formatted(date: .abbreviated, time: .omitted)): \(avg.total)")
                }
            } else {
                let record = CollectionMonthlyAverage(
                    monthStart: monthStart,
                    totalGbp: avg.total,
                    pokemonGbp: avg.pokemon,
                    onePieceGbp: avg.onePiece,
                    cardsGbp: avg.cards,
                    sealedGbp: avg.sealed
                )
                modelContext.insert(record)
                print("[CollectionValue] Saved monthly avg for \(monthStart.formatted(date: .abbreviated, time: .omitted)): \(avg.total)")
            }
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
        return BrandSnapshot(
            total: pv.total + ov.total,
            pokemon: pv.total,
            onePiece: ov.total,
            cards: pv.cards + ov.cards,
            sealed: pv.sealed + ov.sealed
        )
    }

    private func computeBrandValue(items: [CollectionItem], on date: Date) async -> (total: Double, cards: Double, sealed: Double) {
        var total = 0.0
        var cards = 0.0
        var sealed = 0.0
        for item in items {
            guard item.quantity > 0 else { continue }
            if item.itemKind == ProductKind.sealedProduct.rawValue,
               item.sealedStatus == SealedInventoryStatus.opened.rawValue {
                continue
            }
            if let sealedProductID = sealedProductID(for: item),
               let sealedPriceUSD = sealedProducts.marketPriceUSD(for: sealedProductID) {
                let gbp = sealedPriceUSD * Double(item.quantity) * pricing.usdToGbp
                total += gbp
                sealed += gbp
                continue
            }
            guard let card = await cardData.loadCard(masterCardId: item.cardID) else { continue }
            let grade = resolvedGradeKey(for: item)
            let usd = await usdPrice(for: card, variantKey: item.variantKey, grade: grade, on: date)
            let gbp = usd * Double(item.quantity) * pricing.usdToGbp
            total += gbp
            cards += gbp
        }
        return (total: total, cards: cards, sealed: sealed)
    }

    private func sealedProductID(for item: CollectionItem) -> Int? {
        if let rawID = item.sealedProductId,
           let productID = Int(rawID),
           productID > 0 {
            return productID
        }
        return SealedProduct.parseCollectionProductID(item.cardID)
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

        guard let dailySeries = series, !dailySeries.daily.isEmpty else { return nil }

        let cal = Calendar.current
        let targetDay = cal.startOfDay(for: date)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        for point in dailySeries.daily {
            guard let pointDate = dateFormatter.date(from: point.label) else { continue }
            if cal.startOfDay(for: pointDate) == targetDay {
                return point.price
            }
        }

        // No exact-day history point; caller falls back to current live price for consistency.
        return nil
    }

    // MARK: - Helpers

    private func average(of snapshots: [BrandSnapshot]) -> BrandSnapshot {
        guard !snapshots.isEmpty else { return BrandSnapshot(total: 0, pokemon: 0, onePiece: 0, cards: 0, sealed: 0) }
        let count = Double(snapshots.count)
        return BrandSnapshot(
            total:    snapshots.map(\.total).reduce(0, +) / count,
            pokemon:  snapshots.map(\.pokemon).reduce(0, +) / count,
            onePiece: snapshots.map(\.onePiece).reduce(0, +) / count,
            cards:    snapshots.map(\.cards).reduce(0, +) / count,
            sealed:   snapshots.map(\.sealed).reduce(0, +) / count
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
    var cards: Double
    var sealed: Double
}

extension CollectionValueSnapshot {
    var asBrandSnapshot: BrandSnapshot {
        let hasExplicitSplit = cardsGbp > 0 || sealedGbp > 0
        return BrandSnapshot(
            total: totalGbp,
            pokemon: pokemonGbp,
            onePiece: onePieceGbp,
            cards: hasExplicitSplit ? cardsGbp : totalGbp,
            sealed: hasExplicitSplit ? sealedGbp : 0
        )
    }
}
