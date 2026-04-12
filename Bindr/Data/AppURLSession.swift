import Foundation

/// Central URL sessions for app networking.
///
/// **Note on `nw_protocol_instance_set_output_handler … udp` logs:** Those come from Apple’s Network stack
/// (often DNS / QUIC-related UDP). There is no public API to “fix” that message; it appears in Simulator
/// and on device for many apps using `URLSession`. Using one session per traffic class avoids *extra*
/// redundant connection pools (which can slightly reduce churn vs mixing `.shared` with ad‑hoc sessions).
enum AppURLSession {
    /// Single disk + memory cache for **all** card art traffic: `URLSession` stores here, and
    /// `CachedAsyncImage` / prefetch read the same instance via `cachedResponse(for:)`.
    /// The system default `URLCache.shared` disk budget is small; a big grid evicts thumbnails and looks
    /// like “re-download every launch” while the cache warms up again.
    static let imageURLCache: URLCache = {
        let memoryCapacity = 80 * 1024 * 1024
        let diskCapacity = 512 * 1024 * 1024
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("BindrImageURLCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, directory: dir)
    }()

    /// Card/catalog images and prefetch — single pool for the CDN host.
    static let images: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = imageURLCache
        config.httpMaximumConnectionsPerHost = 10
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()
}
