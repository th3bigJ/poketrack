import SwiftUI

struct SharingPlaceholderView: View {
    @Environment(AppServices.self) private var services
    @State private var showPaywall = false

    var body: some View {
        Group {
            if !services.store.isPremium {
                ContentUnavailableView(
                    "Premium only",
                    systemImage: "person.2",
                    description: Text("Upgrade to share your collection with friends via iCloud.")
                )
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Unlock") { showPaywall = true }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Coming soon",
                    systemImage: "link",
                    description: Text("CKShare wiring is device- and account-specific. Use two iCloud accounts to validate sharing in a future build.")
                )
            }
        }
        .navigationTitle("Sharing")
        .sheet(isPresented: $showPaywall) {
            PaywallSheet().environment(services)
        }
    }
}
