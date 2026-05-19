import SwiftUI

// MARK: - Root Settings Page

struct SettingsView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        List {
            gameSection
            storageSection
            premiumSection
            socialSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Game & Catalog

    private var gameSection: some View {
        Section("Game & Catalog") {
            NavigationLink {
                CatalogSettingsPage()
                    .environment(services)
            } label: {
                Label("Card Catalogs", systemImage: "square.stack.3d.up.fill")
            }

            NavigationLink {
                ActiveGameSettingsPage()
                    .environment(services)
            } label: {
                Label("Active Game", systemImage: "gamecontroller.fill")
            }
        }
    }

    // MARK: - Storage & Pricing

    private var storageSection: some View {
        Section("Storage & Pricing") {
            NavigationLink {
                OfflineSettingsPage()
                    .environment(services)
            } label: {
                Label("Offline Mode", systemImage: "arrow.down.circle.fill")
            }

            NavigationLink {
                PricingSettingsPage()
                    .environment(services)
            } label: {
                Label("Pricing & Currency", systemImage: "dollarsign.circle.fill")
            }

            NavigationLink {
                DataSyncSettingsPage()
                    .environment(services)
            } label: {
                syncStatusLabel
            }
        }
    }

    private var syncStatusLabel: some View {
        HStack {
            Label("iCloud Sync", systemImage: syncIconName)
                .foregroundStyle(syncColor)
        }
    }

    private var syncIconName: String {
        switch services.cloudSettings.syncStatus {
        case .cloudKitConnected: "checkmark.icloud.fill"
        case .cloudKitFallback, .iCloudAccountUnavailable: "exclamationmark.icloud.fill"
        }
    }

    private var syncColor: Color {
        switch services.cloudSettings.syncStatus {
        case .cloudKitConnected: .green
        case .cloudKitFallback, .iCloudAccountUnavailable: .orange
        }
    }

    // MARK: - Premium

    private var premiumSection: some View {
        Section("Subscription") {
            NavigationLink {
                PremiumSettingsPage()
                    .environment(services)
            } label: {
                if services.store.isPremium {
                    Label("Premium", systemImage: "crown.fill")
                        .foregroundStyle(.yellow)
                } else {
                    Label("Unlock Premium", systemImage: "crown.fill")
                }
            }
        }
    }

    // MARK: - Social

    private var socialSection: some View {
        Section("Social") {
            NavigationLink {
                NotificationPreferencesView()
                    .environment(services)
            } label: {
                Label("Notifications", systemImage: "bell.badge.fill")
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            NavigationLink {
                DisclaimerView()
            } label: {
                Label("Legal Disclaimer", systemImage: "doc.text.fill")
            }
        }
    }

}

// MARK: - Catalog Settings Page

private struct CatalogSettingsPage: View {
    @Environment(AppServices.self) private var services
    @State private var brandPendingDisable: TCGBrand?

    private var brandsAvailableToAdd: [TCGBrand] {
        services.brandsManifest.brandsAvailableToAdd(enabled: services.brandSettings.enabledBrands)
    }

    private var sortedEnabled: [TCGBrand] {
        services.brandsManifest.sortBrands(services.brandSettings.enabledBrands)
    }

    var body: some View {
        List {
            Section {
                ForEach(sortedEnabled) { brand in
                    Text(brand.displayTitle)
                }
                .onDelete(perform: requestBrandRemoval)
                .deleteDisabled(services.brandSettings.enabledBrands.count <= 1)
            } footer: {
                Text("Removing a game deletes its downloaded catalog from this device and hides those cards from browse, wishlist, and collection until you add the game again.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Card Catalogs")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(brandsAvailableToAdd) { brand in
                        Button(brand.displayTitle) { addBrand(brand) }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(brandsAvailableToAdd.isEmpty)
            }
        }
        .alert(
            "Remove catalog?",
            isPresented: Binding(
                get: { brandPendingDisable != nil },
                set: { if !$0 { brandPendingDisable = nil } }
            ),
            presenting: brandPendingDisable
        ) { brand in
            Button("Cancel", role: .cancel) { brandPendingDisable = nil }
            Button("Delete downloaded data", role: .destructive) {
                services.brandSettings.setEnabled(brand, isOn: false)
                Task {
                    do { try await BrandCatalogMaintenance.purgeLocalData(for: brand) }
                    catch { }
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
        Task { await services.performCatalogSyncAfterEnablingBrands() }
    }

    private func requestBrandRemoval(at offsets: IndexSet) {
        let sorted = services.brandsManifest.sortBrands(services.brandSettings.enabledBrands)
        guard let index = offsets.first, sorted.indices.contains(index) else { return }
        brandPendingDisable = sorted[index]
    }
}

// MARK: - Active Game Settings Page

private struct ActiveGameSettingsPage: View {
    @Environment(AppServices.self) private var services

    private var sortedEnabled: [TCGBrand] {
        services.brandsManifest.sortBrands(services.brandSettings.enabledBrands)
    }

    var body: some View {
        List {
            Section {
                Picker(
                    "Active Game",
                    selection: Binding(
                        get: { services.brandSettings.selectedCatalogBrand },
                        set: { services.brandSettings.selectedCatalogBrand = $0 }
                    )
                ) {
                    ForEach(sortedEnabled) { brand in
                        Text(brand.displayTitle).tag(brand)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text("Changes which card game is used across browse, collection, and search.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Active Game")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Offline Settings Page

private struct OfflineSettingsPage: View {
    @Environment(AppServices.self) private var services

    private var brand: TCGBrand { services.brandSettings.selectedCatalogBrand }

    private var isEnabled: Bool {
        services.offlineImageSettings.isOfflinePackEnabled(for: brand)
    }

    private var statusLine: String? {
        services.offlineImageDownload.statusLine[brand]
    }

    private var manifestCount: Int {
        OfflineImageStore.shared.manifestKeys(for: brand).count
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        services.offlineImageSettings.setOfflinePackEnabled(newValue, for: brand)
                        if newValue {
                            Task {
                                await services.offlineImageDownload.runFullDownloadIfNeeded(
                                    brand: brand,
                                    nationalDexPokemon: services.cardData.nationalDexPokemon,
                                    sealedProducts: services.sealedProducts.products
                                )
                            }
                        } else {
                            services.offlineImageDownload.cancelDownload(for: brand)
                            Task {
                                try? OfflineImageStore.shared.deleteAll(for: brand)
                                services.offlineImageDownload.notifyPackMutated()
                            }
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Offline Mode")
                        if let status = statusLine {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if !isEnabled {
                            Text("Downloads \(OfflinePackDownloadSizeCopy.approximateLabel(for: brand)) of card images")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Downloads low-resolution card images to your device so they load without a network connection. High-resolution images in card details are still fetched when needed.")
            }

            if isEnabled {
                Section("Storage") {
                    Label("\(manifestCount) images stored locally", systemImage: "photo.on.rectangle.angled")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Offline Mode")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Pricing Settings Page

private struct PricingSettingsPage: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        List {
            Section {
                Picker("Currency", selection: Binding(
                    get: { services.priceDisplay.currency },
                    set: { services.priceDisplay.currency = $0 }
                )) {
                    ForEach(PriceDisplayCurrency.allCases) { c in
                        Text(c.pickerTitle).tag(c)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text("Catalog and history values from the server are in US dollars. Pounds use a daily exchange rate.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Pricing & Currency")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Data Sync Settings Page

private struct DataSyncSettingsPage: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        List {
            Section {
                syncStatusRow
                if case .iCloudAccountUnavailable = services.cloudSettings.syncStatus {
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } header: {
                Text("Status")
            } footer: {
                statusFooter
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("iCloud Sync")
        .navigationBarTitleDisplayMode(.large)
    }

    private var syncStatusRow: some View {
        switch services.cloudSettings.syncStatus {
        case .cloudKitConnected:
            return Label("iCloud connected", systemImage: "checkmark.icloud.fill")
                .foregroundStyle(.green)
        case .cloudKitFallback:
            return Label("CloudKit sync failed", systemImage: "exclamationmark.icloud.fill")
                .foregroundStyle(.orange)
        case .iCloudAccountUnavailable:
            return Label("iCloud not available", systemImage: "exclamationmark.icloud.fill")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var statusFooter: some View {
        switch services.cloudSettings.syncStatus {
        case .cloudKitFallback:
            Text("This build is using local-only storage because the CloudKit store could not be opened on this device yet.")
        case .cloudKitConnected:
            Text("Your wishlist, collection, and ledger data are stored locally and synced through your private iCloud database. After reinstalling, data may take several minutes to finish syncing from iCloud.")
        case .iCloudAccountUnavailable:
            Text("You can still use the app offline, but CloudKit sync stays off until this device is signed into iCloud.")
        }
    }
}

// MARK: - Premium Settings Page

private struct PremiumSettingsPage: View {
    @Environment(AppServices.self) private var services
    @State private var showPaywall = false

    var body: some View {
        List {
            Section {
                if services.store.isPremium {
                    Label("Premium active", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        showPaywall = true
                    } label: {
                        Label("Unlock Premium", systemImage: "crown.fill")
                    }
                }

                Button {
                    Task { try? await services.store.restore() }
                } label: {
                    Label("Restore Purchases", systemImage: "arrow.clockwise")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Premium")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showPaywall) {
            PaywallSheet()
                .environment(services)
                .presentationDragIndicator(.visible)
        }
    }
}
