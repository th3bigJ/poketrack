import Foundation
import SwiftData
import Observation

/// Computes and stores daily snapshots, completed-week averages, and completed-month averages.
///
/// Daily rules:
/// - Backfill missing snapshots for the last ~90 days using historical card prices.
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
/// Sendable value copies of SwiftData model objects — used for cross-actor transfer out of
/// background ModelContext fetches so the main thread is never blocked by SQLite reads.
struct SnapshotValue: Sendable {
    let date: Date
    let totalGbp: Double
    let pokemonGbp: Double
    let cardsGbp: Double
    let sealedGbp: Double
}

struct WeeklyAverageValue: Sendable {
    let weekStart: Date
    let totalGbp: Double
    let pokemonGbp: Double
    let cardsGbp: Double
    let sealedGbp: Double
}

struct MonthlyAverageValue: Sendable {
    let monthStart: Date
    let totalGbp: Double
    let pokemonGbp: Double
    let cardsGbp: Double
    let sealedGbp: Double
}

@Observable
@MainActor
final class CollectionValueService {
    private let modelContext: ModelContext
    private let modelContainer: ModelContainer
    private let pricing: PricingService
    private let cardData: CardDataService
    private let sealedProducts: SealedProductService

    private(set) var snapshots: [SnapshotValue] = []
    private(set) var weeklyAverages: [WeeklyAverageValue] = []
    private(set) var monthlyAverages: [MonthlyAverageValue] = []
    private(set) var isBackfilling = false

    /// Called after daily / weekly / monthly value history is persisted so the
    /// debounced R2 library snapshot stays current.
    var onValueHistoryChanged: (() -> Void)?

    private func notifyValueHistoryChanged() {
        onValueHistoryChanged?()
    }

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
        self.modelContainer = modelContext.container
        self.pricing = pricing
        self.cardData = cardData
        self.sealedProducts = sealedProducts
    }

    func loadAllFromStore() async {
        let container = modelContainer
        let (snaps, weekly, monthly) = await Task.detached(priority: .userInitiated) {
            let ctx = ModelContext(container)
            let snaps = (try? ctx.fetch(FetchDescriptor<CollectionValueSnapshot>(
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )))?.map {
                SnapshotValue(date: $0.date, totalGbp: $0.totalGbp, pokemonGbp: $0.pokemonGbp,
                              cardsGbp: $0.cardsGbp, sealedGbp: $0.sealedGbp)
            } ?? []
            let weekly = (try? ctx.fetch(FetchDescriptor<CollectionWeeklyAverage>(
                sortBy: [SortDescriptor(\.weekStart, order: .forward)]
            )))?.map {
                WeeklyAverageValue(weekStart: $0.weekStart, totalGbp: $0.totalGbp, pokemonGbp: $0.pokemonGbp,
                                   cardsGbp: $0.cardsGbp, sealedGbp: $0.sealedGbp)
            } ?? []
            let monthly = (try? ctx.fetch(FetchDescriptor<CollectionMonthlyAverage>(
                sortBy: [SortDescriptor(\.monthStart, order: .forward)]
            )))?.map {
                MonthlyAverageValue(monthStart: $0.monthStart, totalGbp: $0.totalGbp, pokemonGbp: $0.pokemonGbp,
                                    cardsGbp: $0.cardsGbp, sealedGbp: $0.sealedGbp)
            } ?? []
            return (snaps, weekly, monthly)
        }.value
        snapshots = snaps
        weeklyAverages = weekly
        monthlyAverages = monthly
    }

    // MARK: - Persisted last-known value (for yesterday's snapshot on new-day launch)

    private enum LastKnownValueKey {
        static let total   = "collectionValue.lastKnown.total"
        static let pokemon = "collectionValue.lastKnown.pokemon"
        static let cards = "collectionValue.lastKnown.cards"
        static let sealed = "collectionValue.lastKnown.sealed"
        static let date    = "collectionValue.lastKnown.date"
    }

    /// Returns the last in-memory value persisted when the app moved to the background today.
    /// Used only as a launch placeholder while live pricing is recomputed.
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
            cards: defaults.double(forKey: LastKnownValueKey.cards),
            sealed: defaults.double(forKey: LastKnownValueKey.sealed)
        )
    }

    /// Most recent daily snapshot strictly before today — used to sanity-check post-restore recomputes.
    func latestSnapshotTotalBeforeToday() -> Double? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return snapshots
            .filter { cal.startOfDay(for: $0.date) < today }
            .max(by: { $0.date < $1.date })?
            .totalGbp
    }

    func brandSnapshot(for date: Date) -> BrandSnapshot? {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        guard let snap = snapshots.first(where: { cal.startOfDay(for: $0.date) == day }),
              snap.totalGbp > 0 else { return nil }
        return BrandSnapshot(
            total: snap.totalGbp,
            pokemon: snap.pokemonGbp,
            cards: snap.cardsGbp,
            sealed: snap.sealedGbp
        )
    }

    /// Today's live market value using current catalog pricing (same path as saved daily snapshots).
    func computeLiveSnapshot(for collectionItems: [CollectionItem]) async -> BrandSnapshot? {
        await computeValue(for: collectionItems, on: Date(), allowLiveFallback: true)
    }

    /// Clears the persisted snapshot so the next call to `todayPersistedSnapshot()` returns nil
    /// and forces a full recompute. Call this after a daily pricing sync so stale pre-03:00 values
    /// saved earlier in the same calendar day do not short-circuit the recompute.
    func invalidatePersistedSnapshot() {
        UserDefaults.standard.removeObject(forKey: LastKnownValueKey.date)
    }

    /// Call this when the app moves to the background so the value is available on next launch.
    func persistLastKnownValue(_ snapshot: BrandSnapshot) {
        guard snapshot.total > 0 else { return }
        let defaults = UserDefaults.standard
        defaults.set(snapshot.total,   forKey: LastKnownValueKey.total)
        defaults.set(snapshot.pokemon, forKey: LastKnownValueKey.pokemon)
        defaults.set(snapshot.cards,   forKey: LastKnownValueKey.cards)
        defaults.set(snapshot.sealed,  forKey: LastKnownValueKey.sealed)
        defaults.set(Date(),           forKey: LastKnownValueKey.date)
    }

    private func saveYesterdaySnapshotFromPersistedValueIfNeeded() {
        let defaults = UserDefaults.standard
        guard let savedDate = defaults.object(forKey: LastKnownValueKey.date) as? Date else { return }
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date()))!
        guard cal.startOfDay(for: savedDate) == yesterday else { return }
        guard !snapshotExists(for: yesterday) else { return }

        let total   = defaults.double(forKey: LastKnownValueKey.total)
        let pokemon = defaults.double(forKey: LastKnownValueKey.pokemon)
        let cards   = defaults.double(forKey: LastKnownValueKey.cards)
        let sealed  = defaults.double(forKey: LastKnownValueKey.sealed)
        guard total > 0 else { return }

        let snapshot = CollectionValueSnapshot(
            date: yesterday,
            totalGbp: total,
            pokemonGbp: pokemon,
            onePieceGbp: 0,
            cardsGbp: cards,
            sealedGbp: sealed
        )
        modelContext.insert(snapshot)
        try? modelContext.save()
        loadAll()
        notifyValueHistoryChanged()
    }

    func runBackfillIfNeeded(
        collectionItems: [CollectionItem],
        preferredTodaySnapshot: BrandSnapshot? = nil
    ) async {
        guard !isBackfilling else { return }
        await sealedProducts.loadFromLocalIfAvailable()
        purgeZeroValueSnapshots()
        purgeSyntheticPreHistoryBackfill()
        saveYesterdaySnapshotFromPersistedValueIfNeeded()
        await captureTodaySnapshotIfMissing(
            collectionItems: collectionItems,
            preferredSnapshot: preferredTodaySnapshot
        )
        await backfillRecentDailySnapshotsIfNeeded(collectionItems: collectionItems)
        await fillSnapshotGapsIfNeeded(collectionItems: collectionItems)
        let freshSnapshots = fetchAllSnapshots()
        let weeklyChanged = aggregateWeeklyIfNeeded(using: freshSnapshots)
        let monthlyChanged = aggregateMonthlyIfNeeded(using: freshSnapshots)
        loadAll()
        if weeklyChanged || monthlyChanged {
            notifyValueHistoryChanged()
        }
    }

    /// Fills missing daily snapshots in the last ~90 days using historical prices for each day.
    /// Never creates snapshots before the user's oldest existing daily snapshot.
    private func backfillRecentDailySnapshotsIfNeeded(collectionItems: [CollectionItem]) async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let cutoff = cal.date(byAdding: .day, value: -BucketDateMath.dailyPricingHistoryDays, to: today)!

        guard let oldestExisting = snapshots.map({ cal.startOfDay(for: $0.date) }).min() else { return }

        let existingDays = Set(snapshots.map { cal.startOfDay(for: $0.date) })

        var cursor = max(cutoff, oldestExisting)
        var missingDays: [Date] = []
        while cursor <= yesterday {
            if !existingDays.contains(cursor) {
                missingDays.append(cursor)
            }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        guard !missingDays.isEmpty else { return }

        isBackfilling = true
        defer { isBackfilling = false }

        for date in missingDays {
            guard let value = await computeValue(
                for: collectionItems,
                on: date,
                allowLiveFallback: false
            ), value.total > 0 else { continue }
            let record = CollectionValueSnapshot(
                date: date,
                totalGbp: value.total,
                pokemonGbp: value.pokemon,
                onePieceGbp: 0,
                cardsGbp: value.cards,
                sealedGbp: value.sealed
            )
            modelContext.insert(record)
        }
        try? modelContext.save()
        loadAll()
        notifyValueHistoryChanged()
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

        isBackfilling = true
        defer { isBackfilling = false }

        for date in missingDays {
            guard let value = await computeValue(
                for: collectionItems,
                on: date,
                allowLiveFallback: false
            ), value.total > 0 else { continue }
            let record = CollectionValueSnapshot(
                date: date,
                totalGbp: value.total,
                pokemonGbp: value.pokemon,
                onePieceGbp: 0,
                cardsGbp: value.cards,
                sealedGbp: value.sealed
            )
            modelContext.insert(record)
        }
        try? modelContext.save()
        loadAll()
        notifyValueHistoryChanged()
    }

    /// Replaces today's snapshot with the given live value and re-aggregates weekly/monthly averages.
    /// Historical daily snapshots are left untouched — we only have ~90 days of per-card price history
    /// so recomputing older snapshots would silently overwrite them with today's prices anyway.
    func forceRecalculate(liveSnapshot: BrandSnapshot, collectionItems: [CollectionItem]) async {
        guard !isBackfilling, liveSnapshot.total > 0 else {
            return
        }
        isBackfilling = true
        defer { isBackfilling = false }

        // Replace today's snapshot with the fresh live value.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        purgeTodaySnapshot()
        let todayRecord = CollectionValueSnapshot(
            date: today,
            totalGbp: liveSnapshot.total,
            pokemonGbp: liveSnapshot.pokemon,
            onePieceGbp: 0,
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
        notifyValueHistoryChanged()
    }

    private func purgeAllSnapshots() {
        let all = fetchAllSnapshots()
        guard !all.isEmpty else { return }
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
        for s in toDelete { modelContext.delete(s) }
        try? modelContext.save()
    }

    private func purgeAllWeeklyAverages() {
        let descriptor = FetchDescriptor<CollectionWeeklyAverage>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        guard !all.isEmpty else { return }
        for r in all { modelContext.delete(r) }
        try? modelContext.save()
    }

    private func purgeAllMonthlyAverages() {
        let descriptor = FetchDescriptor<CollectionMonthlyAverage>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        guard !all.isEmpty else { return }
        for r in all { modelContext.delete(r) }
        try? modelContext.save()
    }

    /// Re-aggregates weekly and monthly averages from current daily snapshots and reloads.
    /// Call after updating today's snapshot to keep chart averages current.
    func aggregateCurrentPeriods() {
        let weeklyChanged = aggregateWeeklyIfNeeded()
        let monthlyChanged = aggregateMonthlyIfNeeded()
        loadAll()
        if weeklyChanged || monthlyChanged {
            notifyValueHistoryChanged()
        }
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
            onePieceGbp: 0,
            cardsGbp: snapshot.cards,
            sealedGbp: snapshot.sealed
        )
        modelContext.insert(record)
        try? modelContext.save()
        loadAll()
        notifyValueHistoryChanged()
        return true
    }

    private func captureTodaySnapshotIfMissing(
        collectionItems: [CollectionItem],
        preferredSnapshot: BrandSnapshot?
    ) async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        if let preferredSnapshot, preferredSnapshot.total > 0, snapshotExists(for: today) {
            _ = updateTodaySnapshot(preferredSnapshot)
            return
        }
        guard !snapshotExists(for: today) else { return }

        let hasInventory = collectionItems.contains { item in
            guard item.quantity > 0 else { return false }
            if item.itemKind == ProductKind.sealedProduct.rawValue {
                return item.sealedStatus != SealedInventoryStatus.opened.rawValue
            }
            return true
        }
        guard hasInventory else {
            return
        }

        let result: BrandSnapshot
        if let preferredSnapshot, preferredSnapshot.total > 0 {
            result = preferredSnapshot
        } else {
            isBackfilling = true
            guard let computed = await computeValue(for: collectionItems, on: today) else {
                isBackfilling = false
                return
            }
            result = computed
            isBackfilling = false
        }
        guard result.total > 0 else {
            return
        }

        let snapshot = CollectionValueSnapshot(
            date: today,
            totalGbp: result.total,
            pokemonGbp: result.pokemon,
            onePieceGbp: 0,
            cardsGbp: result.cards,
            sealedGbp: result.sealed
        )
        modelContext.insert(snapshot)
        try? modelContext.save()
        loadAll()
        notifyValueHistoryChanged()
    }

    // MARK: - Weekly aggregation

    @discardableResult
    private func aggregateWeeklyIfNeeded(using allSnapshots: [CollectionValueSnapshot]? = nil) -> Bool {
        let cal = weekCalendar

        let allSnapshots = allSnapshots ?? fetchAllSnapshots()
        guard !allSnapshots.isEmpty else { return false }

        var didChange = false

        // Group ALL snapshots by ISO week start, including the current week
        var byWeek: [Date: [CollectionValueSnapshot]] = [:]
        for snap in allSnapshots {
            let ws = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: snap.date))!
            byWeek[ws, default: []].append(snap)
        }

        // Build a lookup of existing records by week start so we can upsert.
        // Fetch live @Model objects here so we can mutate them through modelContext.
        let liveWeeklyRecords = (try? modelContext.fetch(FetchDescriptor<CollectionWeeklyAverage>())) ?? []
        var existingByWeekStart: [Date: CollectionWeeklyAverage] = [:]
        for record in liveWeeklyRecords {
            let ws = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: record.weekStart))!
            existingByWeekStart[ws] = record
        }

        for record in liveWeeklyRecords {
            let ws = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: record.weekStart))!
            if byWeek[ws] == nil {
                modelContext.delete(record)
                didChange = true
            }
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
                    existing.onePieceGbp = 0
                    existing.cardsGbp = avg.cards
                    existing.sealedGbp = avg.sealed
                    didChange = true
                }
            } else {
                let record = CollectionWeeklyAverage(
                    weekStart: weekStart,
                    totalGbp: avg.total,
                    pokemonGbp: avg.pokemon,
                    onePieceGbp: 0,
                    cardsGbp: avg.cards,
                    sealedGbp: avg.sealed
                )
                modelContext.insert(record)
                didChange = true
            }
        }
        guard didChange else { return false }
        try? modelContext.save()
        return true
    }

    // MARK: - Monthly aggregation

    @discardableResult
    private func aggregateMonthlyIfNeeded(using allSnapshots: [CollectionValueSnapshot]? = nil) -> Bool {
        let cal = Calendar.current

        let allSnapshots = allSnapshots ?? fetchAllSnapshots()
        guard !allSnapshots.isEmpty else { return false }

        var didChange = false

        // Group ALL snapshots by month start, including the current month
        var byMonth: [Date: [CollectionValueSnapshot]] = [:]
        for snap in allSnapshots {
            let comps = cal.dateComponents([.year, .month], from: snap.date)
            let ms = cal.date(from: comps)!
            byMonth[ms, default: []].append(snap)
        }

        // Build a lookup of existing records by month start so we can upsert.
        // Fetch live @Model objects here so we can mutate them through modelContext.
        let liveMonthlyRecords = (try? modelContext.fetch(FetchDescriptor<CollectionMonthlyAverage>())) ?? []
        var existingByMonthStart: [Date: CollectionMonthlyAverage] = [:]
        for record in liveMonthlyRecords {
            let comps = cal.dateComponents([.year, .month], from: record.monthStart)
            let ms = cal.date(from: comps)!
            existingByMonthStart[ms] = record
        }

        for record in liveMonthlyRecords {
            let comps = cal.dateComponents([.year, .month], from: record.monthStart)
            let ms = cal.date(from: comps)!
            if byMonth[ms] == nil {
                modelContext.delete(record)
                didChange = true
            }
        }

        for (monthStart, days) in byMonth {
            let avg = average(of: days.map(\.asBrandSnapshot))
            if let existing = existingByMonthStart[monthStart] {
                if abs(existing.totalGbp - avg.total) > 0.01 ||
                    abs(existing.cardsGbp - avg.cards) > 0.01 ||
                    abs(existing.sealedGbp - avg.sealed) > 0.01 {
                    existing.totalGbp = avg.total
                    existing.pokemonGbp = avg.pokemon
                    existing.onePieceGbp = 0
                    existing.cardsGbp = avg.cards
                    existing.sealedGbp = avg.sealed
                    didChange = true
                }
            } else {
                let record = CollectionMonthlyAverage(
                    monthStart: monthStart,
                    totalGbp: avg.total,
                    pokemonGbp: avg.pokemon,
                    onePieceGbp: 0,
                    cardsGbp: avg.cards,
                    sealedGbp: avg.sealed
                )
                modelContext.insert(record)
                didChange = true
            }
        }
        guard didChange else { return false }
        try? modelContext.save()
        return true
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

    private func computeValue(
        for items: [CollectionItem],
        on date: Date,
        allowLiveFallback: Bool = true
    ) async -> BrandSnapshot? {
        let pv = await computeBrandValue(
            items: items,
            brand: .pokemon,
            on: date,
            allowLiveFallback: allowLiveFallback
        )
        guard !pv.usedLiveFallback || allowLiveFallback else { return nil }
        return BrandSnapshot(
            total: pv.total,
            pokemon: pv.total,
            cards: pv.cards,
            sealed: pv.sealed
        )
    }

    private func computeBrandValue(
        items: [CollectionItem],
        brand: TCGBrand,
        on date: Date,
        allowLiveFallback: Bool = true
    ) async -> (total: Double, cards: Double, sealed: Double, usedLiveFallback: Bool) {
        var total = 0.0
        var cards = 0.0
        var sealed = 0.0
        var usedLiveFallback = false

        // Batch-load all non-sealed cards in a single SQLite query instead of one per item.
        let cardIDs = items.compactMap { item -> String? in
            guard item.quantity > 0 else { return nil }
            guard !(item.itemKind == ProductKind.sealedProduct.rawValue &&
                    item.sealedStatus == SealedInventoryStatus.opened.rawValue) else { return nil }
            guard sealedProductID(for: item) == nil else { return nil }
            return item.cardID
        }
        let loadedCards = await cardData.loadCards(masterCardIDs: cardIDs, catalogBrand: brand)
        let cardByID = Dictionary(loadedCards.map { ($0.masterCardId, $0) }, uniquingKeysWith: { f, _ in f })

        for item in items {
            guard item.quantity > 0 else { continue }
            if item.itemKind == ProductKind.sealedProduct.rawValue,
               item.sealedStatus == SealedInventoryStatus.opened.rawValue {
                continue
            }
            if let sealedProductID = sealedProductID(for: item) {
                guard allowLiveFallback,
                      let sealedPriceUSD = sealedProducts.marketPriceUSD(for: sealedProductID) else {
                    usedLiveFallback = true
                    continue
                }
                let gbp = sealedPriceUSD * Double(item.quantity) * pricing.usdToGbp
                total += gbp
                sealed += gbp
                continue
            }
            guard let card = cardByID[item.cardID] else { continue }
            let grade = resolvedGradeKey(for: item)
            let priceResult = await usdPrice(
                for: card,
                variantKey: item.variantKey,
                grade: grade,
                on: date,
                allowLiveFallback: allowLiveFallback
            )
            if priceResult.usedLiveFallback {
                usedLiveFallback = true
                if !allowLiveFallback { continue }
            }
            let gbp = priceResult.usd * Double(item.quantity) * pricing.usdToGbp
            total += gbp
            cards += gbp
        }
        return (total: total, cards: cards, sealed: sealed, usedLiveFallback: usedLiveFallback)
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

    private struct PriceResult {
        let usd: Double
        let usedLiveFallback: Bool
    }

    private func usdPrice(
        for card: Card,
        variantKey: String,
        grade: String,
        on date: Date,
        allowLiveFallback: Bool = true
    ) async -> PriceResult {
        if let historicalPrice = await historicalUsdPrice(for: card, variantKey: variantKey, grade: grade, on: date) {
            return PriceResult(usd: historicalPrice, usedLiveFallback: false)
        }
        guard allowLiveFallback else {
            return PriceResult(usd: 0, usedLiveFallback: true)
        }
        let live = await pricing.usdPriceForVariantAndGrade(for: card, variantKey: variantKey, grade: grade) ?? 0
        return PriceResult(usd: live, usedLiveFallback: live > 0)
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
        guard !snapshots.isEmpty else { return BrandSnapshot(total: 0, pokemon: 0, cards: 0, sealed: 0) }
        let count = Double(snapshots.count)
        return BrandSnapshot(
            total:   snapshots.map(\.total).reduce(0, +) / count,
            pokemon: snapshots.map(\.pokemon).reduce(0, +) / count,
            cards:   snapshots.map(\.cards).reduce(0, +) / count,
            sealed:  snapshots.map(\.sealed).reduce(0, +) / count
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
        for s in zeros { modelContext.delete(s) }
        try? modelContext.save()
    }

    /// Removes synthetic backfill snapshots that were created before the user's first real daily capture.
    ///
    /// Real snapshots captured by the app store `cardsGbp` and `sealedGbp` as zero until the split
    /// was added. Synthetic backfill writes both fields from historical pricing, so any snapshot
    /// dated before that first real capture with a non-zero cards/sealed split is false data.
    private func purgeSyntheticPreHistoryBackfill() {
        let cal = Calendar.current
        let legacySnapshots = snapshots.filter {
            $0.cardsGbp == 0 && $0.sealedGbp == 0 && $0.totalGbp > 0
        }
        guard let firstRealDay = legacySnapshots.map({ cal.startOfDay(for: $0.date) }).min() else {
            return
        }

        let descriptor = FetchDescriptor<CollectionValueSnapshot>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        let stale = all.filter { snapshot in
            cal.startOfDay(for: snapshot.date) < firstRealDay
                && (snapshot.cardsGbp > 0 || snapshot.sealedGbp > 0)
        }
        guard !stale.isEmpty else { return }

        for snapshot in stale {
            modelContext.delete(snapshot)
        }
        try? modelContext.save()
        loadAll()

        purgeAllWeeklyAverages()
        purgeAllMonthlyAverages()
        let freshSnapshots = fetchAllSnapshots()
        aggregateWeeklyIfNeeded(using: freshSnapshots)
        aggregateMonthlyIfNeeded(using: freshSnapshots)
        loadAll()
        notifyValueHistoryChanged()
    }

    private func loadAll() {
        snapshots = fetchAllSnapshots().map {
            SnapshotValue(date: $0.date, totalGbp: $0.totalGbp, pokemonGbp: $0.pokemonGbp,
                          cardsGbp: $0.cardsGbp, sealedGbp: $0.sealedGbp)
        }
        weeklyAverages = {
            let d = FetchDescriptor<CollectionWeeklyAverage>(
                sortBy: [SortDescriptor(\.weekStart, order: .forward)]
            )
            return ((try? modelContext.fetch(d)) ?? []).map {
                WeeklyAverageValue(weekStart: $0.weekStart, totalGbp: $0.totalGbp, pokemonGbp: $0.pokemonGbp,
                                   cardsGbp: $0.cardsGbp, sealedGbp: $0.sealedGbp)
            }
        }()
        monthlyAverages = {
            let d = FetchDescriptor<CollectionMonthlyAverage>(
                sortBy: [SortDescriptor(\.monthStart, order: .forward)]
            )
            return ((try? modelContext.fetch(d)) ?? []).map {
                MonthlyAverageValue(monthStart: $0.monthStart, totalGbp: $0.totalGbp, pokemonGbp: $0.pokemonGbp,
                                    cardsGbp: $0.cardsGbp, sealedGbp: $0.sealedGbp)
            }
        }()
    }

}

// MARK: - Shared value type

struct BrandSnapshot {
    var total: Double
    var pokemon: Double
    var cards: Double
    var sealed: Double
}

extension CollectionValueSnapshot {
    var asBrandSnapshot: BrandSnapshot {
        let hasExplicitSplit = cardsGbp > 0 || sealedGbp > 0
        return BrandSnapshot(
            total: totalGbp,
            pokemon: pokemonGbp,
            cards: hasExplicitSplit ? cardsGbp : totalGbp,
            sealed: hasExplicitSplit ? sealedGbp : 0
        )
    }
}

extension SnapshotValue {
    var asBrandSnapshot: BrandSnapshot {
        let hasExplicitSplit = cardsGbp > 0 || sealedGbp > 0
        return BrandSnapshot(
            total: totalGbp,
            pokemon: pokemonGbp,
            cards: hasExplicitSplit ? cardsGbp : totalGbp,
            sealed: hasExplicitSplit ? sealedGbp : 0
        )
    }
}
