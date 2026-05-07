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
    /// Measured height of the translucent floating header. Read by
    /// `safeAreaInset` so scroll content reserves exactly the right top
    /// gutter — keeps padding in lockstep with header changes (e.g. font
    /// scaling) without hard-coding a constant.
    @State private var bindersHeaderHeight: CGFloat = 64

    private var activeBrand: TCGBrand { services.brandSettings.selectedCatalogBrand }
    private var visibleBinders: [Binder] {
        binders.filter { $0.tcgBrand == activeBrand }
    }

    var body: some View {
        // ZStack overlay pattern (matches Social + Dashboard):
        // content scrolls under a translucent floating header rather than
        // sitting beneath an opaque title bar. `safeAreaInset` reserves the
        // top space so the first row of binders doesn't slip under the
        // header; `bindersHeader` itself paints `.ultraThinMaterial`.
        ZStack(alignment: .top) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: bindersHeaderHeight)
                }
            bindersHeader
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: BindersHeaderHeightKey.self, value: geo.size.height)
                    }
                )
                .onPreferenceChange(BindersHeaderHeightKey.self) { bindersHeaderHeight = $0 }
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

    // MARK: - Content

    /// Scroll content extracted from `body` so the ZStack overlay can wrap
    /// it cleanly. The empty/empty-for-brand/populated branches keep the
    /// behaviour identical to the previous VStack layout — the only
    /// structural change is that the parent now owns the safe-area inset.
    @ViewBuilder
    private var content: some View {
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
                // so allow each grid cell a bit more horizontal room and a
                // touch more vertical spacing between rows.
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
                            .tint(.red)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8 + rootFloatingChromeInset)
            }
        }
    }

    // MARK: - Header

    private var bindersHeader: some View {
        BindrPageHeader(
            title: "Binders",
            leading: {
                ChromeGlassCircleButton(accessibilityLabel: "Back") {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }
            },
            trailing: {
                ChromeGlassCircleButton(accessibilityLabel: "Create Binder") { handleCreateTap() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
        )
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
            valueText: displayedValueText,
            titleTextColor: binder.titleTextColorKind,
            titleFontStyle: binder.titleFontStyleKind
        )
        .task {
            await loadCardURLs()
            await refreshTotalValue()
        }
    }

    /// Subtitle displays only the binder card count.
    private var subtitleText: String {
        let count = binder.slotList.count
        return "\(count) \(count == 1 ? "card" : "cards")"
    }

    /// Returns the formatted total value once prices have been fetched. We
    /// hide the label entirely for empty binders so a "£0" doesn't dominate
    /// brand-new covers — once cards are added the value appears.
    private var displayedValueText: String? {
        guard binder.showValueOnCover, hasLoadedValue, !binder.slotList.isEmpty else { return nil }
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

/// Preference key used by ``BindersRootView`` to read its own translucent
/// header height back into a `safeAreaInset` so scroll content reserves the
/// exact pixel-perfect amount of top space for the floating header.
private struct BindersHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 64
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
