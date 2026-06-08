import Foundation

struct UpcomingRelease: Identifiable, Decodable, Sendable, Equatable {
    let id: Int
    let name: String
    let type: String
    let releaseDate: Date
    let image: String

    private enum CodingKeys: String, CodingKey {
        case id, name, type, image
        case releaseDate = "release_date"
    }

    init(id: Int, name: String, type: String, releaseDate: Date, image: String) {
        self.id = id
        self.name = name
        self.type = type
        self.releaseDate = releaseDate
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
        guard let parsed = Self.releaseDateFormatter.date(from: rawDate.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw DecodingError.dataCorruptedError(
                forKey: .releaseDate,
                in: container,
                debugDescription: "Unrecognized release_date: \(rawDate)"
            )
        }
        releaseDate = parsed
    }

    var imageURL: URL? {
        AppConfiguration.upcomingReleaseImageURL(imageSrc: image)
    }

    private static let releaseDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}

enum UpcomingReleasesService {
    static func decode(_ data: Data) -> [UpcomingRelease]? {
        let decoder = JSONDecoder()
        guard let releases = try? decoder.decode([UpcomingRelease].self, from: data) else { return nil }
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
