import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @Query private var collectionItems: [CollectionItem]
    @State private var showPaywall = false
    @State private var showDataExport = false
    @State private var showDisclaimer = false
    @State private var brandPendingDisable: TCGBrand?
    @State private var showForceRedownloadPrompt = false
    @State private var isRecalculating = false
    @State private var recalcDone = false
    @State private var isRefreshingMarketTrend = false
    @State private var marketTrendRefreshDone = false

    /// Brands the user has not added yet (shown in the Add menu). Order follows the hosted `brands.json`.
    private var brandsAvailableToAdd: [TCGBrand] {
        services.brandsManifest.brandsAvailableToAdd(enabled: services.brandSettings.enabledBrands)
    }

    /// Enabled brands ordered for user-facing controls.
    private var sortedEnabledBrands: [TCGBrand] {
        services.brandsManifest.sortBrands(services.brandSettings.enabledBrands)
    }

    var body: some View {
        List {
            settingsHero
            topSections
            bottomSections
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
        .contentMargins(.top, rootFloatingChromeInset, for: .scrollContent)
        .sheet(isPresented: $showPaywall) {
            PaywallSheet()
                .environment(services)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDataExport) {
            DataExportView()
                .environment(services)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDisclaimer) {
            DisclaimerView()
                .presentationDragIndicator(.visible)
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
                Task {
                    do {
                        try await BrandCatalogMaintenance.purgeLocalData(for: brand)
                    } catch {
                        // Best-effort; UI still disables the brand.
                    }
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
        .alert("Force re-download catalog data?", isPresented: $showForceRedownloadPrompt) {
            Button("Cancel", role: .cancel) {}
            Button("Re-download", role: .destructive) {
                Task { await services.forceCatalogRedownloadFromSettings() }
            }
        } message: {
            Text("This will delete downloaded card catalog data on this device and fetch it again into SQLite for your enabled games.")
        }
    }

    private var settingsHero: some View {
        Section {
            Text("Settings")
                .font(.system(size: 36, weight: .bold, design: .default))
                .foregroundStyle(.primary)
                .padding(.top, 20)
                .padding(.bottom, 8)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder private var topSections: some View {
        Section {
            Picker(
                "Active Game",
                selection: Binding(
                    get: { services.brandSettings.selectedCatalogBrand },
                    set: { services.brandSettings.selectedCatalogBrand = $0 }
                )
            ) {
                ForEach(sortedEnabledBrands) { brand in
                    Text(brand.displayTitle).tag(brand)
                }
            }
        } header: {
            Text("Active Game")
        } footer: {
            Text("Changes which card game is used across browse, collection, and search.")
        }

        CatalogSection(brandsAvailableToAdd: brandsAvailableToAdd, onAdd: addBrand, onDelete: requestBrandRemoval)

        OfflineModeSection()

        Section("Pricing") {
            Picker("Show prices in", selection: Binding(
                get: { services.priceDisplay.currency },
                set: { services.priceDisplay.currency = $0 }
            )) {
                ForEach(PriceDisplayCurrency.allCases) { c in Text(c.pickerTitle).tag(c) }
            }
            Text("Catalog and history values from the server are in US dollars. Pounds use a daily exchange rate.")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                guard !isRecalculating else { return }
                isRecalculating = true
                recalcDone = false
                let items = collectionItems
                Task {
                    await services.pricing.refreshFXRate()
                    services.pricing.clearSetPricingMemoryCache()
                    let liveSnapshot = await computeLiveSnapshot(items: items)
                    print("[Recalc] items=\(items.count) liveSnapshot=\(liveSnapshot?.total as Any) collectionValue=\(services.collectionValue != nil)")
                    if let liveSnapshot {
                        await services.collectionValue?.forceRecalculate(
                            liveSnapshot: liveSnapshot,
                            collectionItems: items
                        )
                    }
                    services.requestDashboardMarketReload()
                    isRecalculating = false
                    recalcDone = true
                }
            } label: {
                if isRecalculating {
                    Label("Recalculating…", systemImage: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                } else if recalcDone {
                    Label("Recalculation complete", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else {
                    Label("Recalculate dashboard values", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isRecalculating)
            Button {
                guard !isRefreshingMarketTrend else { return }
                isRefreshingMarketTrend = true
                marketTrendRefreshDone = false
                Task {
                    await services.forceMarketTrendRefreshFromSettings()
                    isRefreshingMarketTrend = false
                    marketTrendRefreshDone = true
                }
            } label: {
                if isRefreshingMarketTrend {
                    Label("Refreshing market data…", systemImage: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                } else if marketTrendRefreshDone {
                    Label("Market data refreshed", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else {
                    Label("Refresh market trend data", systemImage: "chart.line.uptrend.xyaxis")
                }
            }
            .disabled(isRefreshingMarketTrend)
        }
    }

    @ViewBuilder private var bottomSections: some View {
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

        Section("Premium") {
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
                Label("Restore purchases", systemImage: "arrow.clockwise")
            }
        }

        Section {
            Button {
                showDataExport = true
            } label: {
                Label("Export Data", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                showForceRedownloadPrompt = true
            } label: {
                Label("Force Re-download Catalog", systemImage: "arrow.triangle.2.circlepath")
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Use this when catalog fields change (for example new set metadata) and you need a full fresh download.")
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
            Button {
                showDisclaimer = true
            } label: {
                Label("Legal Disclaimer", systemImage: "doc.text")
            }
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

    private func computeLiveSnapshot(items: [CollectionItem]) async -> BrandSnapshot? {
        var pokemon = 0.0
        var onePiece = 0.0
        await services.sealedProducts.loadFromLocalIfAvailable()
        for item in items {
            let qty = max(item.quantity, 0)
            guard qty > 0, item.sealedStatus != SealedInventoryStatus.opened.rawValue else { continue }
            let usd: Double
            if let pid = sealedProductID(for: item),
               let p = services.sealedProducts.marketPriceUSD(for: pid) {
                usd = p * Double(qty)
            } else {
                guard let card = await services.cardData.loadCard(masterCardId: item.cardID) else { continue }
                let grade: String = {
                    guard let c = item.gradingCompany else { return "raw" }
                    switch c.uppercased() {
                    case "PSA": return "psa10"
                    case "ACE": return "ace10"
                    default: return "raw"
                    }
                }()
                usd = (await services.pricing.usdPriceForVariantAndGrade(for: card, variantKey: item.variantKey, grade: grade) ?? 0) * Double(qty)
            }
            let gbp = usd * services.pricing.usdToGbp
            switch TCGBrand.inferredFromMasterCardId(item.cardID) {
            case .pokemon: pokemon += gbp
            case .onePiece: onePiece += gbp
            }
        }
        let total = pokemon + onePiece
        guard total > 0 else { return nil }
        return BrandSnapshot(total: total, pokemon: pokemon, onePiece: onePiece)
    }

    private func sealedProductID(for item: CollectionItem) -> Int? {
        if let rawID = item.sealedProductId, let id = Int(rawID), id > 0 { return id }
        return SealedProduct.parseCollectionProductID(item.cardID)
    }

}

private struct OfflineModeSection: View {
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
                    Text("Offline Mode")
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
            if isEnabled {
                Text("\(manifestCount) images stored locally")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Offline")
        } footer: {
            Text("Downloads low-resolution card images to your device so they load without a network connection. High-resolution images in card details are still fetched when needed.")
        }
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
