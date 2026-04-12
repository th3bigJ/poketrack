import SwiftUI

struct AccountView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @State private var showPaywall = false
    @State private var showDataExport = false
    @State private var brandPendingDisable: TCGBrand?

    /// Brands the user has not added yet (shown in the Add menu).
    private var brandsAvailableToAdd: [TCGBrand] {
        TCGBrand.allCases
            .filter { !services.brandSettings.enabledBrands.contains($0) }
            .sorted(by: { $0.menuOrder < $1.menuOrder })
    }

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

            Section {
                Picker(
                    "Browse",
                    selection: Binding(
                        get: { services.brandSettings.selectedCatalogBrand },
                        set: { services.brandSettings.selectedCatalogBrand = $0 }
                    )
                ) {
                    ForEach(
                        services.brandSettings.enabledBrands.sorted(by: { $0.menuOrder < $1.menuOrder })
                    ) { b in
                        Text(b.displayTitle).tag(b)
                    }
                }
                ForEach(
                    services.brandSettings.enabledBrands.sorted(by: { $0.menuOrder < $1.menuOrder })
                ) { brand in
                    Text(brand.displayTitle)
                }
                .onDelete(perform: requestBrandRemoval)
                .deleteDisabled(services.brandSettings.enabledBrands.count <= 1)
            } header: {
                HStack {
                    Text("Card catalog")
                    Spacer(minLength: 8)
                    Menu {
                        ForEach(brandsAvailableToAdd) { brand in
                            Button(brand.displayTitle) {
                                addBrand(brand)
                            }
                        }
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                    }
                    .disabled(brandsAvailableToAdd.isEmpty)
                    .opacity(brandsAvailableToAdd.isEmpty ? 0.35 : 1)
                    .accessibilityHint(brandsAvailableToAdd.isEmpty ? "All available games are already in your catalog" : "Choose a game to download")
                }
            } footer: {
                Text("Removing a game deletes its downloaded catalog from this device and hides those cards from browse, wishlist, and collection until you add the game again and download.")
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
        .alert(
            "Remove catalog?",
            isPresented: Binding(
                get: { brandPendingDisable != nil },
                set: { if !$0 { brandPendingDisable = nil } }
            ),
            presenting: brandPendingDisable
        ) { brand in
            Button("Cancel", role: .cancel) {
                brandPendingDisable = nil
            }
            Button("Delete downloaded data", role: .destructive) {
                services.brandSettings.setEnabled(brand, isOn: false)
                do {
                    try BrandCatalogMaintenance.purgeLocalData(for: brand)
                } catch {
                    // Best-effort; UI still disables the brand.
                }
                services.pricing.clearSetPricingMemoryCache()
                if services.brandSettings.enabledBrands.contains(.pokemon) {
                    Task { await services.cardData.loadNationalDexPokemon() }
                } else {
                    services.cardData.clearNationalDexForDisabledPokemon()
                }
                Task { await services.cardData.reloadAfterBrandChange() }
                brandPendingDisable = nil
            }
        } message: { brand in
            Text("This removes the \(brand.displayTitle) catalog from this device. Wishlist and collection entries for that game are hidden until you add it again and download.")
        }
        .onChange(of: services.brandSettings.enabledBrands) { _, new in
            if !new.contains(.pokemon) {
                services.cardData.clearNationalDexForDisabledPokemon()
            }
        }
    }

    private func addBrand(_ brand: TCGBrand) {
        services.brandSettings.setEnabled(brand, isOn: true)
        Task {
            await services.performCatalogSyncAfterEnablingBrands()
        }
    }

    private func requestBrandRemoval(at offsets: IndexSet) {
        let sorted = services.brandSettings.enabledBrands.sorted(by: { $0.menuOrder < $1.menuOrder })
        guard let index = offsets.first, sorted.indices.contains(index) else { return }
        brandPendingDisable = sorted[index]
    }
}
