import Foundation

/// One row in Library Storage → server download timestamps.
struct CatalogDownloadStatusEntry: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let lastDownloaded: Date?
    /// Extra context (row counts, pricing as-of date, etc.).
    let detail: String?
    /// Highlights rows that look missing or out of date for the current pricing period.
    let isStale: Bool
}

enum CatalogDownloadStatusSection: String, Sendable {
    case catalog = "Card catalog"
    case pricing = "Card pricing"
    case market = "Market data"
    case sealed = "Sealed products"
    case other = "Other"
}

struct CatalogDownloadStatus: Sendable, Equatable {
    let sections: [(section: CatalogDownloadStatusSection, entries: [CatalogDownloadStatusEntry])]
    let queriedAt: Date

    var isEmpty: Bool {
        sections.allSatisfy { $0.entries.isEmpty }
    }
}
