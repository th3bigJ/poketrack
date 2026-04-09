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
                self.lock.lock()
                self.inFlight[url] = nil
                self.lock.unlock()
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
}
