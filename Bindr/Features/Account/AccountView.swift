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
            devToolsSection
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
            Label("Pokémon TCG", systemImage: "square.stack.3d.up.fill")
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

    // MARK: - Developer

    private var devToolsSection: some View {
        Section("Developer") {
            NavigationLink {
                DevToolsSettingsPage()
                    .environment(services)
            } label: {
                Label("Developer Tools", systemImage: "hammer.fill")
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

// MARK: - Developer Tools Page

private struct DevToolsSettingsPage: View {
    @Environment(AppServices.self) private var services

    private var r2Configured: Bool {
        AppConfiguration.r2BaseURL.host != "invalid.local"
    }

    var body: some View {
        List {
            Section {
                Button {
                    Task { await services.forcePricingRefreshFromSettings() }
                } label: {
                    HStack {
                        Label("Refresh pricing from R2", systemImage: "arrow.clockwise.circle.fill")
                        Spacer()
                        if services.isCatalogDownloadInProgress {
                            ProgressView()
                        }
                    }
                }
                .disabled(
                    !r2Configured
                        || services.brandSettings.enabledBrands.isEmpty
                        || services.isCatalogDownloadInProgress
                )
            } footer: {
                if !r2Configured {
                    Text("R2 is not configured in this build, so pricing cannot be downloaded.")
                } else if !services.brandSettings.enabledBrands.isEmpty {
                    Text("Re-downloads market pricing, daily price buckets, sealed product prices, and trend data from R2. This bypasses the usual daily 03:00 refresh schedule.")
                } else {
                    Text("Enable at least one card catalog in Settings before refreshing pricing.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Developer Tools")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Premium Settings Page

private struct PremiumSettingsPage: View {
    @Environment(AppServices.self) private var services
    @State private var showPaywall = false
    @State private var restoreAlertMessage: String?

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
                    Task { await runRestore() }
                } label: {
                    HStack {
                        Label("Restore Purchases", systemImage: "arrow.clockwise")
                        Spacer()
                        if services.store.isRestoring {
                            ProgressView()
                        }
                    }
                }
                .disabled(services.store.isRestoring)
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
        .alert("Restore Purchases", isPresented: Binding(
            get: { restoreAlertMessage != nil },
            set: { if !$0 { restoreAlertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreAlertMessage ?? "")
        }
    }

    private func runRestore() async {
        do {
            try await services.store.restore()
            if services.store.isPremium {
                restoreAlertMessage = "Your Premium subscription has been restored."
            } else {
                restoreAlertMessage = services.store.restoreMessage
                    ?? "No active subscription was found for this Apple ID."
            }
        } catch {
            restoreAlertMessage = error.localizedDescription
        }
    }
}
