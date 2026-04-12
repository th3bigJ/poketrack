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

/// Temporary root for the last tab until social / Bindrs features ship.
struct BindrsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Bindrs",
                systemImage: "person.2",
                description: Text("Community features will appear here.")
            )
            .navigationTitle("Bindrs")
        }
    }
}
