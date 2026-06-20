import SwiftUI
import SwiftData

// MARK: - Share Item

enum SocialShareItem {
    case binder(Binder)
    case deck(Deck)
  /// Generic new post — user picks a card from collection / wishlist.
    case card
  /// Opened from a card detail share action — card is fixed for card-type posts.
    case cardDetail(Card)
  /// Opened from a sealed product detail share action.
    case sealedProductDetail(SealedProduct)
}

// MARK: - Post Tag

private enum PostTag: String, CaseIterable, Identifiable {
    case pull    = "Card Pull"
    case showcase = "Showcase"
    case bought  = "Bought"
    case trade   = "Trade"
    case want    = "I Want"
    case binder  = "Binder"
    case deck    = "Deck"

    var id: String { rawValue }

    var showsCardPicker: Bool {
        switch self {
        case .pull, .showcase, .bought, .trade, .want: return true
        case .binder, .deck:               return false
        }
    }
}

// MARK: - Social Post Card Picker

private enum SocialPostCardPickerSource {
    case collection
    case wishlist

    var navigationTitle: String {
        switch self {
        case .collection: return "Pick My Card"
        case .wishlist: return "Pick Wishlist Card"
        }
    }

    var emptyTitle: String {
        switch self {
        case .collection: return "Collection Empty"
        case .wishlist: return "Wishlist Empty"
        }
    }

    var emptyDescription: String {
        switch self {
        case .collection: return "Add cards to your collection to post a pull, purchase, or trade."
        case .wishlist: return "Add cards to your wishlist to post an I Want update."
        }
    }
}

private struct SocialPostCardPickerView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CollectionItem.dateAcquired, order: .reverse) private var collectionItems: [CollectionItem]
    @Query(sort: \WishlistItem.dateAdded, order: .reverse) private var wishlistItems: [WishlistItem]

    let source: SocialPostCardPickerSource
    let initialSelectedCardIDs: Set<String>
    let onConfirm: ([String]) -> Void

    @State private var cardIDs: [String] = []
    @State private var selectedCardIDs: Set<String> = []
    @State private var cardNameByID: [String: String] = [:]
    @State private var cardCacheByID: [String: Card] = [:]
    @State private var isLoading = false
    @State private var isIndexingNames = false
    @State private var searchText = ""

    private var filteredCardIDs: [String] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return cardIDs }
        let query = trimmed.localizedLowercase
        return cardIDs.filter { cardID in
            guard let cardName = cardNameByID[cardID] else { return false }
            return cardName.localizedLowercase.contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading cards...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if cardIDs.isEmpty {
                    ContentUnavailableView(
                        source.emptyTitle,
                        systemImage: "rectangle.stack",
                        description: Text(source.emptyDescription)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    cardGrid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(source.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selectedCardIDs.count))") {
                        let orderedSelection = cardIDs.filter { selectedCardIDs.contains($0) }
                        guard !orderedSelection.isEmpty else { return }
                        onConfirm(orderedSelection)
                        dismiss()
                    }
                    .disabled(selectedCardIDs.isEmpty)
                }
            }
        }
        .tint(.primary)
        .task { await loadCards() }
        .onChange(of: searchText) { _, _ in
            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            Task { await indexCardNamesIfNeeded() }
        }
    }

    private var cardGrid: some View {
        ScrollView {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                SelectableCardGrid(
                    cardIDs: filteredCardIDs,
                    isSelectMode: .constant(true),
                    selectedCardIDs: $selectedCardIDs,
                    cardLoader: { id in await loadCard(for: id) }
                )
                .padding(.horizontal, 12)

                if isIndexingNames {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Indexing card names...")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 12)
                }
            }
            .padding(.bottom, 12)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.5))
            TextField("Search cards...", text: $searchText)
                .font(.system(size: 13))
                .foregroundStyle(Color.primary)
                .tint(services.theme.accentColor)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .inlineSearchFieldChrome(cornerRadius: 14)
    }

    private func loadCards() async {
        isLoading = true
        defer { isLoading = false }

        switch source {
        case .collection:
            cardIDs = dedupeCardIDs(collectionItems.compactMap { item in
                guard item.quantity > 0, item.itemKind == ProductKind.singleCard.rawValue else { return nil }
                return item.cardID
            })
        case .wishlist:
            cardIDs = dedupeCardIDs(wishlistItems.compactMap { item in
                item.cardID.isEmpty ? nil : item.cardID
            })
        }

        selectedCardIDs = initialSelectedCardIDs.intersection(Set(cardIDs))

        await warmInitialCards()
    }

    private func warmInitialCards() async {
        let batch = Array(cardIDs.prefix(36))
        var cards: [Card] = []
        for cardID in batch {
            if let card = await loadCard(for: cardID) {
                cards.append(card)
            }
        }
        if !cards.isEmpty {
            ImagePrefetcher.shared.prefetchInitialBatch(cards, count: cards.count)
        }
    }

    private func loadCard(for cardID: String) async -> Card? {
        if let cached = cardCacheByID[cardID] {
            return cached
        }
        guard let loaded = await services.cardData.loadCard(masterCardId: cardID) else {
            return nil
        }
        cardCacheByID[cardID] = loaded
        cardNameByID[cardID] = loaded.cardName
        return loaded
    }

    private func indexCardNamesIfNeeded() async {
        let missingIDs = cardIDs.filter { cardNameByID[$0] == nil }
        guard !missingIDs.isEmpty else { return }
        isIndexingNames = true
        defer { isIndexingNames = false }

        for cardID in missingIDs {
            guard !Task.isCancelled else { return }
            _ = await loadCard(for: cardID)
        }
    }

    private func dedupeCardIDs(_ ids: [String]) -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []
        for id in ids where !id.isEmpty {
            if seen.insert(id).inserted {
                ordered.append(id)
            }
        }
        return ordered
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        y += rowHeight
        return CGSize(width: width, height: y)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Glass Capsule Button Modifier

private struct GlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                content
                    .glassEffect(.clear.tint(nil).interactive(), in: Capsule())
            } else {
                content
                    .background(.thinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
            }
        }
    }
}

// MARK: - SocialShareSheet

struct SocialShareSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let item: SocialShareItem

    @Query(sort: \CollectionItem.dateAcquired, order: .reverse) private var collectionItems: [CollectionItem]
    @Query(sort: \WishlistItem.dateAdded, order: .reverse)      private var wishlistItems: [WishlistItem]
    @Query(sort: \Binder.createdAt, order: .reverse)            private var binders: [Binder]
    @Query(sort: \Deck.createdAt, order: .reverse)              private var decks: [Deck]

    @State private var selectedTag: PostTag
    @State private var postText = ""
    @State private var selectedCollectionItems: [CollectionItem] = []
    @State private var selectedWishlistItems: [WishlistItem] = []
    @State private var selectedBinder: Binder? = nil
    @State private var selectedDeck: Deck? = nil
    @State private var visibility: SharedContentVisibility = .friends
    @State private var includeBinderValues = false
    @State private var cardsByID: [String: Card] = [:]
    @State private var setCodesByID: [String: String] = [:]
    @State private var setNamesByID: [String: String] = [:]
    @State private var isBusy = false
    @State private var errorMessage: String? = nil
    @State private var showPaywall = false
    @State private var showCardPicker = false

    init(item: SocialShareItem) {
        self.item = item
        switch item {
        case .binder(let b):
            _selectedTag    = State(initialValue: .binder)
            _selectedBinder = State(initialValue: b)
        case .deck(let d):
            _selectedTag  = State(initialValue: .deck)
            _selectedDeck = State(initialValue: d)
        case .card:
            _selectedTag = State(initialValue: .pull)
        case .cardDetail(let card):
            _selectedTag = State(initialValue: .pull)
            _cardsByID = State(initialValue: [card.masterCardId: card])
            _setCodesByID = State(initialValue: [card.masterCardId: card.setCode])
        case .sealedProductDetail:
            _selectedTag = State(initialValue: .pull)
        }
    }

    private var preselectedCard: Card? {
        if case .cardDetail(let card) = item { return card }
        return nil
    }

    private var preselectedSealedProduct: SealedProduct? {
        if case .sealedProductDetail(let product) = item { return product }
        return nil
    }

    private var usesFixedItemPreview: Bool {
        if let product = preselectedSealedProduct {
            switch selectedTag {
            case .pull, .showcase, .bought, .trade:
                return true
            case .want:
                return wishlistItems.contains {
                    $0.cardID == product.collectionCardID && $0.variantKey == sealedVariantKey
                }
            case .binder, .deck:
                return false
            }
        }
        guard let card = preselectedCard else { return false }
        switch selectedTag {
        case .pull, .showcase, .bought, .trade:
            return true
        case .want:
            return wishlistItems.contains { $0.cardID == card.masterCardId }
        case .binder, .deck:
            return false
        }
    }

    private var sealedVariantKey: String { "sealed" }

    private var accent: Color { services.theme.accentColor }
    private var headerButtonColor: Color { colorScheme == .dark ? .white : .black }

    private var canPost: Bool {
        switch selectedTag {
        case .pull, .showcase, .bought, .trade:
            if preselectedCard != nil || preselectedSealedProduct != nil { return true }
            return !selectedCollectionItems.isEmpty
        case .want:
            if let card = preselectedCard,
               wishlistItems.contains(where: { $0.cardID == card.masterCardId }) {
                return true
            }
            if let product = preselectedSealedProduct,
               wishlistItems.contains(where: {
                   $0.cardID == product.collectionCardID && $0.variantKey == sealedVariantKey
               }) {
                return true
            }
            return !selectedWishlistItems.isEmpty
        case .binder:                return selectedBinder != nil
        case .deck:                  return selectedDeck != nil
        }
    }

    private var singleCards: [CollectionItem] {
        collectionItems.filter { $0.itemKind == ProductKind.singleCard.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
            header
            Divider().opacity(0.15)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    tagSection
                    if selectedTag.showsCardPicker {
                        cardImagePicker
                    } else {
                        nonCardPicker
                    }
                    postTextField
                    visibilityPicker
                    if selectedTag == .binder {
                        binderValuePicker
                    }
                    
                    if case .deck(let deck) = item {
                        Divider().opacity(0.15).padding(.vertical, 8)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            sectionLabel("DIGITAL EXPORT")
                            
                            Button {
                                Task {
                                    let idsNeedingLookup = deck.cardList
                                        .filter { ($0.localId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                                        .map(\.cardID)
                                    var pokemonSets = await services.cardData.catalogSets(for: .pokemon)
                                    let hasAnySetAbbreviation = pokemonSets.contains {
                                        guard let abbr = $0.setAbbreviation else { return false }
                                        return !abbr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    }
                                    if pokemonSets.isEmpty || !hasAnySetAbbreviation {
                                        await services.forceCatalogRedownloadFromSettings()
                                        pokemonSets = await services.cardData.catalogSets(for: .pokemon)
                                    }
                                    let lookedUpCards = await services.cardData.loadCards(masterCardIDs: idsNeedingLookup, catalogBrand: .pokemon)
                                    let cardsByMasterId = Dictionary(uniqueKeysWithValues: lookedUpCards.map { ($0.masterCardId, $0) })
                                    let exportText = PTCGLService.shared.exportToPTCGL(deck: deck, sets: pokemonSets, cardsByMasterId: cardsByMasterId)
                                    UIPasteboard.general.string = exportText
                                    HapticManager.notification(.success)
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Copy to TCG Live (Text)")
                                        .font(.system(size: 14, weight: .semibold))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.tertiary)
                                }
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                            
                            Text("Standardized PTCGL format: Qty Name Set Number")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            Button {
                                Task {
                                    let idsNeedingLookup = deck.cardList
                                        .filter { ($0.localId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                                        .map(\.cardID)
                                    let catalogBrand = deck.tcgBrand
                                    let sets = await services.cardData.catalogSets(for: catalogBrand)
                                    let lookedUpCards = await services.cardData.loadCards(masterCardIDs: idsNeedingLookup, catalogBrand: catalogBrand)
                                    let cardsByMasterId = Dictionary(uniqueKeysWithValues: lookedUpCards.map { ($0.masterCardId, $0) })
                                    let exportText = PTCGLService.shared.exportToOfficialLeague(deck: deck, sets: sets, cardsByMasterId: cardsByMasterId)
                                    UIPasteboard.general.string = exportText
                                    HapticManager.notification(.success)
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "list.bullet.rectangle.portrait")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Copy Official Deck List (Text)")
                                        .font(.system(size: 14, weight: .semibold))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.tertiary)
                                }
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                            
                            Text("Official competition-ready format: Qty Name - Set Number")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .sheet(isPresented: $showPaywall) {
            PaywallSheet().environment(services)
        }
        .sheet(isPresented: $showCardPicker) {
            SocialPostCardPickerView(
                source: selectedTag == .want ? .wishlist : .collection,
                initialSelectedCardIDs: selectedCardPickerInitialIDs,
                onConfirm: { selectedCardIDs in
                    if selectedTag == .want {
                        selectedWishlistItems = selectedCardIDs.compactMap { selectedCardID in
                            wishlistItems.first { $0.cardID == selectedCardID }
                        }
                    } else {
                        selectedCollectionItems = selectedCardIDs.compactMap { selectedCardID in
                            singleCards.first { $0.cardID == selectedCardID }
                        }
                    }
                    HapticManager.selection()
                }
            )
            .environment(services)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .task {
            await loadCards()
            applyPreselectedSelection()
        }
        .task(id: binderValuePreferenceTaskID) {
            await loadBinderValuePreference()
        }
        .onChange(of: singleCards) { _, _ in
            applyPreselectedSelection()
            Task { await loadCards() }
        }
        .onChange(of: wishlistItems) { _, _ in
            applyPreselectedSelection()
            Task { await loadCards() }
        }
        .onChange(of: selectedTag) { _, _ in
            errorMessage = nil
            applyPreselectedSelection()
        }
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color.primary.opacity(0.2))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text("New Post")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            HStack {
                Button { dismiss() } label: {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(headerButtonColor)
                        .frame(height: 44)
                        .padding(.horizontal, 14)
                        .modifier(GlassCapsuleModifier())
                }
                .buttonStyle(.plain)
                .frame(height: 48)
                .contentShape(Rectangle())

                Spacer()

                Button { Task { await post() } } label: {
                    if isBusy {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 60, height: 44)
                            .modifier(GlassCapsuleModifier())
                    } else {
                        Text("Post")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(headerButtonColor)
                            .frame(height: 44)
                            .padding(.horizontal, 14)
                            .modifier(GlassCapsuleModifier())
                            .opacity(canPost ? 1 : 0.4)
                    }
                }
                .buttonStyle(.plain)
                .frame(height: 48)
                .contentShape(Rectangle())
                .disabled(!canPost || isBusy)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Tags

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("TYPE")
            FlowLayout(spacing: 8) {
                ForEach(PostTag.allCases) { tag in
                    tagChip(tag)
                }
            }
        }
    }

    private func tagChip(_ tag: PostTag) -> some View {
        let isSelected = selectedTag == tag
        return Button { selectedTag = tag } label: {
            Text(tag.rawValue)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? .primary : Color.primary.opacity(0.45))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    isSelected ? accent.opacity(0.12) : Color.primary.opacity(0.05),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(isSelected ? accent : Color.primary.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card Image Picker

    private var cardImagePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            if usesFixedItemPreview, let product = preselectedSealedProduct {
                fixedPreselectedSealedPreview(for: product)
            } else if usesFixedItemPreview, let card = preselectedCard {
                fixedPreselectedCardPreview(for: card)
            } else {
                sectionLabel(selectedTag == .want ? "SELECT FROM WISHLIST" : "SELECT FROM COLLECTION")
                selectedCardPickerRow
            }
        }
    }

    private var selectedCardPickerInitialIDs: Set<String> {
        if selectedTag == .want {
            return Set(selectedWishlistItems.map(\.cardID))
        }
        return Set(selectedCollectionItems.map(\.cardID))
    }

    private var selectedCardPickerRow: some View {
        let selectedItemsCount = selectedTag == .want
            ? selectedWishlistItems.count
            : selectedCollectionItems.count
        let selectedID = selectedTag == .want
            ? selectedWishlistItems.first?.cardID
            : selectedCollectionItems.first?.cardID
        let card = selectedID.flatMap { cardsByID[$0] }
        return Button {
            showCardPicker = true
        } label: {
            HStack(spacing: 12) {
                if let card {
                    CachedCardThumbnailImage(
                        url: AppConfiguration.imageURL(relativePath: card.displayImageSrc),
                        targetSize: CGSize(width: 72, height: 101)
                    )
                    .frame(width: 52, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(accent.opacity(0.55), lineWidth: 1)
                    }
                } else {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(accent)
                        .frame(width: 52, height: 52)
                        .background(accent.opacity(0.10), in: Circle())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedItemsCount > 1 ? "\(selectedItemsCount) cards selected" : card?.cardName ?? "Add Card")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(card == nil ? pickerEmptySubtitle : selectedCardSubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(card == nil ? "Choose" : "Edit")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(accent.opacity(0.10), in: Capsule())
            }
            .padding(12)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var pickerEmptySubtitle: String {
        selectedTag == .want ? "Pick from your wishlist" : "Pick from your collection"
    }

    private var selectedCardSubtitle: String {
        let count = selectedTag == .want ? selectedWishlistItems.count : selectedCollectionItems.count
        if count > 1 {
            return selectedTag == .want ? "From your wishlist" : "From your collection"
        }
        let variant = selectedTag == .want
            ? selectedWishlistItems.first?.variantKey
            : selectedCollectionItems.first?.variantKey
        guard let variant, variant != "normal" else {
            return selectedTag == .want ? "Wishlist" : "Collection"
        }
        return displayName(forVariantKey: variant)
    }

    private func displayName(forVariantKey key: String) -> String {
        let spaced = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return spaced.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func fixedPreselectedSealedPreview(for product: SealedProduct) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("PRODUCT")
            HStack {
                Spacer(minLength: 0)
                CachedAsyncImage(url: product.imageURL, targetSize: CGSize(width: 120, height: 168)) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    Color(uiColor: .tertiarySystemFill)
                }
                .frame(width: 120, height: 168)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(accent, lineWidth: 2.5)
                }
                Spacer(minLength: 0)
            }
            Text(product.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .onAppear {
            let cardID = product.collectionCardID
            if selectedTag == .want {
                selectedWishlistItems = wishlistItems.first {
                    $0.cardID == cardID && $0.variantKey == sealedVariantKey
                }.map { [$0] } ?? []
            } else {
                selectedCollectionItems = collectionItemMatchingSealed(product).map { [$0] } ?? []
            }
        }
    }

    private func fixedPreselectedCardPreview(for card: Card) -> some View {
        let variantKey = resolvedVariantKey(for: card)
        let imageURL = AppConfiguration.imageURL(relativePath: card.displayImageSrc)
        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel("CARD")
            HStack {
                Spacer(minLength: 0)
                CachedCardThumbnailImage(url: imageURL, targetSize: CGSize(width: 120, height: 168))
                    .frame(width: 120, height: 168)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(accent, lineWidth: 2.5)
                    }
                Spacer(minLength: 0)
            }
            Text(card.cardName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .onAppear {
            if selectedTag == .want {
                selectedWishlistItems = (wishlistItems.first {
                    $0.cardID == card.masterCardId && $0.variantKey == variantKey
                } ?? wishlistItems.first { $0.cardID == card.masterCardId }).map { [$0] } ?? []
            } else {
                selectedCollectionItems = collectionItemMatching(card, variantKey: variantKey).map { [$0] } ?? []
            }
        }
    }

    private var collectionImagePicker: some View {
        Group {
            if singleCards.isEmpty {
                emptyPicker("No cards in your collection yet.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(singleCards, id: \.cardID) { item in
                            let isSelected = selectedCollectionItems.contains {
                                $0.cardID == item.cardID && $0.variantKey == item.variantKey
                            }
                            cardImageCell(cardID: item.cardID, variantKey: item.variantKey, isSelected: isSelected) {
                                if isSelected {
                                    selectedCollectionItems.removeAll {
                                        $0.cardID == item.cardID && $0.variantKey == item.variantKey
                                    }
                                } else {
                                    selectedCollectionItems.append(item)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                .frame(height: 132)
                .padding(.horizontal, -16)
            }
        }
    }

    private var wishlistImagePicker: some View {
        Group {
            if wishlistItems.isEmpty {
                emptyPicker("Your wishlist is empty.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(wishlistItems, id: \.cardID) { item in
                            let isSelected = selectedWishlistItems.contains {
                                $0.cardID == item.cardID && $0.variantKey == item.variantKey
                            }
                            cardImageCell(cardID: item.cardID, variantKey: item.variantKey, isSelected: isSelected) {
                                if isSelected {
                                    selectedWishlistItems.removeAll {
                                        $0.cardID == item.cardID && $0.variantKey == item.variantKey
                                    }
                                } else {
                                    selectedWishlistItems.append(item)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                .frame(height: 132)
                .padding(.horizontal, -16)
            }
        }
    }

    private func cardImageCell(cardID: String, variantKey: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let imageURL = cardsByID[cardID].map { AppConfiguration.imageURL(relativePath: $0.displayImageSrc) }
        return Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    CachedCardThumbnailImage(url: imageURL, targetSize: CGSize(width: 80, height: 112))
                        .frame(width: 80, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(isSelected ? accent : Color.primary.opacity(0.12), lineWidth: isSelected ? 2.5 : 1)
                        }
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white, accent)
                            .offset(x: 6, y: -6)
                    }
                }
            }
            .frame(width: 80)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Non-card pickers (binder / deck / folder)

    @ViewBuilder
    private var nonCardPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch selectedTag {
            case .binder:
                sectionLabel("SELECT BINDER")
                chipPicker(items: binders, id: { $0.id }, title: { $0.title }, subtitle: { "\($0.slotList.count) cards" },
                           selected: Binding(get: { selectedBinder?.id }, set: { id in selectedBinder = binders.first { $0.id == id } }))
            case .deck:
                sectionLabel("SELECT DECK")
                chipPicker(items: decks, id: { $0.id }, title: { $0.title }, subtitle: { "\($0.totalCardCount) cards" },
                           selected: Binding(get: { selectedDeck?.id }, set: { id in selectedDeck = decks.first { $0.id == id } }))
            default:
                EmptyView()
            }
        }
    }

    private func chipPicker<T, ID: Equatable>(
        items: [T],
        id: @escaping (T) -> ID,
        title: @escaping (T) -> String,
        subtitle: @escaping (T) -> String,
        selected: Binding<ID?>
    ) -> some View {
        Group {
            if items.isEmpty {
                emptyPicker("Nothing here yet.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            let isSelected = selected.wrappedValue == id(item)
                            Button {
                                selected.wrappedValue = isSelected ? nil : id(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(title(item))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2).multilineTextAlignment(.leading)
                                    Text(subtitle(item))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .frame(maxWidth: 160, alignment: .leading)
                                .background(isSelected ? accent.opacity(0.12) : Color.primary.opacity(0.05),
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(isSelected ? accent : Color.primary.opacity(0.1), lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    // MARK: - Post Text

    private var postTextField: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("POST")
            TextField("Write something…", text: $postText, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineLimit(5, reservesSpace: true)
                .padding(12)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                }
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "E05252"))
            }
        }
    }

    // MARK: - Visibility

    private var visibilityPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("SHARE WITH")
            HStack(spacing: 10) {
                visibilityOption(.friends, label: "Friends", icon: "person.2.fill")
                visibilityOption(.link,    label: "Public",  icon: "globe")
            }
        }
    }

    private var binderValuePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("CARD VALUES")
            Toggle(isOn: $includeBinderValues) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Include card values")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Friends can choose whether to show the shared market estimates.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            }
        }
    }

    private func visibilityOption(_ option: SharedContentVisibility, label: String, icon: String) -> some View {
        let isSelected = visibility == option
        return Button { visibility = option } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                Text(label).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(isSelected ? .primary : Color.primary.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(isSelected ? accent.opacity(0.18) : Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? accent : Color.primary.opacity(0.1), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(Color.primary.opacity(0.3))
    }

    private func emptyPicker(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color.primary.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Actions

    private func post() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            switch selectedTag {
            case .pull, .showcase, .bought, .trade:
                let cards: [SocialShareService.PostCardInput]
                if !selectedCollectionItems.isEmpty {
                    cards = selectedCollectionItems.map { item in
                        SocialShareService.PostCardInput(
                            cardID: item.cardID,
                            variantKey: item.variantKey,
                            cardName: cardsByID[item.cardID]?.cardName ?? item.cardID,
                            setName: setNamesByID[item.cardID] ?? setCodesByID[item.cardID]
                        )
                    }
                } else if let card = preselectedCard {
                    cards = [
                        SocialShareService.PostCardInput(
                            cardID: card.masterCardId,
                            variantKey: resolvedVariantKey(for: card),
                            cardName: card.cardName,
                            setName: setNamesByID[card.masterCardId] ?? card.setCode
                        )
                    ]
                } else if let product = preselectedSealedProduct {
                    cards = [
                        SocialShareService.PostCardInput(
                            cardID: product.collectionCardID,
                            variantKey: sealedVariantKey,
                            cardName: product.name,
                            setName: product.setName
                        )
                    ]
                } else {
                    return
                }
                let taggedMessage = tagPrefix + (postText.isEmpty ? "" : " \(postText)")
                _ = try await services.socialShare.publishPull(
                    cards: cards,
                    message: taggedMessage,
                    visibility: visibility
                )
            case .want:
                guard !selectedWishlistItems.isEmpty else { return }
                let cards = selectedWishlistItems.map { item in
                    SocialShareService.PostCardInput(
                        cardID: item.cardID,
                        variantKey: item.variantKey,
                        cardName: cardsByID[item.cardID]?.cardName
                            ?? (preselectedSealedProduct?.collectionCardID == item.cardID
                                ? preselectedSealedProduct?.name
                                : nil)
                            ?? item.cardID,
                        setName: setNamesByID[item.cardID] ?? setCodesByID[item.cardID]
                    )
                }
                _ = try await services.socialShare.publishWant(
                    cards: cards,
                    message: postText,
                    visibility: visibility
                )
            case .binder:
                guard let binder = selectedBinder else { return }
                _ = try await services.socialShare.publishBinderPost(
                    binder,
                    title: binder.title,
                    description: postText,
                    visibility: visibility,
                    includeValue: includeBinderValues
                )
            case .deck:
                guard let deck = selectedDeck else { return }
                _ = try await services.socialShare.publishDeckPost(
                    deck, title: deck.title, description: postText, visibility: visibility, includeValue: false
                )
            }
            await services.socialFeed.refreshAfterContentPublished()
            dismiss()
        } catch {
            if case SocialShareService.SocialShareError.freeTierLimitReached = error { showPaywall = true }
            else if case SocialShareService.SocialShareError.deckSharingRequiresPremium = error { showPaywall = true }
            errorMessage = error.localizedDescription
        }
    }

    private var tagPrefix: String {
        switch selectedTag {
        case .bought: return "#bought"
        case .trade:  return "#trade"
        default:      return ""
        }
    }

    private func applyPreselectedSelection() {
        if let product = preselectedSealedProduct {
            let cardID = product.collectionCardID
            switch selectedTag {
            case .pull, .showcase, .bought, .trade:
                if selectedCollectionItems.first?.cardID != cardID {
                    selectedCollectionItems = collectionItemMatchingSealed(product).map { [$0] } ?? []
                }
            case .want:
                if selectedWishlistItems.first?.cardID != cardID {
                    selectedWishlistItems = wishlistItems.first {
                        $0.cardID == cardID && $0.variantKey == sealedVariantKey
                    }.map { [$0] } ?? []
                }
            case .binder, .deck:
                break
            }
            return
        }

        guard let card = preselectedCard else { return }
        let variantKey = resolvedVariantKey(for: card)
        switch selectedTag {
        case .pull, .showcase, .bought, .trade:
            if selectedCollectionItems.first?.cardID != card.masterCardId {
                selectedCollectionItems = collectionItemMatching(card, variantKey: variantKey).map { [$0] } ?? []
            }
        case .want:
            if selectedWishlistItems.first?.cardID != card.masterCardId {
                selectedWishlistItems = (wishlistItems.first {
                    $0.cardID == card.masterCardId && $0.variantKey == variantKey
                } ?? wishlistItems.first { $0.cardID == card.masterCardId }).map { [$0] } ?? []
            }
        case .binder, .deck:
            break
        }
    }

    private func collectionItemMatchingSealed(_ product: SealedProduct) -> CollectionItem? {
        let cardID = product.collectionCardID
        return collectionItems.first {
            $0.cardID == cardID && $0.variantKey == sealedVariantKey
        } ?? collectionItems.first { $0.cardID == cardID }
    }

    private func collectionItemMatching(_ card: Card, variantKey: String) -> CollectionItem? {
        singleCards.first {
            $0.cardID == card.masterCardId && $0.variantKey == variantKey
        } ?? singleCards.first { $0.cardID == card.masterCardId }
    }

    private func resolvedVariantKey(for card: Card) -> String {
        if let item = singleCards.first(where: { $0.cardID == card.masterCardId && $0.variantKey == "normal" }) {
            return item.variantKey
        }
        if let item = singleCards.first(where: { $0.cardID == card.masterCardId }) {
            return item.variantKey
        }
        if let wish = wishlistItems.first(where: { $0.cardID == card.masterCardId }) {
            return wish.variantKey
        }
        return "normal"
    }

    private var binderValuePreferenceTaskID: String {
        guard selectedTag == .binder, let selectedBinder else { return "not-binder" }
        return selectedBinder.id.uuidString
    }

    private func loadBinderValuePreference() async {
        guard selectedTag == .binder, let binder = selectedBinder else { return }
        do {
            let snapshot = try await services.socialShare.shareSnapshot(for: binder)
            guard selectedTag == .binder, selectedBinder?.id == binder.id else { return }
            includeBinderValues = snapshot.includeValue
        } catch {
            guard selectedTag == .binder, selectedBinder?.id == binder.id else { return }
            includeBinderValues = false
        }
    }

    private func loadCards() async {
        let setNameByCode = Dictionary(
            uniqueKeysWithValues: services.cardData.sets.map { ($0.setCode, $0.name) }
        )

        if let card = preselectedCard,
           setNamesByID[card.masterCardId] == nil,
           let name = setNameByCode[card.setCode] {
            setNamesByID[card.masterCardId] = name
        }

        var ids = Set(singleCards.map(\.cardID) + wishlistItems.map(\.cardID))
        if let card = preselectedCard {
            ids.insert(card.masterCardId)
        }
        ids = ids.filter { cardsByID[$0] == nil }
        guard !ids.isEmpty else {
            prefetchImages()
            return
        }

        let cardDataService = services.cardData
        var loaded: [Card] = []
        await withTaskGroup(of: Card?.self) { group in
            for id in ids {
                group.addTask { await cardDataService.loadCard(masterCardId: id) }
            }
            for await card in group {
                if let card { loaded.append(card) }
            }
        }
        for card in loaded {
            cardsByID[card.masterCardId] = card
            setCodesByID[card.masterCardId] = card.setCode
            if let name = setNameByCode[card.setCode] {
                setNamesByID[card.masterCardId] = name
            }
        }
        prefetchImages()
    }

    private func prefetchImages() {
        let urls = cardsByID.values.compactMap { card -> URL? in
            let url = AppConfiguration.imageURL(relativePath: card.displayImageSrc)
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
            guard AppURLSession.imageURLCache.cachedResponse(for: request) == nil else { return nil }
            return url
        }
        for url in urls {
            Task.detached(priority: .background) {
                let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
                guard let (data, response) = try? await AppURLSession.images.data(for: request) else { return }
                let cached = CachedURLResponse(response: response, data: data)
                AppURLSession.imageURLCache.storeCachedResponse(cached, for: URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30))
            }
        }
    }
}
