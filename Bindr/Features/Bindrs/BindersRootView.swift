import SwiftUI
import SwiftData

struct BindersRootView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @Query(sort: \Binder.createdAt, order: .reverse) private var binders: [Binder]

    @Binding var showCreateSheet: Bool
    @State private var isEditing = false
    @State private var showPaywall = false
    @State private var binderToDelete: Binder?
    @State private var presentedBinder: Binder?
    @State private var showDeleteConfirm = false

    private var activeBrand: TCGBrand { services.brandSettings.selectedCatalogBrand }
    private var visibleBinders: [Binder] {
        binders.filter { $0.tcgBrand == activeBrand }
    }

    var body: some View {
        VStack(spacing: 0) {
            bindersHeader
            Group {
                if binders.isEmpty {
                    ScrollView {
                        ContentUnavailableView {
                            Label("No Binders", systemImage: "books.vertical")
                        } description: {
                            Text("Create a binder to organise your cards.")
                        } actions: {
                            Button("Create a Binder") { handleCreateTap() }
                                .buttonStyle(.borderedProminent)
                        }
                        .frame(minHeight: 300)
                    }
                } else if visibleBinders.isEmpty {
                    ScrollView {
                        ContentUnavailableView {
                            Label("No \(activeBrand.displayTitle) Binders", systemImage: "books.vertical")
                        } description: {
                            Text("Create a binder for \(activeBrand.displayTitle) to organise those cards.")
                        } actions: {
                            Button("Create a Binder") { handleCreateTap() }
                                .buttonStyle(.borderedProminent)
                        }
                        .frame(minHeight: 300)
                    }
                } else {
                    ScrollView {
                        // Cards now render in an A4 portrait ratio (~160 × 230),
                        // so allow each grid cell a bit more horizontal room
                        // and a touch more vertical spacing between rows.
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 14)], spacing: 16) {
                            ForEach(visibleBinders) { binder in
                                Button {
                                    presentedBinder = binder
                                } label: {
                                    ZStack(alignment: .topTrailing) {
                                        BinderCardCell(binder: binder)
                                        
                                        if isEditing {
                                            Button {
                                                binderToDelete = binder
                                                showDeleteConfirm = true
                                            } label: {
                                                Image(systemName: "minus.circle.fill")
                                                    .font(.title3)
                                                    .foregroundStyle(.red)
                                                    .background(Circle().fill(.white).padding(2))
                                            }
                                            .transition(.scale.combined(with: .opacity))
                                            .padding(8)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        binderToDelete = binder
                                        showDeleteConfirm = true
                                    } label: {
                                        Label("Delete Binder", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8 + rootFloatingChromeInset)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: $presentedBinder) { binder in
            BinderDetailView(binder: binder)
                .environment(services)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateBinderSheet()
                .environment(services)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet()
                .environment(services)
        }
        .alert("Delete Binder?", isPresented: $showDeleteConfirm, presenting: binderToDelete) { binder in
            Button("Delete \"\(binder.title)\"", role: .destructive) {
                modelContext.delete(binder)
            }
            Button("Cancel", role: .cancel) {}
        } message: { binder in
            Text("This will permanently remove \"\(binder.title)\" and all its cards.")
        }
        .task(id: binders.map(\.id).map(\.uuidString).sorted().joined(separator: ",")) {
            do {
                try await services.socialShare.reconcileDeletedBinders(localBinderIDs: Set(binders.map(\.id)))
            } catch {
                // Silent best-effort cleanup.
            }
        }
    }

    // MARK: - Header

    private var bindersHeader: some View {
        ZStack {
            Text("Binders")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)

            HStack {
                ChromeGlassCircleButton(accessibilityLabel: "Back") {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }

                Spacer()

                HStack(spacing: 8) {
                    ChromeGlassCircleButton(accessibilityLabel: isEditing ? "Done" : "Edit") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isEditing.toggle()
                        }
                    } label: {
                        Image(systemName: isEditing ? "checkmark" : "pencil")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                    }

                    ChromeGlassCircleButton(accessibilityLabel: "Create Binder") { handleCreateTap() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func handleCreateTap() {
        if !services.store.isPremium && visibleBinders.count >= 1 {
            showPaywall = true
        } else {
            showCreateSheet = true
        }
    }
}

private struct BinderCardCell: View {
    @Environment(AppServices.self) private var services
    let binder: Binder
    @State private var cardURLs: [URL?] = [nil, nil, nil]
    @State private var totalUSDValue: Double = 0
    @State private var hasLoadedValue: Bool = false

    var body: some View {
        BinderCoverView(
            title: binder.title,
            subtitle: subtitleText,
            colourName: binder.colour,
            texture: binder.textureKind,
            seed: binder.textureSeed,
            peekingCardURLs: cardURLs,
            showCardPreview: binder.showCardPreview,
            compact: true,
            valueText: displayedValueText
        )
        .task {
            await loadCardURLs()
            await refreshTotalValue()
        }
    }

    /// Subtitle now leads with the binder grade ("RAW") followed by the card
    /// count, matching the look of the new cover layout.
    private var subtitleText: String {
        let count = binder.slotList.count
        return "RAW · \(count) \(count == 1 ? "card" : "cards")"
    }

    /// Returns the formatted total value once prices have been fetched. We
    /// hide the label entirely for empty binders so a "£0" doesn't dominate
    /// brand-new covers — once cards are added the value appears.
    private var displayedValueText: String? {
        guard hasLoadedValue, !binder.slotList.isEmpty else { return nil }
        return formatTotal(usd: totalUSDValue)
    }

    private func formatTotal(usd: Double) -> String {
        let display = services.priceDisplay.currency
        let amount = display == .gbp ? usd * services.pricing.usdToGbp : usd

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if amount >= 1000 {
            formatter.maximumFractionDigits = 0
            formatter.minimumFractionDigits = 0
        } else {
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
        }
        let pretty = formatter.string(from: NSNumber(value: amount)) ?? "0"
        return "\(display.symbol)\(pretty)"
    }

    private func loadCardURLs() async {
        let slots = binder.slotList.prefix(3)
        var urls: [URL?] = []

        for slot in slots {
            if let card = await services.cardData.loadCard(masterCardId: slot.cardID) {
                urls.append(AppConfiguration.imageURL(relativePath: card.imageLowSrc))
            } else {
                urls.append(nil)
            }
        }

        while urls.count < 3 { urls.append(nil) }
        cardURLs = urls
    }

    /// Sums every slot's USD market price the same way ``BinderDetailView``
    /// does, so the cover front mirrors what the user sees inside the binder.
    private func refreshTotalValue() async {
        var sum: Double = 0
        for slot in binder.slotList {
            guard let card = await services.cardData.loadCard(masterCardId: slot.cardID) else { continue }
            if let usd = await services.pricing.usdPriceForVariant(
                for: card,
                variantKey: slot.variantKey
            ) {
                sum += usd
            }
        }
        totalUSDValue = sum
        hasLoadedValue = true
    }
}

