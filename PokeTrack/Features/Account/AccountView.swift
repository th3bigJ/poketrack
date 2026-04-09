import SwiftUI

struct AccountView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @State private var showPaywall = false

    var body: some View {
        List {
            // iCloud Sync Status
            Section {
                if services.cloudSettings.isICloudAvailable {
                    Label("iCloud connected", systemImage: "checkmark.icloud")
                        .foregroundStyle(.green)
                } else {
                    Label("iCloud not available", systemImage: "exclamationmark.icloud")
                        .foregroundStyle(.orange)
                    
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } header: {
                Text("Data Sync")
            } footer: {
                if services.cloudSettings.isICloudAvailable {
                    Text("Your wishlists and collections sync across all devices signed into your iCloud account.")
                } else {
                    Text("Sign into iCloud in Settings to sync your data across devices.")
                }
            }

            Section("Pricing") {
                Picker(
                    "Show prices in",
                    selection: Binding(
                        get: { services.priceDisplay.currency },
                        set: { services.priceDisplay.currency = $0 }
                    )
                ) {
                    ForEach(PriceDisplayCurrency.allCases) { c in
                        Text(c.pickerTitle).tag(c)
                    }
                }
                Text("Catalog and history values from the server are in US dollars. Pounds use a daily exchange rate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Premium") {
                if services.store.isPremium {
                    Label("Premium active", systemImage: "checkmark.seal.fill")
                } else {
                    Button("Unlock Premium") {
                        showPaywall = true
                    }
                }
                Button("Restore purchases") {
                    Task {
                        try? await services.store.restore()
                    }
                }
            }

            #if DEBUG
            Section {
                Toggle(
                    "Force free tier",
                    isOn: Binding(
                        get: { services.store.debugForceFreeTier },
                        set: { services.store.debugForceFreeTier = $0 }
                    )
                )
            } header: {
                Text("Testing")
            } footer: {
                Text("On: app acts non‑Premium (wishlist limits, etc.) while your StoreKit purchase stays active. Off: real entitlement.")
            }
            #endif
        }
        .toolbar(.hidden, for: .navigationBar)
        .contentMargins(.top, rootFloatingChromeInset, for: .scrollContent)
        .sheet(isPresented: $showPaywall) {
            PaywallSheet()
                .environment(services)
        }
    }
}
