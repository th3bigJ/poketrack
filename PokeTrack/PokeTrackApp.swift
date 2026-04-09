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
    /// Local-only store. We have CloudKit entitlements for containers / future use, but SwiftData’s automatic
    /// CloudKit sync requires optional properties, defaults, and optional relationships on every model. Until
    /// the schema is migrated for that, opt out per Apple’s “Disable automatic sync” guidance.
    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([
            WishlistItem.self,
            CollectionItem.self,
            TransactionRecord.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not open SwiftData store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(Self.makeModelContainer())
    }
}
