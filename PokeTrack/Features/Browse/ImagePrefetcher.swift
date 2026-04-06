import Foundation

/// Warms `URLCache` for upcoming card images so `CachedAsyncImage` can display
/// them instantly when cells scroll into view.
final class ImagePrefetcher: @unchecked Sendable {
    static let shared = ImagePrefetcher()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        // Low priority so prefetch doesn't compete with visible-cell loads.
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

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
