import Foundation

/// Warms `URLCache` for upcoming card images so `CachedAsyncImage` can display
/// them instantly when cells scroll into view.
final class ImagePrefetcher: @unchecked Sendable {
    static let shared = ImagePrefetcher()

    /// Same pool as `CachedAsyncImage` so image traffic doesn't open two parallel session stacks to the CDN.
    private let session = AppURLSession.images

    private var inFlight: [URL: Task<Void, Never>] = [:]
    private let lock = NSLock()

    private init() {}

    /// Start warming the cache for `urls`. Already-cached or in-flight URLs are skipped.
    func prefetch(_ urls: [URL], priority: TaskPriority = .low) {
        for url in urls {
            lock.lock()
            guard inFlight[url] == nil else { lock.unlock(); continue }
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
            if URLCache.shared.cachedResponse(for: request) != nil {
                lock.unlock()
                continue
            }
            let task = Task.detached(priority: priority) { [weak self] in
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

    /// Cancel specific URLs (useful when swiping through detail view).
    func cancel(urls: [URL]) {
        lock.lock()
        for url in urls {
            inFlight[url]?.cancel()
            inFlight[url] = nil
        }
        lock.unlock()
    }

    /// Prefetch a slice of card thumbnails, typically just ahead of the visible grid cells.
    /// Uses larger window (30) for smoother scrolling experience.
    func prefetchCardWindow(_ cards: [Card], startingAt startIndex: Int, count: Int = 30) {
        guard startIndex < cards.count else { return }
        let endIndex = min(startIndex + count, cards.count)
        let urls = cards[startIndex..<endIndex].map {
            AppConfiguration.imageURL(relativePath: $0.imageLowSrc)
        }
        prefetch(urls, priority: .low)
    }

    /// Prefetch high-res images for adjacent cards in detail view for instant swipe experience.
    /// Called when viewing a card to prepare next/prev cards at high quality.
    func prefetchHighResForDetailView(_ cards: [Card], currentIndex: Int, window: Int = 2) {
        let start = max(0, currentIndex - window)
        let end = min(cards.count, currentIndex + window + 1)
        
        var urls: [URL] = []
        for i in start..<end where i != currentIndex {
            let card = cards[i]
            // Prefetch high-res if available, otherwise low-res
            if let highSrc = card.imageHighSrc {
                urls.append(AppConfiguration.imageURL(relativePath: highSrc))
            } else {
                urls.append(AppConfiguration.imageURL(relativePath: card.imageLowSrc))
            }
        }
        
        // Use medium priority for detail view - user will see these soon
        prefetch(urls, priority: .medium)
    }

    /// Prefetch low-res thumbnails for the entire visible range immediately.
    /// Called on initial load to ensure instant display.
    func prefetchInitialBatch(_ cards: [Card], count: Int = 60) {
        let end = min(count, cards.count)
        let urls = cards[0..<end].map {
            AppConfiguration.imageURL(relativePath: $0.imageLowSrc)
        }
        prefetch(urls, priority: .userInitiated)
    }

    private func finish(_ url: URL) {
        lock.lock()
        inFlight[url] = nil
        lock.unlock()
    }
}
