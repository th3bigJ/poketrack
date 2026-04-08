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
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [WishlistItem.self, CollectionItem.self, TransactionRecord.self])
    }
}
