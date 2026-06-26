import Foundation
import os

/// Warms `URLCache` for upcoming card images so `CachedAsyncImage` can display
/// them instantly when cells scroll into view.
final class ImagePrefetcher: @unchecked Sendable {
    static let shared = ImagePrefetcher()

    /// Same pool as `CachedAsyncImage` so image traffic doesn't open two parallel session stacks to the CDN.
    private let session = AppURLSession.images
    private let maxInFlightRequests = 8

    private var inFlight: [URL: Task<Void, Never>] = [:]
    private let lock = OSAllocatedUnfairLock()

    private init() {}

    /// Start warming the cache for `urls`. Already-cached or in-flight URLs are skipped.
    func prefetch(_ urls: [URL], priority: TaskPriority = .low) {
        for url in urls {
            let task: Task<Void, Never>? = lock.withLock {
                guard inFlight[url] == nil else { return nil }
                guard inFlight.count < maxInFlightRequests else { return nil }
                let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
                guard AppURLSession.imageURLCache.cachedResponse(for: request) == nil else { return nil }
                let t = Task.detached(priority: priority) { [weak self] in
                    guard let self else { return }
                    do {
                        let (data, response) = try await self.session.data(for: request)
                        AppURLSession.imageURLCache.storeCachedResponse(
                            CachedURLResponse(response: response, data: data), for: request)
                    } catch {}
                    self.finish(url)
                }
                inFlight[url] = t
                return t
            }
            _ = task
        }
    }

    /// Cancel all in-flight prefetch tasks (e.g. on feed reshuffle).
    func cancelAll() {
        lock.withLock {
            inFlight.values.forEach { $0.cancel() }
            inFlight.removeAll()
        }
    }

    /// Cancel specific URLs (useful when swiping through detail view).
    func cancel(urls: [URL]) {
        lock.withLock {
            for url in urls {
                inFlight[url]?.cancel()
                inFlight[url] = nil
            }
        }
    }

    /// Prefetch a slice of card thumbnails, typically just ahead of the visible grid cells.
    func prefetchCardWindow(_ cards: [Card], startingAt startIndex: Int, count: Int = 12) {
        guard startIndex < cards.count else { return }
        let endIndex = min(startIndex + count, cards.count)
        let urls = cards[startIndex..<endIndex].map {
            AppConfiguration.imageURL(relativePath: $0.displayImageSrc)
        }
        prefetch(urls, priority: .background)
    }

    /// Prefetch high-res images for the current card and adjacent cards in detail view.
    /// The visible card is warmed at higher priority so hi-res can replace low-res quickly on open.
    func prefetchHighResForDetailView(_ cards: [Card], currentIndex: Int, window: Int = 2) {
        guard !cards.isEmpty, currentIndex >= 0, currentIndex < cards.count else { return }

        let start = max(0, currentIndex - window)
        let end = min(cards.count, currentIndex + window + 1)

        var adjacentURLs: [URL] = []
        for i in start..<end where i != currentIndex {
            adjacentURLs.append(highResURL(for: cards[i]))
        }

        prefetch([highResURL(for: cards[currentIndex])], priority: .userInitiated)
        prefetch(adjacentURLs, priority: .medium)
    }

    private func highResURL(for card: Card) -> URL {
        if let highSrc = card.imageHighSrc?.trimmingCharacters(in: .whitespacesAndNewlines), !highSrc.isEmpty {
            return AppConfiguration.imageURL(relativePath: highSrc)
        }
        return AppConfiguration.imageURL(relativePath: card.displayImageSrc)
    }

    /// Prefetch low-res thumbnails for the entire visible range immediately.
    /// Called on initial load to ensure instant display.
    func prefetchInitialBatch(_ cards: [Card], count: Int = 60) {
        let end = min(count, cards.count)
        let urls = cards[0..<end].map {
            AppConfiguration.imageURL(relativePath: $0.displayImageSrc)
        }
        prefetch(urls, priority: .userInitiated)
    }

    private func finish(_ url: URL) {
        lock.withLock {
            inFlight[url] = nil
        }
    }
}
