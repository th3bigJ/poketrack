import Foundation

/// Central URL sessions for app networking.
///
/// **Note on `nw_protocol_instance_set_output_handler … udp` logs:** Those come from Apple’s Network stack
/// (often DNS / QUIC-related UDP). There is no public API to “fix” that message; it appears in Simulator
/// and on device for many apps using `URLSession`. Using one session per traffic class avoids *extra*
/// redundant connection pools (which can slightly reduce churn vs mixing `.shared` with ad‑hoc sessions).
enum AppURLSession {
    /// Card/catalog images and prefetch — single pool for the CDN host.
    static let images: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 6
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()
}
