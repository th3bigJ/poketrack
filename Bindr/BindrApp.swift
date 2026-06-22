//
//  BindrApp.swift
//  Bindr
//
//  Created by Jordan Hardcastle on 05/04/2026.
//

import SwiftUI
import SwiftData
import UserNotifications
import UIKit
import BackgroundTasks

final class BindrPushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Buffer for a notification tap that arrived before any observer was
    /// listening — typically a cold launch where the user tapped the
    /// notification to wake the app and `didReceive` fires before SwiftUI
    /// has built `AppServices` (and therefore before
    /// ``SocialPushService.subscribeToPushEvents`` ran).
    /// `NotificationCenter.default.post` requires a live observer at the
    /// moment of posting, so without this buffer the deep link would be lost
    /// on cold launch. ``SocialPushService`` drains this on init.
    static var pendingTapUserInfo: [AnyHashable: Any]?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: CatalogDailyRefreshTask.identifier,
            using: nil
        ) { task in
            CatalogDailyRefreshTask.handle(task as! BGAppRefreshTask)
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationCenter.default.post(name: .socialPushDeviceTokenDidUpdate, object: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Safe to ignore in development/simulators where APNs registration may be unavailable.
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Foreground arrival: just present the banner. We deliberately do NOT
        // post the deep-link notification here — `willPresent` fires the
        // moment a push arrives while the app is in front, which is *before*
        // the user has done anything. Posting it would route them to the
        // related post immediately, yanking them out of whatever they were
        // doing. Only the actual tap (`didReceive` below) should route.
        if #available(iOS 14.0, *) {
            return [.banner, .list, .sound, .badge]
        } else {
            return [.alert, .sound, .badge]
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        // Buffer first, then post. Either:
        //   • An observer is already listening — the post delivers it, the
        //     observer drains the buffer (no-op) on the next init.
        //   • No observer yet (cold launch race) — the post is dropped, but
        //     ``SocialPushService.init`` reads `pendingTapUserInfo` and
        //     enqueues the deep link as soon as it subscribes.
        Self.pendingTapUserInfo = userInfo
        NotificationCenter.default.post(name: .socialPushDeepLinkReceived, object: nil, userInfo: userInfo)
    }
}

@main
struct BindrApp: App {
    @UIApplicationDelegateAdaptor(BindrPushAppDelegate.self) private var pushAppDelegate

    /// Captured in ``BindrApp/init()`` before SwiftData creates the store file.
    /// Must not use lazy `static let` — that would run after the empty store is created on first launch.
    nonisolated(unsafe) private(set) static var storeExistedAtLaunch = false

    init() {
        Self.storeExistedAtLaunch = FileManager.default.fileExists(atPath: Self.storeURL.path)
        Self.suppressCoreDataDebugLogging()
        // App launch runs on the main thread; configure tab bar before the first frame.
        dispatchPrecondition(condition: .onQueue(.main))
        MainActor.assumeIsolated {
            Self.applyTabBarAppearance()
        }
    }

    /// Core Data / SwiftData emit verbose WAL checkpoint logs when SQL debug is
    /// enabled in the run scheme. Silence that noise in Debug builds.
    nonisolated private static func suppressCoreDataDebugLogging() {
        #if DEBUG
        let settings: [String: String] = [
            "com.apple.CoreData.Logging.stderr": "0",
            "com.apple.CoreData.SQLDebug": "0",
            "com.apple.CoreData.ConcurrencyDebug": "0",
            "com.apple.CoreData.MigrationDebug": "0",
        ]
        for (key, value) in settings {
            UserDefaults.standard.set(value, forKey: key)
            setenv(key, value, 1)
        }
        #endif
    }

    /// Local SwiftData store. Library backup and cross-device recovery use Bindr Cloud (R2).
    nonisolated private static func makeModelContainer() -> ModelContainer {
        suppressCoreDataDebugLogging()
        let schema = Schema([
            WishlistItem.self,
            CollectionItem.self,
            LedgerLine.self,
            CostLot.self,
            SaleAllocation.self,
            Binder.self,
            BinderSlot.self,
            Deck.self,
            DeckCard.self,
            CollectionValueSnapshot.self,
            CollectionWeeklyAverage.self,
            CollectionMonthlyAverage.self,
        ])

        do {
            return try makePersistentContainer(schema: schema)
        } catch {
            logModelContainerIssue(stage: "initial local store load", error: error)
            destroyPersistentStoreFiles()
            do {
                return try makePersistentContainer(schema: schema)
            } catch {
                fatalError("Could not create SwiftData store: \(error)")
            }
        }
    }

    nonisolated private static func makePersistentContainer(schema: Schema) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    nonisolated private static var storeURL: URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        let directoryURL = baseURL.appendingPathComponent("Bindr", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent("Bindr.store")
    }

    nonisolated private static func destroyPersistentStoreFiles() {
        let fileManager = FileManager.default
        let urls = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal"),
        ]

        for url in urls where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    nonisolated private static func logModelContainerIssue(stage: String, error: Error) {
        let nsError = error as NSError
        let diagnostic = [
            "stage=\(stage)",
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
            "description=\(nsError.localizedDescription)",
            nsError.userInfo.isEmpty ? nil : "userInfo=\(nsError.userInfo)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        #if DEBUG
        print("Bindr SwiftData store issue:\n\(diagnostic)")
        #endif
    }

    /// Match tab bar glass density to multi-select pill buttons.
    /// Re-call after sheet dismiss — presentation can reset the tab bar to the default opaque grey.
    @MainActor
    static func applyTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.backgroundColor = UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor.black.withAlphaComponent(0.30)
            } else {
                return UIColor.black.withAlphaComponent(0.12)
            }
        }
        appearance.shadowColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.18)
                : UIColor.black.withAlphaComponent(0.10)
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ModelContainerHost()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                CatalogDailyRefreshTask.schedule()
            }
        }
    }

    private struct ModelContainerHost: View {
        @State private var modelContainer: ModelContainer?

        var body: some View {
            Group {
                if let modelContainer {
                    RootView()
                        .modelContainer(modelContainer)
                } else {
                    LaunchWordmarkView()
                        .task {
                            let container = await Task.detached(priority: .userInitiated) {
                                BindrApp.makeModelContainer()
                            }.value
                            modelContainer = container
                        }
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                GlassReadySignal.shared.isReady = true
            }
        }
    }
}
