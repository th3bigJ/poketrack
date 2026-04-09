import Foundation

/// Warms `URLCache` for upcoming card images so `CachedAsyncImage` can display
/// them instantly when cells scroll into view.
final class ImagePrefetcher: @unchecked Sendable {
    static let shared = ImagePrefetcher()

    /// Same pool as `CachedAsyncImage` so image traffic doesn’t open two parallel session stacks to the CDN.
    private let session = AppURLSession.images

    private var inFlight: [URL: Task<Void, Never>] = [:]
    private let lock = NSLock()

    private init() {}

    /// Start warming the cache for `urls`. Already-cached or in-flight URLs are skipped.
    func prefetch(_ urls: [URL]) {
        for url in urls {
            lock.lock()
            guard inFlight[url] == nil else { lock.unlock(); continue }
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
            if URLCache.shared.cachedResponse(for: request) != nil {
                lock.unlock()
                continue
            }
            let task = Task.detached(priority: .low) { [weak self] in
                guard let self else { return }
                do {
                    let (data, response) = try await self.session.data(for: request)
                    URLCache.shared.storeCachedResponse(
                        CachedURLResponse(response: response, data: data), for: request)
                } catch {}
                self.finish(url)
            }
            inFlight[url] = task
            lock.unlock()
        }
    }

    /// Cancel all in-flight prefetch tasks (e.g. on feed reshuffle).
    func cancelAll() {
        lock.lock()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        lock.unlock()
    }

    /// Prefetch a slice of card thumbnails, typically just ahead of the visible grid cells.
    func prefetchCardWindow(_ cards: [Card], startingAt startIndex: Int, count: Int = 18) {
        guard startIndex < cards.count else { return }
        let endIndex = min(startIndex + count, cards.count)
        let urls = cards[startIndex..<endIndex].map {
            AppConfiguration.imageURL(relativePath: $0.imageLowSrc)
        }
        prefetch(urls)
    }

    private func finish(_ url: URL) {
        lock.lock()
        inFlight[url] = nil
        lock.unlock()
    }
}
