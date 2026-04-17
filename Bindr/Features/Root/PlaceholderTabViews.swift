import SwiftUI

/// Temporary root for the first tab until the real dashboard is built.
struct DashboardPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Dashboard",
                systemImage: "rectangle.grid.2x2",
                description: Text("Your overview will appear here.")
            )
            .navigationTitle("Dashboard")
        }
    }
}

