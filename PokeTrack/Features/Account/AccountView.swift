import SwiftUI

struct AccountView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @State private var showPaywall = false
    @State private var showDataExport = false

    var body: some View {
        List {
            // iCloud Sync Status
            Section {
                switch services.cloudSettings.syncStatus {
                case .cloudKitConnected:
                    Label("iCloud connected", systemImage: "checkmark.icloud")
                        .foregroundStyle(.green)
                case .cloudKitFallback:
                    Label("CloudKit sync failed", systemImage: "exclamationmark.icloud")
                        .foregroundStyle(.orange)
                case .iCloudAccountUnavailable:
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
                switch services.cloudSettings.syncStatus {
                case .cloudKitFallback:
                    Text("This build is using local-only storage because the CloudKit store could not be opened on this device yet.")
                case .cloudKitConnected:
                    Text("Your wishlist, collection, and ledger data are stored locally and synced through your private iCloud database.")
                case .iCloudAccountUnavailable:
                    Text("You can still use the app offline, but CloudKit sync stays off until this device is signed into iCloud.")
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

            Section("Data") {
                Button("Export Data") {
                    showDataExport = true
                }
            }

            if let diagnostic = services.cloudSettings.cloudKitDiagnostic,
               services.cloudSettings.syncStatus == .cloudKitFallback {
                Section {
                    Text(diagnostic)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                } header: {
                    Text("CloudKit Debug")
                } footer: {
                    Text("This is the last SwiftData/CloudKit container error captured during app launch.")
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
        .sheet(isPresented: $showDataExport) {
            DataExportView()
                .environment(services)
        }
    }
}
