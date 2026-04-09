import SwiftData
import SwiftUI

struct CardBrowseDetailView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    let cards: [Card]
    @State private var index: Int
    @State private var navigationPath = NavigationPath()

    /// Scrydex-style keys from pricing JSON for the open card (for wishlist).
    @State private var wishlistVariantKeys: [String] = ["normal"]
    @State private var showWishlistPaywall = false
    @State private var wishlistAlertMessage: String?
    @State private var showWishlistAlert = false
    @State private var addToCollectionPayload: AddToCollectionSheetPayload?

    init(cards: [Card], startIndex: Int) {
        self.cards = cards
        let clamped: Int = {
            guard !cards.isEmpty else { return 0 }
            return min(max(0, startIndex), cards.count - 1)
        }()
        _index = State(initialValue: clamped)
    }

    private var currentCard: Card? {
        guard cards.indices.contains(index) else { return cards.first }
        return cards[index]
    }

    private var currentSet: TCGSet? {
        guard let card = currentCard else { return nil }
        return services.cardData.sets.first { $0.setCode == card.setCode }
    }

    /// Filled wishlist star — gold (not system accent / blue).
    private static let wishlistActiveStarColor = Color(red: 0.98, green: 0.78, blue: 0.18)

    /// `Menu` labels pick up accent (blue) unless tinted; + should read white on dark card chrome.
    private var collectionPlusGlyphColor: Color {
        colorScheme == .dark ? .white : Color.primary
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .top) {
                if cards.isEmpty {
                    ContentUnavailableView("No card", systemImage: "rectangle.on.rectangle.slash")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TabView(selection: $index) {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { i, card in
                            CardBrowseDetailPage(card: card)
                                .tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Avoid an opaque page container so the overlay header can read as truly clear over one background.
                    .background(Color.clear)
                    .ignoresSafeArea(edges: .top)
                }

                headerRow
            }
            .background(pageChromeBackground)
            .navigationBarHidden(true)
            .navigationDestination(for: TCGSet.self) { set in
                SetCardsView(set: set)
            }
            .navigationDestination(for: NationalDexPokemon.self) { mon in
                DexCardsView(dexId: mon.nationalDexNumber, displayName: mon.displayName)
            }
            .task(id: index) {
                await loadWishlistVariantKeys()
            }
        }
        .presentationBackground(pageChromeBackground)
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .presentationCornerRadius(20)
        .sheet(isPresented: $showWishlistPaywall) {
            PaywallSheet()
                .environment(services)
        }
        .alert("Wishlist", isPresented: $showWishlistAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(wishlistAlertMessage ?? "")
        }
        .sheet(item: $addToCollectionPayload) { payload in
            AddToCollectionSheet(card: payload.card, variantKey: payload.variantKey)
                .environment(services)
        }
    }

    private var isCurrentCardOnWishlist: Bool {
        guard let card = currentCard, let wl = services.wishlist else { return false }
        return wl.isInWishlist(cardID: card.masterCardId)
    }

    private var singleAvailableVariantKey: String? {
        wishlistVariantKeys.count == 1 ? wishlistVariantKeys[0] : nil
    }

    private func loadWishlistVariantKeys() async {
        guard let card = currentCard else { return }
        var keys = await services.pricing.variantKeys(for: card)
        if keys.isEmpty, let pv = card.pricingVariants, !pv.isEmpty {
            keys = pv
        }
        if keys.isEmpty {
            keys = ["normal"]
        }
        wishlistVariantKeys = keys
    }

    private func addToWishlist(variantKey: String) {
        guard let card = currentCard else { return }
        guard let wl = services.wishlist else {
            wishlistAlertMessage = "Wishlist isn’t available yet. Try again in a moment."
            showWishlistAlert = true
            return
        }
        do {
            try wl.addItem(cardID: card.masterCardId, variantKey: variantKey, notes: "")
        } catch let e as WishlistError {
            switch e {
            case .limitReached:
                showWishlistPaywall = true
            case .alreadyExists:
                wishlistAlertMessage = "This card and variant are already on your wishlist."
                showWishlistAlert = true
            case .saveFailed(let err):
                wishlistAlertMessage = err.localizedDescription
                showWishlistAlert = true
            }
        } catch {
            wishlistAlertMessage = error.localizedDescription
            showWishlistAlert = true
        }
    }

    private func removeCurrentCardFromWishlist() {
        guard let card = currentCard else { return }
        guard let wl = services.wishlist else {
            wishlistAlertMessage = "Wishlist isn’t available yet. Try again in a moment."
            showWishlistAlert = true
            return
        }
        do {
            try wl.removeAllItems(forCardID: card.masterCardId)
        } catch let e as WishlistError {
            switch e {
            case .saveFailed(let err):
                wishlistAlertMessage = err.localizedDescription
                showWishlistAlert = true
            case .limitReached, .alreadyExists:
                break
            }
        } catch {
            wishlistAlertMessage = error.localizedDescription
            showWishlistAlert = true
        }
    }

    private func addToCollectionVariant(variantKey: String) {
        guard let card = currentCard else { return }
        addToCollectionPayload = AddToCollectionSheetPayload(card: card, variantKey: variantKey)
    }

    /// Title Case variant key for picker labels (matches pricing panel style).
    private func wishlistVariantTitle(_ key: String) -> String {
        let spaced = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return spaced.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func wishlistRowShowsCheckmark(for key: String) -> Bool {
        guard let id = currentCard?.masterCardId else { return false }
        return services.wishlist?.isInWishlist(cardID: id, variantKey: key) == true
    }

    @ViewBuilder
    private func variantSelectionMenuContent(
        sectionHeader: String,
        showWishlistCheckmarks: Bool,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        Section {
            ForEach(wishlistVariantKeys, id: \.self) { key in
                Button {
                    onSelect(key)
                } label: {
                    HStack(spacing: 10) {
                        if showWishlistCheckmarks {
                            if wishlistRowShowsCheckmark(for: key) {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Self.wishlistActiveStarColor)
                                    .frame(width: 18, alignment: .leading)
                            } else {
                                Color.clear.frame(width: 18, height: 1)
                            }
                        }
                        Text(wishlistVariantTitle(key))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                }
            }
        } header: {
            Text(sectionHeader)
        }
    }

    @ViewBuilder
    private var headerRow: some View {
        let headerHeight = RootChromeEnvironment.searchBarStackHeight

        HStack(alignment: .center, spacing: 10) {
            Button {
                if let set = currentSet { navigationPath.append(set) }
            } label: {
                Group {
                    if let set = currentSet {
                        SetLogoAsyncImage(logoSrc: set.logoSrc, height: 26)
                            .frame(maxWidth: 72, maxHeight: headerHeight - 14)
                    } else {
                        Color.clear
                            .frame(width: 0, height: 1)
                    }
                }
                .frame(minHeight: 32, alignment: .center)
            }
            .buttonStyle(.plain)
            .disabled(currentSet == nil)
            .accessibilityLabel(currentSet.map { "Set: \($0.name)" } ?? "Set")
            .accessibilityHidden(currentSet == nil)

            Text(currentCard?.cardName ?? "")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.15), value: currentCard?.cardName)

            HStack(spacing: 10) {
                Group {
                    if let variantKey = singleAvailableVariantKey {
                        Button {
                            addToCollectionVariant(variantKey: variantKey)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(collectionPlusGlyphColor)
                                .modifier(ChromeGlassCircleGlyphModifier())
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Add to collection")
                        .accessibilityHint("Adds the available print variant")
                    } else {
                        Menu {
                            variantSelectionMenuContent(
                                sectionHeader: "Select Variant to add to collection",
                                showWishlistCheckmarks: false,
                                onSelect: addToCollectionVariant(variantKey:)
                            )
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(collectionPlusGlyphColor)
                                .modifier(ChromeGlassCircleGlyphModifier())
                        }
                        .menuStyle(.button)
                        .menuIndicator(.hidden)
                        .tint(collectionPlusGlyphColor)
                        .accessibilityLabel("Add to collection")
                        .accessibilityHint("Choose a print variant to add")
                    }
                }
                .frame(width: 48, height: 48)

                Group {
                    if isCurrentCardOnWishlist {
                        Button(action: removeCurrentCardFromWishlist) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Self.wishlistActiveStarColor)
                                .modifier(ChromeGlassCircleGlyphModifier())
                        }
                        .buttonStyle(.plain)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Remove from wishlist")
                    } else {
                        Group {
                            if let variantKey = singleAvailableVariantKey {
                                Button {
                                    addToWishlist(variantKey: variantKey)
                                } label: {
                                    Image(systemName: "star")
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundStyle(Color.primary)
                                        .modifier(ChromeGlassCircleGlyphModifier())
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .accessibilityLabel("Add to wishlist")
                                .accessibilityHint("Adds the available print variant")
                            } else {
                                Menu {
                                    variantSelectionMenuContent(
                                        sectionHeader: "Select Variant to add to wishlist",
                                        showWishlistCheckmarks: true,
                                        onSelect: addToWishlist(variantKey:)
                                    )
                                } label: {
                                    Image(systemName: "star")
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundStyle(Color.primary)
                                        .modifier(ChromeGlassCircleGlyphModifier())
                                }
                                .menuStyle(.button)
                                .menuIndicator(.hidden)
                                .accessibilityLabel("Add to wishlist")
                                .accessibilityHint("Choose a print variant to save")
                            }
                        }
                        .frame(width: 48, height: 48)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: headerHeight, alignment: .center)
        .frame(maxWidth: .infinity)
        .background {
            headerGlassBarBackground
        }
        .ignoresSafeArea(edges: .top)
    }

    /// Full-width Liquid Glass (iOS 26+) or frosted material, with a light dim overlay for title contrast.
    @ViewBuilder
    private var headerGlassBarBackground: some View {
        ZStack {
            if #available(iOS 26.0, *) {
                Rectangle()
                    .fill(Color.clear)
                    .glassEffect(.regular, in: Rectangle())
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
            }
            Rectangle()
                .fill(headerFullWidthDimStyle)
                .opacity(colorScheme == .dark ? 0.38 : 0.30)
        }
    }

    /// Sheet body fill — black in dark mode to match the card-detail chrome.
    private var pageChromeBackground: Color {
        colorScheme == .dark ? Color.black : Color(uiColor: .systemBackground)
    }

    /// Full-width header scrim (logo, title, actions) — slightly darker for legibility.
    private var headerFullWidthDimStyle: LinearGradient {
        if colorScheme == .dark {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.24),
                    Color.white.opacity(0.17),
                    Color.white.opacity(0.12),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.11),
                    Color.black.opacity(0.06),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Single page (one card)

private struct CardBrowseDetailPage: View {
    let card: Card

    @Environment(\.modelContext) private var modelContext
    @Query private var collectionItems: [CollectionItem]

    @State private var editingItem: CollectionItem?
    @State private var itemPendingRemoval: CollectionItem?
    @State private var showRemoveConfirm = false

    init(card: Card) {
        self.card = card
        let cardID = card.masterCardId
        _collectionItems = Query(
            filter: #Predicate<CollectionItem> { $0.cardID == cardID },
            sort: [SortDescriptor(\.variantKey)]
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AsyncImage(url: AppConfiguration.imageURL(relativePath: card.imageHighSrc ?? card.imageLowSrc)) {
                    $0.resizable().scaledToFit()
                } placeholder: {
                    Color(uiColor: .tertiarySystemFill)
                        .aspectRatio(5/7, contentMode: .fit)
                }
                .padding(.horizontal, 16)
                // Start below the custom header (66pt chrome + 6pt gap).
                .padding(.top, RootChromeEnvironment.searchBarStackHeight + 6)

                if !collectionItems.isEmpty {
                    collectionInCollectionSection
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                }

                CardPricingPanel(card: card)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .sheet(isPresented: Binding(
            get: { editingItem != nil },
            set: { if !$0 { editingItem = nil } }
        )) {
            if let editingItem {
                EditCollectionItemSheet(item: editingItem, cardDisplayName: card.cardName)
            }
        }
        .confirmationDialog(
            "Remove from collection?",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let item = itemPendingRemoval {
                    modelContext.delete(item)
                    itemPendingRemoval = nil
                }
            }
            Button("Cancel", role: .cancel) {
                itemPendingRemoval = nil
            }
        } message: {
            Text("This removes this stack from your holdings. Ledger history is kept.")
        }
    }

    private var collectionInCollectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(collectionItems, id: \.persistentModelID) { item in
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(item.quantity) × \(collectionVariantTitle(item.variantKey)) in collection")
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 12) {
                        Button("Edit") {
                            editingItem = item
                        }
                        .buttonStyle(.bordered)

                        Button("Remove", role: .destructive) {
                            itemPendingRemoval = item
                            showRemoveConfirm = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Matches ``AddToCollectionSheet``’s variant label (title case, underscores → spaces).
    private func collectionVariantTitle(_ variantKey: String) -> String {
        let spaced = variantKey
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return spaced.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}

// MARK: - Edit collection stack

private struct EditCollectionItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    @Bindable var item: CollectionItem
    let cardDisplayName: String

    @State private var quantity: Int
    @State private var notes: String
    @State private var errorMessage: String?

    init(item: CollectionItem, cardDisplayName: String) {
        self.item = item
        self.cardDisplayName = cardDisplayName
        _quantity = State(initialValue: item.quantity)
        _notes = State(initialValue: item.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                }
                Section {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit in collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear {
                services.setupCollectionLedger(modelContext: modelContext)
            }
        }
    }

    private func save() {
        errorMessage = nil
        services.setupCollectionLedger(modelContext: modelContext)
        guard let ledger = services.collectionLedger else {
            errorMessage = "Collection isn’t ready. Try again."
            return
        }
        do {
            if quantity != item.quantity {
                try ledger.applySingleCardStackQuantityChange(
                    item: item,
                    newQuantity: quantity,
                    cardDisplayName: cardDisplayName
                )
            }
            item.notes = notes
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
