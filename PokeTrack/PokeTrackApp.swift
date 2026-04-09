//
//  PokeTrackApp.swift
//  PokeTrack
//
//  Created by Jordan Hardcastle on 05/04/2026.
//

import SwiftUI
import SwiftData

@main
struct PokeTrackApp: App {
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

        let directoryURL = baseURL.appendingPathComponent("PokeTrack", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent("PokeTrack.store")
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
