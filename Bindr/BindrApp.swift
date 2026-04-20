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

final class BindrPushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationCenter.default.post(name: .socialPushDeviceTokenDidUpdate, object: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Safe to ignore in development/simulators where APNs registration may be unavailable.
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        NotificationCenter.default.post(name: .socialPushDeepLinkReceived, object: nil, userInfo: notification.request.content.userInfo)
        return [.banner, .sound, .badge]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        NotificationCenter.default.post(name: .socialPushDeepLinkReceived, object: nil, userInfo: response.notification.request.content.userInfo)
    }
}

@main
struct BindrApp: App {
    @UIApplicationDelegateAdaptor(BindrPushAppDelegate.self) private var pushAppDelegate

    static let cloudKitFallbackDefaultsKey = "cloudKitFallbackActive"
    static let cloudKitLastErrorDefaultsKey = "cloudKitLastError"

    /// CloudKit-backed store for user data. SwiftData keeps a local cache on-device and syncs it through the
    /// app's private iCloud database when the user is signed into iCloud.
    private static func makeModelContainer() -> ModelContainer {
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
            logModelContainerIssue(
                stage: "initial CloudKit load",
                error: error
            )
            destroyPersistentStoreFiles()

            do {
                let container = try makePersistentContainer(schema: schema, cloudKitDatabase: .automatic)
                UserDefaults.standard.set(false, forKey: cloudKitFallbackDefaultsKey)
                UserDefaults.standard.removeObject(forKey: cloudKitLastErrorDefaultsKey)
                return container
            } catch {
                logModelContainerIssue(
                    stage: "CloudKit reload after store reset",
                    error: error
                )

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

    private static func makePersistentContainer(
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

    private static var storeURL: URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        let directoryURL = baseURL.appendingPathComponent("Bindr", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent("Bindr.store")
    }

    private static func destroyPersistentStoreFiles() {
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

    private static func logModelContainerIssue(stage: String, error: Error) {
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

        UserDefaults.standard.set(diagnostic, forKey: cloudKitLastErrorDefaultsKey)

        print("SwiftData model container failure during \(stage)")
        print("domain=\(nsError.domain) code=\(nsError.code)")
        print("description=\(nsError.localizedDescription)")
        if !nsError.userInfo.isEmpty {
            print("userInfo=\(nsError.userInfo)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(Self.makeModelContainer())
    }
}
