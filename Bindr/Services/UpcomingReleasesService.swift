import Foundation

struct UpcomingRelease: Identifiable, Decodable, Sendable, Equatable {
    let id: Int
    let name: String
    let type: String
    let releaseDate: Date
    /// When false, JSON only specified month/year (e.g. "August 2026") — show without a day in UI.
    let hasExactReleaseDay: Bool
    let image: String

    private enum CodingKeys: String, CodingKey {
        case id, name, type, image
        case releaseDate = "release_date"
    }

    init(id: Int, name: String, type: String, releaseDate: Date, hasExactReleaseDay: Bool = true, image: String) {
        self.id = id
        self.name = name
        self.type = type
        self.releaseDate = releaseDate
        self.hasExactReleaseDay = hasExactReleaseDay
        self.image = image
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(String.self, forKey: .type)
        image = try container.decode(String.self, forKey: .image)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let rawDate = try container.decode(String.self, forKey: .releaseDate)
        guard let parsed = Self.parseReleaseDate(rawDate) else {
            throw DecodingError.dataCorruptedError(
                forKey: .releaseDate,
                in: container,
                debugDescription: "Unrecognized release_date: \(rawDate)"
            )
        }
        releaseDate = parsed.date
        hasExactReleaseDay = parsed.hasExactDay
    }

    var imageURL: URL? {
        AppConfiguration.upcomingReleaseImageURL(imageSrc: image)
    }

    var releaseDateLabel: String {
        if hasExactReleaseDay {
            return releaseDate.formatted(.dateTime.month(.abbreviated).day().year())
        }
        return releaseDate.formatted(.dateTime.month(.wide).year())
    }

    var releaseDateAccessibilityLabel: String {
        if hasExactReleaseDay {
            return releaseDate.formatted(date: .long, time: .omitted)
        }
        return releaseDate.formatted(.dateTime.month(.wide).year())
    }

    /// Supports full RFC dates and month-only strings from `upcoming.json`.
    private static func parseReleaseDate(_ raw: String) -> (date: Date, hasExactDay: Bool)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let date = fullReleaseDateFormatter.date(from: trimmed) {
            return (date, true)
        }
        if let date = monthYearTimeReleaseDateFormatter.date(from: trimmed) {
            return (date, false)
        }
        if let date = monthYearReleaseDateFormatter.date(from: trimmed) {
            return (date, false)
        }
        if monthOnlyReleaseDateFormatter.date(from: trimmed) != nil {
            return (inferredMonthOnlyDate(from: trimmed), false)
        }
        return nil
    }

    private static func inferredMonthOnlyDate(from monthName: String) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        var utc = calendar
        utc.timeZone = TimeZone(secondsFromGMT: 0)!

        let monthToken = monthName.trimmingCharacters(in: .whitespacesAndNewlines)
        let reference = monthOnlyReleaseDateFormatter.date(from: monthToken) ?? Date()
        let targetMonth = utc.component(.month, from: reference)
        let now = Date()
        let currentMonth = utc.component(.month, from: now)
        let currentYear = utc.component(.year, from: now)
        var year = currentYear
        if targetMonth < currentMonth {
            year += 1
        }

        var components = DateComponents()
        components.year = year
        components.month = targetMonth
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return utc.date(from: components) ?? now
    }

    private static let fullReleaseDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    private static let monthYearTimeReleaseDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    private static let monthYearReleaseDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static let monthOnlyReleaseDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMMM"
        return formatter
    }()
}

enum UpcomingReleasesService {
    static func decode(_ data: Data) -> [UpcomingRelease]? {
        guard let elements = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }

        let decoder = JSONDecoder()
        var releases: [UpcomingRelease] = []
        releases.reserveCapacity(elements.count)

        for element in elements {
            guard let elementData = try? JSONSerialization.data(withJSONObject: element),
                  let release = try? decoder.decode(UpcomingRelease.self, from: elementData) else {
                continue
            }
            releases.append(release)
        }

        return releases.sorted {
            if $0.releaseDate != $1.releaseDate { return $0.releaseDate < $1.releaseDate }
            return $0.id < $1.id
        }
    }

    static func loadFromDailyBlob() async -> [UpcomingRelease] {
        guard let data = await CatalogStore.shared.dailyBlob(key: DailyBlobKey.upcomingReleases) else {
            return []
        }
        return decode(data) ?? []
    }

    /// Prefer the live CDN JSON so corrected `image` paths appear without waiting for the next daily sync.
    static func loadReleasesPreferringNetwork() async -> [UpcomingRelease] {
        let url = AppConfiguration.r2CatalogURL(path: DailyBlobPath.upcomingReleases)
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)

        guard let (data, response) = try? await AppURLSession.catalog.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              !data.isEmpty,
              let releases = decode(data) else {
            return await loadFromDailyBlob()
        }

        try? await CatalogStore.shared.upsertDailyBlob(key: DailyBlobKey.upcomingReleases, data: data)
        if let etag = http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "Etag") {
            try? await CatalogStore.shared.setMeta("daily_blob_http_etag_" + DailyBlobKey.upcomingReleases, etag)
        }
        return releases
    }
}
