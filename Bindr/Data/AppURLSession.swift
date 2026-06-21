import Foundation

/// Central URL sessions for app networking.
///
/// **Note on `nw_protocol_instance_set_output_handler … udp` logs:** Those come from Apple's Network stack
/// (often DNS / QUIC-related UDP). There is no public API to "fix" that message; it appears in Simulator
/// and on device for many apps using `URLSession`. Using one session per traffic class avoids *extra*
/// redundant connection pools (which can slightly reduce churn vs mixing `.shared` with ad‑hoc sessions).
enum AppURLSession {
    /// Shared image cache used by both the images session and `CachedAsyncImage`.
    /// The system default `URLCache.shared` disk budget is small; a big grid evicts thumbnails and looks
    /// like "re-download every launch" while the cache warms up again.
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
        config.httpMaximumConnectionsPerHost = 6
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    /// Parallel catalog/pricing downloads from R2. Kept below the image session (6) so thumbnails
    /// still load while a large first-sync runs, but high enough to saturate the network.
    static let catalogParallelDownloads = 12

    /// Catalog/pricing downloads — separate session so catalog traffic does not evict the image cache.
    static let catalog: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = catalogParallelDownloads
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 600
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
}
