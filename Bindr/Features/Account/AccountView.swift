import SwiftUI

struct SettingsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @State private var showPaywall = false
    @State private var showDataExport = false
    @State private var showDisclaimer = false
    @State private var brandPendingDisable: TCGBrand?

    /// Brands the user has not added yet (shown in the Add menu). Order follows the hosted `brands.json`.
    private var brandsAvailableToAdd: [TCGBrand] {
        services.brandsManifest.brandsAvailableToAdd(enabled: services.brandSettings.enabledBrands)
    }

    var body: some View {
        List {
            topSections
            bottomSections
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
        .sheet(isPresented: $showDisclaimer) {
            DisclaimerView()
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

    @ViewBuilder private var topSections: some View {
        Section {
            switch services.cloudSettings.syncStatus {
            case .cloudKitConnected:
                Label("iCloud connected", systemImage: "checkmark.icloud").foregroundStyle(.green)
            case .cloudKitFallback:
                Label("CloudKit sync failed", systemImage: "exclamationmark.icloud").foregroundStyle(.orange)
            case .iCloudAccountUnavailable:
                Label("iCloud not available", systemImage: "exclamationmark.icloud").foregroundStyle(.orange)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        } header: { Text("Data Sync") } footer: {
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
            Picker("Show prices in", selection: Binding(
                get: { services.priceDisplay.currency },
                set: { services.priceDisplay.currency = $0 }
            )) {
                ForEach(PriceDisplayCurrency.allCases) { c in Text(c.pickerTitle).tag(c) }
            }
            Text("Catalog and history values from the server are in US dollars. Pounds use a daily exchange rate.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section("Premium") {
            if services.store.isPremium {
                Label("Premium active", systemImage: "checkmark.seal.fill")
            } else {
                Button("Unlock Premium") { showPaywall = true }
            }
            Button("Restore purchases") { Task { try? await services.store.restore() } }
        }

        CatalogSection(brandsAvailableToAdd: brandsAvailableToAdd, onAdd: addBrand, onDelete: requestBrandRemoval)
    }

    @ViewBuilder private var bottomSections: some View {
        Section {
            Button("Refresh catalog") {
                Task { await services.performCatalogSyncAfterEnablingBrands() }
            }
        } header: {
            Text("Catalog")
        } footer: {
            Text("Re-checks the server for new sets and cards. Use this if a recently released set appears in the list but shows no cards.")
        }

        Section {
            Button("Export Data") { showDataExport = true }
        } header: {
            Text("Data")
        }

        Section {
            NavigationLink {
                NotificationPreferencesView()
                    .environment(services)
            } label: {
                Label("Notification Preferences", systemImage: "bell.badge")
            }
        } header: {
            Text("Social")
        } footer: {
            Text("Choose exactly which social activity types can notify you.")
        }

        Section {
            Button("Legal Disclaimer") { showDisclaimer = true }
        }

        if let diagnostic = services.cloudSettings.cloudKitDiagnostic,
           services.cloudSettings.syncStatus == .cloudKitFallback {
            Section {
                Text(diagnostic).font(.caption.monospaced()).textSelection(.enabled)
            } header: { Text("CloudKit Debug") } footer: {
                Text("This is the last SwiftData/CloudKit container error captured during app launch.")
            }
        }

        #if DEBUG
        Section {
            Toggle("Force free tier", isOn: Binding(
                get: { services.store.debugForceFreeTier },
                set: { services.store.debugForceFreeTier = $0 }
            ))
        } header: { Text("Testing") } footer: {
            Text("On: app acts non‑Premium (wishlist limits, etc.) while your StoreKit purchase stays active. Off: real entitlement.")
        }
        #endif
    }

    private func addBrand(_ brand: TCGBrand) {
        services.brandSettings.setEnabled(brand, isOn: true)
        Task {
            await services.performCatalogSyncAfterEnablingBrands()
        }
    }

    private func requestBrandRemoval(at offsets: IndexSet) {
        let sorted = services.brandsManifest.sortBrands(services.brandSettings.enabledBrands)
        guard let index = offsets.first, sorted.indices.contains(index) else { return }
        brandPendingDisable = sorted[index]
    }

}

private struct CatalogSection: View {
    @Environment(AppServices.self) private var services
    let brandsAvailableToAdd: [TCGBrand]
    let onAdd: (TCGBrand) -> Void
    let onDelete: (IndexSet) -> Void

    private var sortedEnabled: [TCGBrand] {
        services.brandsManifest.sortBrands(services.brandSettings.enabledBrands)
    }

    var body: some View {
        Section {
            Picker(
                "Browse",
                selection: Binding(
                    get: { services.brandSettings.selectedCatalogBrand },
                    set: { services.brandSettings.selectedCatalogBrand = $0 }
                )
            ) {
                ForEach(sortedEnabled) { b in
                    Text(b.displayTitle).tag(b)
                }
            }
            ForEach(sortedEnabled) { brand in
                Text(brand.displayTitle)
            }
            .onDelete(perform: onDelete)
            .deleteDisabled(services.brandSettings.enabledBrands.count <= 1)
        } header: {
            HStack {
                Text("Card catalog")
                Spacer(minLength: 8)
                Menu {
                    ForEach(brandsAvailableToAdd) { brand in
                        Button(brand.displayTitle) { onAdd(brand) }
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
    }
}

