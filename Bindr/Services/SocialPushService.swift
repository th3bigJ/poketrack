import Foundation
import Observation
import UIKit
import UserNotifications

@Observable
@MainActor
final class SocialPushService {
    private let authService: SocialAuthService
    private let profileService: SocialProfileService

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var queuedDeepLinkURL: URL?

    init(authService: SocialAuthService, profileService: SocialProfileService) {
        self.authService = authService
        self.profileService = profileService
        subscribeToPushEvents()
        // Cold-launch drain: if the user tapped a notification that woke
        // the app from a fully-terminated state, the UN-delegate's
        // `didReceive` may have fired before this service existed — and
        // therefore before any observer was listening on
        // `.socialPushDeepLinkReceived`. `BindrPushAppDelegate` stashes
        // the userInfo as a fallback; pull it now so the deep link still
        // routes once the UI mounts.
        if let pending = BindrPushAppDelegate.pendingTapUserInfo {
            BindrPushAppDelegate.pendingTapUserInfo = nil
            queueDeepLink(from: pending)
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorizationIfNeeded() async {
        await refreshAuthorizationStatus()
        guard authorizationStatus == .notDetermined else { return }
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        authorizationStatus = granted ? .authorized : .denied
    }

    func updateRegistrationState() async {
        await requestAuthorizationIfNeeded()
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }
        guard case .signedIn = authService.authState else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func handleAPNsTokenData(_ tokenData: Data) async {
        let hex = tokenData.map { String(format: "%02x", $0) }.joined()
        do {
            try await profileService.registerDeviceToken(hex)
        } catch {
            // Best-effort registration: user still receives local app behavior.
        }
    }

    func queueDeepLink(from userInfo: [AnyHashable: Any]) {
        let raw = extractDeepLinkString(from: userInfo)
        guard let raw else { return }
        guard let url = URL(string: raw) else { return }
        queuedDeepLinkURL = url
    }

    func queueDeepLink(url: URL) {
        queuedDeepLinkURL = url
    }

    func consumeQueuedDeepLinkURL() -> URL? {
        defer { queuedDeepLinkURL = nil }
        return queuedDeepLinkURL
    }

    func clearAppBadgeCount() {
        if #available(iOS 17.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        } else {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        }
    }

    private func subscribeToPushEvents() {
        NotificationCenter.default.addObserver(
            forName: .socialPushDeviceTokenDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let data = notification.object as? Data else { return }
            Task { @MainActor in
                await self?.handleAPNsTokenData(data)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .socialPushDeepLinkReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let userInfo = notification.userInfo else { return }
            MainActor.assumeIsolated {
                self.queueDeepLink(from: userInfo)
            }
        }
    }

    private func extractDeepLinkString(from userInfo: [AnyHashable: Any]) -> String? {
        let directKeys = ["deep_link", "deepLink", "deeplink", "url"]
        for key in directKeys {
            if let raw = userInfo[key] as? String {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        if let metadata = userInfo["metadata"] as? [String: Any] {
            for key in directKeys {
                if let raw = metadata[key] as? String {
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            }
        }

        return nil
    }
}

extension Notification.Name {
    static let socialPushDeviceTokenDidUpdate = Notification.Name("socialPushDeviceTokenDidUpdate")
    static let socialPushDeepLinkReceived = Notification.Name("socialPushDeepLinkReceived")
}
