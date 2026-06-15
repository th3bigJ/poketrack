import Foundation

/// Static date-key helpers shared across pricing sync phases.
enum BucketDateMath {

    static func todayUTCKey(now: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func setCodeFromCardId(_ cardId: String) -> String {
        guard let dash = cardId.lastIndex(of: "-") else { return cardId }
        return String(cardId[..<dash])
    }

    /// Collapses `me04` → `me4` so daily bucket set stems align with catalog `setCode`.
    static func normalizedSetCode(_ setCode: String) -> String {
        let lower = setCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let regex = try? NSRegularExpression(pattern: #"^([a-z]+)(\d+)$"#, options: []),
              let m = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              m.numberOfRanges == 3,
              let r1 = Range(m.range(at: 1), in: lower),
              let r2 = Range(m.range(at: 2), in: lower),
              let n = Int(String(lower[r2]))
        else { return lower }
        return "\(String(lower[r1]))\(n)"
    }

    static func isoWeekKey(from dateKey: String) -> String? {
        guard dateKey.count == 10 else { return nil }
        let parts = dateKey.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let date = cal.date(from: comps) else { return nil }
        let isoYear = cal.component(.yearForWeekOfYear, from: date)
        let isoWeek = cal.component(.weekOfYear, from: date)
        return String(format: "%04d-W%02d", isoYear, isoWeek)
    }

    static func monthKey(from dateKey: String) -> String? {
        guard dateKey.count >= 7 else { return nil }
        return String(dateKey.prefix(7))
    }

    /// Rolling window of daily price buckets kept locally (~3 months).
    static let dailyPricingHistoryDays = 90

    static func lastDailyKeys(count: Int, relativeTo now: Date = Date()) -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return (0..<count).compactMap { offset -> String? in
            guard let date = cal.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let comps = cal.dateComponents([.year, .month, .day], from: date)
            guard let y = comps.year, let m = comps.month, let d = comps.day else { return nil }
            return String(format: "%04d-%02d-%02d", y, m, d)
        }.reversed()
    }

    static func last31DailyKeys(relativeTo now: Date = Date()) -> [String] {
        lastDailyKeys(count: 31, relativeTo: now)
    }

    static func last90DailyKeys(relativeTo now: Date = Date()) -> [String] {
        lastDailyKeys(count: dailyPricingHistoryDays, relativeTo: now)
    }

    static func allWeeklyKeys(from startYear: Int, relativeTo now: Date = Date()) -> [String] {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.weekOfYear = 1
        comps.yearForWeekOfYear = startYear
        guard var cursor = cal.date(from: comps) else { return [] }
        let currentWeekKey = isoWeekKey(from: todayUTCKey(now: now)) ?? ""
        var keys: [String] = []
        while let key = isoWeekKey(from: {
            let c = cal.dateComponents([.year, .month, .day], from: cursor)
            return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        }()), key <= currentWeekKey {
            if keys.last != key { keys.append(key) }
            guard let next = cal.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }
        return keys
    }

    static func allMonthlyKeys(from startYear: Int, relativeTo now: Date = Date()) -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = startYear; comps.month = 1; comps.day = 1
        guard var cursor = cal.date(from: comps) else { return [] }
        let todayComps = cal.dateComponents([.year, .month], from: now)
        let currentKey = String(format: "%04d-%02d", todayComps.year!, todayComps.month!)
        var keys: [String] = []
        while true {
            let c = cal.dateComponents([.year, .month], from: cursor)
            let key = String(format: "%04d-%02d", c.year!, c.month!)
            guard key <= currentKey else { break }
            keys.append(key)
            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return keys
    }

    static func weeklyAverages(from daily: [[String]], limit: Int) -> [[String]] {
        var totals: [String: (sum: Double, count: Int)] = [:]
        for point in daily {
            guard point.count == 2, let wk = isoWeekKey(from: point[0]), let p = Double(point[1]) else { continue }
            totals[wk, default: (0, 0)].sum += p
            totals[wk, default: (0, 0)].count += 1
        }
        return totals
            .map { (k, v) in [k, String(v.sum / Double(v.count))] }
            .sorted { $0[0] < $1[0] }
            .suffix(limit)
            .map { $0 }
    }

    static func monthlyAverages(from daily: [[String]], limit: Int) -> [[String]] {
        var totals: [String: (sum: Double, count: Int)] = [:]
        for point in daily {
            guard point.count == 2, let mk = monthKey(from: point[0]), let p = Double(point[1]) else { continue }
            totals[mk, default: (0, 0)].sum += p
            totals[mk, default: (0, 0)].count += 1
        }
        return totals
            .map { (k, v) in [k, String(v.sum / Double(v.count))] }
            .sorted { $0[0] < $1[0] }
            .suffix(limit)
            .map { $0 }
    }
}
