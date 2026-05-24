import UIKit
import CoreData

/// Keeps the launch overlay visible until SwiftData's CloudKit @MainActor merge
/// has fully finished — including any late bursts after notifications stop.
///
/// Strategy: run a CADisplayLink and count consecutive frames that arrive on time.
/// Any frame that's late (main thread was busy) resets the counter. We only declare
/// idle after N consecutive clean frames AND at least `quietWindow` seconds of
/// silence since the last `NSPersistentStoreRemoteChange` notification.
///
/// The quiet window must be larger than the gap between the last notification and
/// the last merge batch — logs show this can be 3-10s, so we use a 12s window with
/// a hard cap at 25s.
final class CloudKitIdleMonitor {
    private var notificationObserver: NSObjectProtocol?
    private var displayLink: CADisplayLink?
    private var consecutiveCleanFrames = 0
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var lastRemoteChangeTime: CFAbsoluteTime = 0
    private var hasSeenNotification = false
    private let onIdle: () -> Void

    /// A frame arriving more than this late counts as a hitch and resets the counter.
    private let hitchThreshold: CFTimeInterval = 0.080
    /// Consecutive clean frames required (at 60fps this is ~250ms of smooth rendering).
    private let requiredCleanFrames = 15
    /// Seconds of silence after last notification/hitch before declaring idle.
    private let quietWindow: CFTimeInterval

    init(quietWindow: CFTimeInterval = 12.0, onIdle: @escaping () -> Void) {
        self.quietWindow = quietWindow
        self.onIdle = onIdle
    }

    func start() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleRemoteChange()
        }
        armDisplayLink()
        print("[CloudKit] idle monitor armed")
    }

    func stop() {
        tearDown()
    }

    private func handleRemoteChange() {
        hasSeenNotification = true
        lastRemoteChangeTime = CFAbsoluteTimeGetCurrent()
        consecutiveCleanFrames = 0
        lastFrameTimestamp = 0
    }

    private func armDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp

        if lastFrameTimestamp == 0 {
            lastFrameTimestamp = now
            return
        }

        let interval = now - lastFrameTimestamp
        lastFrameTimestamp = now

        // Any hitch resets — this catches merge work that arrives without a notification.
        if interval > hitchThreshold {
            consecutiveCleanFrames = 0
            // Also bump the quiet window start — a hitch means work is still happening.
            if hasSeenNotification {
                lastRemoteChangeTime = CFAbsoluteTimeGetCurrent()
            }
            return
        }

        // If we've seen notifications, enforce the quiet window.
        if hasSeenNotification {
            let silence = CFAbsoluteTimeGetCurrent() - lastRemoteChangeTime
            if silence < quietWindow {
                consecutiveCleanFrames = 0
                return
            }
        }

        consecutiveCleanFrames += 1

        if consecutiveCleanFrames >= requiredCleanFrames {
            let note = hasSeenNotification
                ? String(format: "%.1fs after last notification/hitch", CFAbsoluteTimeGetCurrent() - lastRemoteChangeTime)
                : "no notifications received"
            print("[CloudKit] idle confirmed (\(note))")
            tearDown()
            onIdle()
        }
    }

    private func tearDown() {
        if let o = notificationObserver {
            NotificationCenter.default.removeObserver(o)
            notificationObserver = nil
        }
        displayLink?.invalidate()
        displayLink = nil
    }

    deinit { tearDown() }
}
