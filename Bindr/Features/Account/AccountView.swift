import SwiftUI
import SwiftData

// MARK: - Root Settings Page

struct SettingsView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        ScrollView {
            VStack(spacing: BindrSpacing.xl) {
                BindrMenuSection(title: "Account") {
                    BindrMenuNavigationRow(
                        title: services.store.isPremium ? "Premium" : "Unlock Premium",
                        systemImage: "crown.fill",
                        color: .yellow
                    ) {
                        PremiumSettingsPage()
                            .environment(services)
                    }

                    BindrMenuNavigationRow(
                        title: "Account & Privacy",
                        systemImage: "person.crop.circle.badge.checkmark",
                        color: .gray
                    ) {
                        MyAccountPrivacyView()
                            .environment(services)
                    }
                }

                BindrMenuSection(title: "Storage & Pricing") {
                    BindrMenuNavigationRow(
                        title: "Offline Mode",
                        systemImage: "arrow.down.circle.fill",
                        color: .blue
                    ) {
                        OfflineSettingsPage()
                            .environment(services)
                    }

                    BindrMenuNavigationRow(
                        title: "Pricing & Currency",
                        systemImage: "dollarsign.circle.fill",
                        color: .green
                    ) {
                        PricingSettingsPage()
                            .environment(services)
                    }

                    BindrMenuNavigationRow(
                        title: "Library Storage",
                        systemImage: "internaldrive.fill",
                        color: .orange
                    ) {
                        LibraryStorageSettingsPage()
                            .environment(services)
                    }

                    BindrMenuNavigationRow(
                        title: "Backup and Restore",
                        systemImage: "arrow.triangle.2.circlepath.icloud",
                        color: .cyan
                    ) {
                        BackupRestoreSettingsPage()
                            .environment(services)
                    }
                }

                BindrMenuSection(title: "Social") {
                    BindrMenuNavigationRow(
                        title: "Notifications",
                        systemImage: "bell.badge.fill",
                        color: .red
                    ) {
                        NotificationPreferencesView()
                            .environment(services)
                    }
                }

                #if DEBUG
                BindrMenuSection(title: "Developer") {
                    BindrMenuNavigationRow(
                        title: "Developer Tools",
                        systemImage: "hammer.fill",
                        color: .purple
                    ) {
                        DevToolsSettingsPage()
                            .environment(services)
                    }
                }
                #endif
            }
            .padding(.horizontal, BindrSpacing.lg)
            .padding(.top, BindrSpacing.lg)
            .padding(.bottom, BindrSpacing.xxl)
        }
        .bindrPageBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - My Account & Privacy

struct MyAccountPrivacyView: View {
    @Environment(AppServices.self) private var services
    @AppStorage("Bindr.privacy.shareWishlist") private var shareWishlist = true
    @AppStorage("Bindr.privacy.shareCollection") private var shareCollection = true
    @AppStorage("Bindr.privacy.shareBinders") private var shareBinders = true
    @AppStorage("Bindr.privacy.shareDecks") private var shareDecks = true
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?

    var body: some View {
        List {
            Section {
                Label(services.socialAuth.isSignedIn ? "Signed in to Bindr" : "Not signed in", systemImage: "person.crop.circle.fill")
                    .foregroundStyle(services.socialAuth.isSignedIn ? BindrPalette.ownedGreen : .secondary)
            } footer: {
                Text("Manage what parts of your collection can appear on your social profile and shared posts.")
            }

            Section {
                Toggle("Share wishlist", isOn: $shareWishlist)
                Toggle("Share collection", isOn: $shareCollection)
                Toggle("Share binders", isOn: $shareBinders)
                Toggle("Share decks", isOn: $shareDecks)
            } header: {
                Text("Social Sharing")
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Label("Delete Account and Data", systemImage: "trash.fill")
                        Spacer()
                        if isDeletingAccount {
                            ProgressView()
                        }
                    }
                }
                .disabled(!services.socialAuth.isSignedIn || isDeletingAccount)

                if let deleteAccountError {
                    Text(deleteAccountError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Account")
            } footer: {
                Text("Permanently deletes your Bindr account, social profile, posts, comments, trades, friendships, and cloud backup. Your local collection, binders, decks, ledger, and wishlist on this device are also removed.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Account & Privacy")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog(
            "Delete account and data?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account and Data", role: .destructive) {
                Task { await deleteAccountAndData() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Your account, cloud backup, and all local library data on this device will be permanently deleted.")
        }
    }

    @MainActor
    private func deleteAccountAndData() async {
        isDeletingAccount = true
        deleteAccountError = nil
        defer { isDeletingAccount = false }

        do {
            try await services.deleteAccountAndAllData()
        } catch {
            deleteAccountError = error.localizedDescription
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

// MARK: - Library Storage Settings Page

struct LibraryStorageSettingsPage: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @State private var inventory = LibraryInventoryCounts()
    @State private var downloadStatus: CatalogDownloadStatus? = nil
    @State private var isLoadingDownloadStatus = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        List {
            Section {
                Label("Stored on this device", systemImage: "internaldrive.fill")
                    .foregroundStyle(.green)
            } footer: {
                Text("Your library is saved locally on this iPhone or iPad. Bindr Cloud Backup keeps your library and app preferences online for reinstall and disaster recovery — use Backup and Restore in Settings to manage it.")
            }

            Section {
                inventoryRow("Collection cards", count: inventory.collectionCards, systemImage: "square.stack.3d.up.fill")
                inventoryRow("Wishlist", count: inventory.wishlistItems, systemImage: "heart.fill")
                inventoryRow("Binders", count: inventory.binders, systemImage: "book.closed.fill")
                inventoryRow("Decks", count: inventory.decks, systemImage: "rectangle.stack.fill")
                inventoryRow("Activity ledger", count: inventory.ledgerLines, systemImage: "list.bullet.rectangle")
                inventoryRow("Daily value snapshots", count: inventory.dailyValueSnapshots, systemImage: "chart.line.uptrend.xyaxis")
                inventoryRow("Weekly averages", count: inventory.weeklyAverages, systemImage: "calendar")
                inventoryRow("Monthly averages", count: inventory.monthlyAverages, systemImage: "calendar.badge.clock")
            } header: {
                Text("On this device")
            }

            if let status = downloadStatus {
                ForEach(status.sections, id: \.section.rawValue) { pair in
                    Section {
                        ForEach(pair.entries) { entry in
                            downloadStatusRow(entry)
                        }
                    } header: {
                        Text(pair.section.rawValue)
                    }
                }
                Section {} footer: {
                    Text("Checked \(Self.relativeFormatter.localizedString(for: status.queriedAt, relativeTo: Date()))")
                        .foregroundStyle(.tertiary)
                }
            } else {
                Section {
                    if isLoadingDownloadStatus {
                        HStack {
                            ProgressView()
                            Text("Checking downloads…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Data downloads")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Library Storage")
        .navigationBarTitleDisplayMode(.large)
        .task {
            reloadInventory()
            await reloadDownloadStatus()
        }
        .onChange(of: services.collectionInventoryRevision) { _, _ in reloadInventory() }
    }

    private func reloadInventory() {
        inventory = services.libraryInventoryCounts(modelContext: modelContext)
    }

    private func reloadDownloadStatus() async {
        isLoadingDownloadStatus = true
        downloadStatus = await services.cardData.fetchDownloadStatus()
        isLoadingDownloadStatus = false
    }

    private func inventoryRow(_ title: String, count: Int, systemImage: String) -> some View {
        LabeledContent {
            Text("\(count)")
                .foregroundStyle(count > 0 ? .primary : .secondary)
                .monospacedDigit()
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    @ViewBuilder
    private func downloadStatusRow(_ entry: CatalogDownloadStatusEntry) -> some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                if let date = entry.lastDownloaded {
                    Text(Self.relativeFormatter.localizedString(for: date, relativeTo: Date()))
                        .foregroundStyle(entry.isStale ? .orange : .secondary)
                        .font(.subheadline)
                } else {
                    Text("Never")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
                if let detail = entry.detail {
                    Text(detail)
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
        } label: {
            Label {
                Text(entry.title)
            } icon: {
                Image(systemName: entry.systemImage)
                    .foregroundStyle(entry.isStale ? .orange : (entry.lastDownloaded == nil ? .red : .secondary))
            }
        }
    }
}

// MARK: - Backup & Restore Settings Page

struct BackupRestoreSettingsPage: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @State private var isRestoring = false
    @State private var isBackingUp = false
    @State private var restoreMessage: String?
    @State private var backupMessage: String?
    @State private var showReplaceRestoreConfirmation = false

    var body: some View {
        List {
            Section {
                Button {
                    Task { await runCloudBackupUpload() }
                } label: {
                    HStack {
                        Label("Publish Library to Bindr Cloud", systemImage: "icloud.and.arrow.up.fill")
                        Spacer()
                        if isBackingUp || services.collectionSync.isUploading {
                            ProgressView()
                        }
                    }
                }
                .disabled(
                    isBackingUp
                    || services.collectionSync.isUploading
                    || !services.socialAuth.isSignedIn
                )

                if let backupMessage {
                    Text(backupMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let lastUploadedAt = services.collectionSync.lastUploadedAt,
                          let summary = services.collectionSync.lastUploadedSummary {
                    Text("Last backed up \(lastUploadedAt.formatted(date: .abbreviated, time: .shortened)) — \(summary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let error = services.collectionSync.lastUploadError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("Your account backup: collection, wishlist, binders, decks, ledger, value history, and app preferences (theme, currency, grid and filter settings). Uploads automatically when your library or preferences change. After reinstall, everything restores when you're signed in to Bindr.")
            }

            Section {
                Button {
                    if localLibraryHasData {
                        showReplaceRestoreConfirmation = true
                    } else {
                        Task { await runCloudBackupRestore(force: false) }
                    }
                } label: {
                    HStack {
                        Label("Restore from Cloud Backup", systemImage: "arrow.triangle.2.circlepath.icloud")
                        Spacer()
                        if isRestoring || services.collectionSync.isRestoring {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRestoring || services.collectionSync.isRestoring || !services.socialAuth.isSignedIn)

                if let restoreMessage {
                    Text(restoreMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let lastRestoredAt = services.collectionSync.lastRestoredAt {
                    Text(restoreStatusLine(lastRestoredAt: lastRestoredAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let error = services.collectionSync.lastRestoreError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("Replaces everything on this device with your latest Bindr cloud backup — collection, wishlist, binders, decks, ledger, and value history. Happens automatically after reinstall when you're signed in; tap above to restore manually.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Backup and Restore")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog(
            "Replace local library?",
            isPresented: $showReplaceRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace with cloud backup", role: .destructive) {
                Task { await runCloudBackupRestore(force: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces your current collection, binders, decks, ledger, and wishlist on this device with your cloud backup.")
        }
    }

    private var localLibraryHasData: Bool {
        !UserLibraryBackupCodec.localLibraryIsEmpty(modelContext)
    }

    private func restoreStatusLine(lastRestoredAt: Date) -> String {
        if let summary = services.collectionSync.lastRestoredSummary {
            return "Last restored \(lastRestoredAt.formatted(date: .abbreviated, time: .shortened)) — \(summary)"
        }
        return "Last restored \(lastRestoredAt.formatted(date: .abbreviated, time: .shortened)) — \(services.collectionSync.lastRestoredCardCount) cards"
    }

    private func runCloudBackupUpload() async {
        isBackingUp = true
        backupMessage = nil
        defer { isBackingUp = false }

        guard services.socialAuth.isSignedIn else {
            backupMessage = "Sign in to your Bindr account first."
            return
        }

        let uploaded = await services.backupLibraryToCloud()
        if uploaded, let summary = services.collectionSync.lastUploadedSummary {
            backupMessage = "Backed up \(summary)."
        } else if let error = services.collectionSync.lastUploadError {
            backupMessage = error
        } else {
            backupMessage = "Nothing to back up yet."
        }
    }

    private func runCloudBackupRestore(force: Bool) async {
        isRestoring = true
        restoreMessage = nil
        defer { isRestoring = false }

        guard services.socialAuth.isSignedIn else {
            restoreMessage = "Sign in to your Bindr account first."
            return
        }

        let restored = await services.restoreCollectionFromCloudBackup(force: force)
        if restored {
            if let summary = services.collectionSync.lastRestoredSummary {
                restoreMessage = "Restored \(summary)."
            } else {
                restoreMessage = "Restored \(services.collectionSync.lastRestoredCardCount) cards from cloud backup."
            }
        } else if let error = services.collectionSync.lastRestoreError {
            restoreMessage = error
        } else {
            restoreMessage = "No cloud backup found, or your library is already on this device."
        }
    }
}

// MARK: - Developer Tools Page

#if DEBUG
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
#endif

// MARK: - Premium Settings Page

struct PremiumSettingsPage: View {
    @Environment(AppServices.self) private var services
    @State private var showPaywall = false
    @State private var showRestoreAlert = false
    @State private var restoreAlertMessage = ""

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
                    Haptics.lightImpact()
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
        .alert("Restore Purchases", isPresented: $showRestoreAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreAlertMessage)
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
            restoreAlertMessage = services.store.purchaseError ?? error.localizedDescription
        }
        showRestoreAlert = true
    }
}
