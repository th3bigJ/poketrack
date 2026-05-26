import Foundation

/// Lightweight launch profiler that logs method timings to both the console
/// and a flat text file so you can inspect which steps dominate the first
/// interactive frame.
///
/// Usage:
///   LaunchTraceProfiler.begin("reloadDashboardInventory")
///   // … work …
///   LaunchTraceProfiler.end("reloadDashboardInventory")
///
///   LaunchTraceProfiler.mark("dashboard is now touchable")
///
/// Call ``flushToFile()`` once after the launch sequence settles; the file
/// is written to the app's caches directory so it survives relaunch but not
/// an uninstall.
enum LaunchTraceProfiler {

    // MARK: - Public API

    /// Record the start of a measured block.
    static func begin(_ label: String) {
        log("▶ BEGIN \(label)")
    }

    /// Record the end of a measured block.
    static func end(_ label: String) {
        log("◀ END   \(label)")
    }

    /// Record a one-shot event.
    static func mark(_ event: String) {
        log("● \(event)")
    }

    /// Seconds since the profiler was first used (wall-clock).
    static func elapsed() -> Double {
        let duration = ContinuousClock.now - startInstant
        let (seconds, attoseconds) = duration.components
        return Double(seconds) + Double(attoseconds) / 1_000_000_000_000_000_000.0
    }

    /// Write all accumulated entries to a log file in the caches directory.
    static func flushToFile() {
        queue.sync {
            guard !lines.isEmpty else { return }
            let url = Self.logFileURL()
            let content = lines.joined(separator: "\n")
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                print("[LaunchTrace] flushed \(lines.count) lines → \(url.lastPathComponent)")
            } catch {
                print("[LaunchTrace] failed to write log: \(error)")
            }
        }
    }

    /// Reset for a new session (clears in-memory buffer; does not delete the file).
    static func reset() {
        queue.sync { lines = [] }
    }

    // MARK: - Private

    private static let queue = DispatchQueue(label: "launch.trace.profiler", qos: .utility)
    private static let startInstant = ContinuousClock.now
    private static var lines: [String] = []

    private static func log(_ entry: String) {
        let offset = elapsed()
        let line = String(format: "+%07.3fs  %@", offset, entry)
        print("[LaunchTrace] \(line)")
        queue.async {
            lines.append(line)
        }
    }

    private static func logFileURL() -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("launch_trace.log")
    }
}
