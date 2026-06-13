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
    /// Return `true` to stop monitoring and finalize idle; `false` to keep monitoring.
    private let onIdle: () -> Bool

    /// A frame arriving more than this late counts as a hitch and resets the counter.
    private let hitchThreshold: CFTimeInterval = 0.080
    /// Consecutive clean frames required (at 60fps this is ~250ms of smooth rendering).
    private let requiredCleanFrames = 15
    /// Seconds of silence after last notification/hitch before declaring idle.
    private let quietWindow: CFTimeInterval
    /// When true, do not finalize until at least one remote-change notification arrives.
    /// Prevents fresh installs from declaring import complete before CloudKit starts.
    private let requireRemoteChangeBeforeIdle: Bool
    /// Gives up waiting for the first remote-change notification after this many seconds.
    /// Used on fresh installs so brand-new users without iCloud data are not blocked forever.
    private let maxWaitWithoutNotification: CFTimeInterval?
    private let monitoringStartedAt = CFAbsoluteTimeGetCurrent()

    init(
        quietWindow: CFTimeInterval = 12.0,
        requireRemoteChangeBeforeIdle: Bool = false,
        maxWaitWithoutNotification: CFTimeInterval? = nil,
        onIdle: @escaping () -> Bool
    ) {
        self.quietWindow = quietWindow
        self.requireRemoteChangeBeforeIdle = requireRemoteChangeBeforeIdle
        self.maxWaitWithoutNotification = maxWaitWithoutNotification
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

        if requireRemoteChangeBeforeIdle, !hasSeenNotification {
            if let maxWaitWithoutNotification {
                let elapsed = CFAbsoluteTimeGetCurrent() - monitoringStartedAt
                if elapsed < maxWaitWithoutNotification {
                    consecutiveCleanFrames = 0
                    return
                }
            } else {
                consecutiveCleanFrames = 0
                return
            }
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
            let shouldFinalize = onIdle()
            if shouldFinalize {
                tearDown()
            } else {
                // Caller asked to keep observing (e.g. launch pipeline not yet complete).
                consecutiveCleanFrames = 0
                lastFrameTimestamp = 0
                if hasSeenNotification {
                    lastRemoteChangeTime = CFAbsoluteTimeGetCurrent()
                }
            }
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
