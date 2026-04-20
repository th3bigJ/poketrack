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
        guard let raw = userInfo["deep_link"] as? String else { return }
        guard let url = URL(string: raw) else { return }
        queuedDeepLinkURL = url
    }

    func consumeQueuedDeepLinkURL() -> URL? {
        defer { queuedDeepLinkURL = nil }
        return queuedDeepLinkURL
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
            guard let userInfo = notification.userInfo else { return }
            self?.queueDeepLink(from: userInfo)
        }
    }
}

extension Notification.Name {
    static let socialPushDeviceTokenDidUpdate = Notification.Name("socialPushDeviceTokenDidUpdate")
    static let socialPushDeepLinkReceived = Notification.Name("socialPushDeepLinkReceived")
}
