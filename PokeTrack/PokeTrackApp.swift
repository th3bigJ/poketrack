//
//  PokeTrackApp.swift
//  PokeTrack
//
//  Created by Jordan Hardcastle on 05/04/2026.
//

import SwiftData
import SwiftUI

@main
struct PokeTrackApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try PokeTrackModelContainer.makeProduction()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
