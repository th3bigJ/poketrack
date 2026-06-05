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

    nonisolated static let cloudKitFallbackDefaultsKey = "cloudKitFallbackActive"
    nonisolated static let cloudKitLastErrorDefaultsKey = "cloudKitLastError"
    /// True if the SQLite store already existed when the app launched.
    /// False means this is a fresh install (or after deletion) — CloudKit restore is needed.
    nonisolated static let storeExistedAtLaunch: Bool = FileManager.default.fileExists(atPath: Self.storeURL.path)

    init() {
        Self.configureTabBarAppearance()
    }

    /// CloudKit-backed store. SwiftData merges CloudKit records on @MainActor; the
    /// CloudKitIdleMonitor keeps the launch overlay visible until those merges complete,
    /// so the freeze is hidden behind the overlay rather than felt on the dashboard.
    nonisolated private static func makeModelContainer() -> ModelContainer {
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
            let container = try makePersistentContainer(schema: schema, cloudKitDatabase: .automatic)
            UserDefaults.standard.set(false, forKey: cloudKitFallbackDefaultsKey)
            UserDefaults.standard.removeObject(forKey: cloudKitLastErrorDefaultsKey)
            return container
        } catch {
            logModelContainerIssue(stage: "initial CloudKit load", error: error)
            destroyPersistentStoreFiles()
            do {
                let container = try makePersistentContainer(schema: schema, cloudKitDatabase: .automatic)
                UserDefaults.standard.set(false, forKey: cloudKitFallbackDefaultsKey)
                UserDefaults.standard.removeObject(forKey: cloudKitLastErrorDefaultsKey)
                return container
            } catch {
                logModelContainerIssue(stage: "CloudKit reload after store reset", error: error)
                do {
                    let container = try makePersistentContainer(schema: schema, cloudKitDatabase: .none)
                    UserDefaults.standard.set(true, forKey: cloudKitFallbackDefaultsKey)
                    return container
                } catch {
                    fatalError("Could not create fallback SwiftData store: \(error)")
                }
            }
        }
    }

    nonisolated private static func makePersistentContainer(
        schema: Schema,
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase
    ) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: cloudKitDatabase
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
        let iCloudToken = FileManager.default.ubiquityIdentityToken
        let diagnostic = [
            "stage=\(stage)",
            "iCloudAccount=\(iCloudToken != nil ? "signed-in" : "not-signed-in")",
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
            "description=\(nsError.localizedDescription)",
            nsError.userInfo.isEmpty ? nil : "userInfo=\(nsError.userInfo)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")

        UserDefaults.standard.set(diagnostic, forKey: cloudKitLastErrorDefaultsKey)

        print("[PokeTrack] SwiftData model container failure during \(stage)")
        print("[PokeTrack] iCloud account present: \(iCloudToken != nil)")
        print("[PokeTrack] domain=\(nsError.domain) code=\(nsError.code)")
        print("[PokeTrack] description=\(nsError.localizedDescription)")
        if !nsError.userInfo.isEmpty {
            print("[PokeTrack] userInfo=\(nsError.userInfo)")
        }
    }

    /// Match tab bar glass density to multi-select pill buttons.
    private static func configureTabBarAppearance() {
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
                    LaunchWordmarkView(elapsedLabel: "")
                        .task {
                            // Build the ModelContainer off the main thread so opening the
                            // CloudKit-backed SQLite store doesn't freeze the launch animation.
                            let container = await Task.detached(priority: .userInitiated) {
                                BindrApp.makeModelContainer()
                            }.value
                            modelContainer = container
                        }
                }
            }
            .task {
                // Liquid Glass initialises quickly; enabling it is cheap. (An earlier "8–9s glass"
                // freeze was actually the offline-image reconcile blocking the main thread — see
                // OfflineImageDownloadService.) Flip glass on after one short settle so the cards
                // come up glassy on the first interactive frame rather than popping in late.
                try? await Task.sleep(for: .milliseconds(300))
                GlassReadySignal.shared.isReady = true
            }
        }
    }
}
