import SwiftData
import SwiftUI
import UIKit

struct CardBrowseDetailView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    let cards: [Card]
    /// When set, replaces the collection/wishlist buttons with a deck-add button.
    var addToDeckAction: ((Card, String, Int) -> Void)? = nil
    /// When false, hides the standard collection action.
    var showsHeaderChromeActions: Bool = true
    /// When true and ``showsHeaderChromeActions`` is false, still show wishlist actions.
    var showsWishlistWhenChromeHidden: Bool = false
    /// Optional context-specific trade action (used by Social friend profile card detail).
    var tradeAction: ((Card, Int) -> Void)? = nil
    var tradeActionLabel: String = "Trade"

    @State private var index: Int
    @State private var pushedSet: TCGSet? = nil

    init(
        cards: [Card],
        startIndex: Int,
        addToDeckAction: ((Card, String, Int) -> Void)? = nil,
        showsHeaderChromeActions: Bool = true,
        showsWishlistWhenChromeHidden: Bool = false,
        tradeAction: ((Card, Int) -> Void)? = nil,
        tradeActionLabel: String = "Trade"
    ) {
        self.cards = cards
        self.addToDeckAction = addToDeckAction
        self.showsHeaderChromeActions = showsHeaderChromeActions
        self.showsWishlistWhenChromeHidden = showsWishlistWhenChromeHidden
        self.tradeAction = tradeAction
        self.tradeActionLabel = tradeActionLabel
        let clamped: Int = {
            guard !cards.isEmpty else { return 0 }
            return min(max(0, startIndex), cards.count - 1)
        }()
        _index = State(initialValue: clamped)
    }

    var body: some View {
        Group {
            if cards.isEmpty {
                ContentUnavailableView("No card", systemImage: "rectangle.on.rectangle.slash")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabView(selection: $index) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { i, card in
                        CardBrowseDetailPage(
                            card: card,
                            set: services.cardData.sets.first { $0.setCode == card.setCode },
                            addToDeckAction: addToDeckAction,
                            showsCollectionAction: showsHeaderChromeActions,
                            showsWishlistAction: showsHeaderChromeActions || showsWishlistWhenChromeHidden,
                            tradeAction: tradeAction,
                            tradeActionLabel: tradeActionLabel,
                            onOpenSet: {
                                pushedSet = services.cardData.sets.first { $0.setCode == card.setCode }
                            }
                        )
                        .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pageChromeBackground)
        .task(id: index) {
            ImagePrefetcher.shared.prefetchHighResForDetailView(cards, currentIndex: index, window: 2)
        }
        .onChange(of: index) { _, _ in
            HapticManager.selection()
        }
        .sheet(item: $pushedSet) { set in
            NavigationStack {
                SetCardsView(set: set)
            }
        }
        .presentationBackground(pageChromeBackground)
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .presentationCornerRadius(20)
    }

    private var pageChromeBackground: Color {
        colorScheme == .dark ? Color.black : Color(uiColor: .systemBackground)
    }
}

private struct CardBrowseDetailPage: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var collectionItems: [CollectionItem]

    let card: Card
    let set: TCGSet?
    let addToDeckAction: ((Card, String, Int) -> Void)?
    let showsCollectionAction: Bool
    let showsWishlistAction: Bool
    let tradeAction: ((Card, Int) -> Void)?
    let tradeActionLabel: String
    let onOpenSet: () -> Void

    @State private var editingLine: HoldingLine?
    @State private var dispositionLine: HoldingLine?
    @State private var addToCollectionPayload: AddToCollectionSheetPayload?
    @State private var addToFolderPayload: AddToFolderSheetPayload?
    @State private var showCardShare = false
    @State private var showTradeListQuantityPicker = false
    @State private var tradeListPickerQuantity = 1
    @State private var wishlistVariantKeys: [String] = ["normal"]
    @State private var isCurrentCardWishlisted = false
    @State private var showWishlistPaywall = false
    @State private var wishlistAlertMessage: String?
    @State private var showWishlistAlert = false
    @State private var imageAppeared = false
    @State private var extractedAuraColors: [Color] = []
    @State private var auraSourceImageArea: CGFloat = 0

    private static let wishlistActiveStarColor = Color(red: 0.98, green: 0.78, blue: 0.18)

    init(
        card: Card,
        set: TCGSet?,
        addToDeckAction: ((Card, String, Int) -> Void)?,
        showsCollectionAction: Bool,
        showsWishlistAction: Bool,
        tradeAction: ((Card, Int) -> Void)?,
        tradeActionLabel: String = "Trade",
        onOpenSet: @escaping () -> Void
    ) {
        self.card = card
        self.set = set
        self.addToDeckAction = addToDeckAction
        self.showsCollectionAction = showsCollectionAction
        self.showsWishlistAction = showsWishlistAction
        self.tradeAction = tradeAction
        self.tradeActionLabel = tradeActionLabel
        self.onOpenSet = onOpenSet
        let cardID = card.masterCardId
        _collectionItems = Query(
            filter: #Predicate<CollectionItem> { $0.cardID == cardID },
            sort: [SortDescriptor(\.variantKey)]
        )
    }

    private var visibleCollectionItems: [CollectionItem] {
        collectionItems.filter { $0.quantity > 0 }
    }

    private var showsCollectionSection: Bool {
        let brand = TCGBrand.inferredFromMasterCardId(card.masterCardId)
        guard services.brandSettings.enabledBrands.contains(brand) else { return false }
        return !visibleCollectionItems.isEmpty
    }

    private var singleAvailableVariantKey: String? {
        wishlistVariantKeys.count == 1 ? wishlistVariantKeys[0] : nil
    }

    /// Deck rows are keyed by card id and quantity, so variant does not affect deckbuilding behavior.
    /// Prefer "normal" when present, then fall back to the first available key.
    private var preferredDeckVariantKey: String {
        if wishlistVariantKeys.contains("normal") {
            return "normal"
        }
        return wishlistVariantKeys.first ?? "normal"
    }

    private var summaryFacts: [(String, String)] {
        var facts: [(String, String)] = []
        if let number = cleaned(card.printedNumber) ?? cleaned(card.cardNumber) {
            facts.append(("Number", number))
        }
        if let rarity = cleaned(card.rarity) {
            facts.append(("Rarity", rarity))
        }
        if let category = cleaned(card.category) {
            facts.append(("Category", category))
        }
        if let stage = cleaned(card.stage) {
            facts.append(("Stage", stage))
        }
        if let hp = card.hp {
            facts.append(("HP", "\(hp)"))
        }
        if let types = cleanedList(card.elementTypes) {
            facts.append(("Type", types))
        }
        if let subtypes = cleanedList(card.subtypes) ?? cleaned(card.subtype) {
            facts.append(("Subtype", subtypes))
        }
        if let trainerType = cleaned(card.trainerType) {
            facts.append(("Trainer", trainerType))
        }
        if let energyType = cleaned(card.energyType) {
            facts.append(("Energy", energyType))
        }
        if let regulationMark = cleaned(card.regulationMark) {
            facts.append(("Regulation", regulationMark))
        }
        if let evolvesFrom = cleaned(card.evolveFrom) {
            facts.append(("Evolves From", evolvesFrom))
        }
        if let artist = cleaned(card.artist) {
            facts.append(("Artist", artist))
        }
        if let weakness = cleaned(card.weakness) {
            facts.append(("Weakness", weakness))
        }
        if let resistance = cleaned(card.resistance) {
            facts.append(("Resistance", resistance))
        }
        if let retreatCost = card.retreatCost {
            facts.append(("Retreat", "\(retreatCost)"))
        }
        if let attributes = cleanedList(card.opAttributes) {
            facts.append(("Attributes", attributes))
        }
        if let cost = card.opCost {
            facts.append(("Cost", "\(cost)"))
        }
        if let counter = card.opCounter {
            facts.append(("Counter", "\(counter)"))
        }
        if let life = card.opLife {
            facts.append(("Life", "\(life)"))
        }
        return facts
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    cardHeroSection

                    CardPricingPanel(card: card)
                        .glassCardStyle(cornerRadius: 26, interactive: false)
                    recentSoldOnEbayButton
                        .glassCardStyle(cornerRadius: 26, interactive: false)

                    if showsCollectionSection {
                        collectionSection
                    }

                    if !summaryFacts.isEmpty || card.attacks != nil || card.abilities != nil || cleaned(card.rules) != nil || cleaned(card.flavorText) != nil {
                        cardDetailsSection
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .topLeading)
            }
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pageBackground.ignoresSafeArea())
        .task(id: card.masterCardId) {
            extractedAuraColors = []
            auraSourceImageArea = 0
            await loadWishlistVariantKeys()
        }
        .onAppear {
            services.setupCollectionLedger(modelContext: modelContext)
        }
        .sheet(item: $editingLine) { line in
            EditCollectionItemSheet(
                line: line,
                cardDisplayName: card.cardName,
                availableVariantKeys: wishlistVariantKeys
            )
        }
        .sheet(item: $dispositionLine) { line in
            HoldingDispositionSheet(line: line, cardDisplayName: card.cardName)
        }
        .sheet(item: $addToCollectionPayload) { payload in
            AddToCollectionSheet(card: payload.card, variantKey: payload.variantKey, availableVariantKeys: payload.availableVariantKeys)
                .environment(services)
        }
        .sheet(item: $addToFolderPayload) { payload in
            AddToFolderSheet(card: payload.card, variantKey: payload.variantKey)
        }
        .sheet(isPresented: $showCardShare) {
            SocialShareSheet(item: .card)
                .environment(services)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showWishlistPaywall) {
            PaywallSheet()
                .environment(services)
        }
        .alert("Wishlist", isPresented: $showWishlistAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(wishlistAlertMessage ?? "")
        }
    }

    private var cardHeroSection: some View {
        VStack(spacing: 10) {
            cardImage
                .padding(.top, 20)
                .padding(.horizontal, 6)

            cardMetaRow
        }
        .background(alignment: .top) {
            cardImageToMetaFadeAura
        }
    }

    private var cardImageToMetaFadeAura: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: cardAuraColors.map { $0.opacity(colorScheme == .dark ? 0.62 : 0.42) },
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(maxWidth: .infinity)
                .aspectRatio(5 / 7, contentMode: .fit)
                .blur(radius: colorScheme == .dark ? 32 : 26)
                .scaleEffect(1.16)

            LinearGradient(
                colors: [
                    cardAuraColors[0].opacity(colorScheme == .dark ? 0.34 : 0.20),
                    cardAuraColors[1].opacity(colorScheme == .dark ? 0.24 : 0.14),
                    cardAuraColors[2].opacity(colorScheme == .dark ? 0.14 : 0.09),
                    cardAuraColors[2].opacity(colorScheme == .dark ? 0.08 : 0.05),
                    cardAuraColors[2].opacity(colorScheme == .dark ? 0.04 : 0.02),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 330)
            .blur(radius: colorScheme == .dark ? 20 : 15)
            .offset(y: -8)
        }
        .allowsHitTesting(false)
    }

    private var recentSoldOnEbayButton: some View {
        Button {
            guard let url = ebayRecentSoldURL else { return }
            openURL(url)
        } label: {
            HStack(spacing: 14) {
                ebayWordmarkBadge
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recent Sold on eBay")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Open sold listings for this card")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05), in: Circle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 76)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityLabel("Open recent sold listings on eBay")
    }

    private var ebayWordmarkBadge: some View {
        ebayWordmark
            .frame(width: 74, height: 42)
            .background(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.70), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.05), lineWidth: 1)
            }
    }

    private var ebayWordmark: some View {
        HStack(spacing: 0) {
            Text("e").foregroundStyle(Color(red: 0.89, green: 0.15, blue: 0.13))
            Text("B").foregroundStyle(Color(red: 0.00, green: 0.38, blue: 0.75))
            Text("a").foregroundStyle(Color(red: 0.97, green: 0.74, blue: 0.06))
            Text("y").foregroundStyle(Color(red: 0.44, green: 0.68, blue: 0.11))
        }
        .font(.system(size: 24, weight: .bold, design: .rounded))
    }

    private var ebayRecentSoldURL: URL? {
        let cardName = card.cardName.trimmingCharacters(in: .whitespacesAndNewlines)
        let setName = cleaned(set?.name) ?? card.setCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let cardNumber = (cleaned(card.printedNumber) ?? cleaned(card.cardNumber) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let searchText = [cardName, setName, cardNumber]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchText.isEmpty else { return nil }

        var components = URLComponents(string: "https://www.ebay.com/sch/i.html")
        components?.queryItems = [
            URLQueryItem(name: "_nkw", value: searchText),
            URLQueryItem(name: "LH_Sold", value: "1"),
            URLQueryItem(name: "LH_Complete", value: "1")
        ]
        return components?.url
    }

    private var cardImage: some View {
        ZStack {
            // Type-driven aura to echo colors from each card art while keeping contrast subtle.
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: cardAuraColors.map { $0.opacity(colorScheme == .dark ? 0.78 : 0.56) },
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(maxWidth: .infinity)
                .aspectRatio(5 / 7, contentMode: .fit)
                .blur(radius: colorScheme == .dark ? 30 : 24)
                .scaleEffect(1.12)

            ProgressiveAsyncImage(
                lowResURL: AppConfiguration.imageURL(relativePath: card.displayImageSrc),
                highResURL: card.imageHighSrc.map { AppConfiguration.imageURL(relativePath: $0) },
                onImageLoaded: updateAuraColors(from:)
            ) {
                Color(uiColor: .tertiarySystemFill)
                    .aspectRatio(5 / 7, contentMode: .fit)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.22), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity)
        .scaleEffect(imageAppeared ? 1.0 : 0.96)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.84)) {
                imageAppeared = true
            }
        }
        .onDisappear {
            imageAppeared = false
        }
    }

    @ViewBuilder
    private var cardMetaRow: some View {
        if let deckAction = addToDeckAction {
            VStack(spacing: 12) {
                titleBlock

                Button {
                    deckAction(card, preferredDeckVariantKey, 1)
                } label: {
                    cardActionBody(
                        title: "Add to Deck",
                        systemImage: "plus.circle.fill",
                        tint: CardDetailPalette.chartLine
                    )
                }
                .buttonStyle(.plain)
            }
        } else {
            VStack(spacing: 12) {
                titleBlock

                HStack(spacing: 8) {
                    if showsCollectionAction {
                        collectionActionButton
                    }
                    if showsWishlistAction {
                        wishlistActionButton
                    }
                    if showsCollectionAction {
                        folderActionButton
                    }
                    if let tradeAction {
                        tradeActionButton(action: tradeAction)
                    }
                    if showsCollectionAction {
                        shareActionButton
                    }
                }
            }
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text(card.cardName)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
            centeredSetBlock
        }
    }

    @ViewBuilder
    private var centeredSetBlock: some View {
        if let set {
            Button(action: onOpenSet) {
                SetLogoAsyncImage(
                    logoSrc: set.logoSrc,
                    height: 34,
                    brand: TCGBrand.inferredFromMasterCardId(card.masterCardId)
                )
                .frame(maxWidth: 140, minHeight: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(set.name)")
        } else if let setCode = cleaned(card.setCode) {
            Text(setCode)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Color.clear
                .frame(width: 140, height: 40)
        }
    }

    @ViewBuilder
    private var collectionActionButton: some View {
        if let variantKey = singleAvailableVariantKey {
            Button {
                addToCollectionVariant(variantKey: variantKey)
            } label: {
                cardActionBody(
                    title: "Collection",
                    systemImage: "plus.circle.fill",
                    tint: CardDetailPalette.success
                )
            }
            .buttonStyle(.plain)
        } else {
            Menu {
                variantSelectionMenuContent(
                    sectionHeader: "Select Variant to add to collection",
                    showWishlistCheckmarks: false,
                    onSelect: addToCollectionVariant(variantKey:)
                )
            } label: {
                cardActionBody(
                    title: "Collection",
                    systemImage: "plus.circle.fill",
                    tint: CardDetailPalette.success
                )
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
        }
    }

    @ViewBuilder
    private var wishlistActionButton: some View {
        if isCurrentCardWishlisted {
            Button {
                removeCurrentCardFromWishlist()
            } label: {
                cardActionBody(
                    title: "Wish List",
                    systemImage: "star.fill",
                    tint: Self.wishlistActiveStarColor
                )
            }
            .buttonStyle(.plain)
        } else if let variantKey = singleAvailableVariantKey {
            Button {
                addToWishlist(variantKey: variantKey)
            } label: {
                cardActionBody(
                    title: "Wish List",
                    systemImage: "star",
                    tint: CardDetailPalette.gold
                )
            }
            .buttonStyle(.plain)
        } else {
            Menu {
                variantSelectionMenuContent(
                    sectionHeader: "Select Variant to add to wishlist",
                    showWishlistCheckmarks: true,
                    onSelect: addToWishlist(variantKey:)
                )
            } label: {
                cardActionBody(
                    title: "Wish List",
                    systemImage: "star",
                    tint: CardDetailPalette.gold
                )
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
        }
    }

    @ViewBuilder
    private var folderActionButton: some View {
        if let variantKey = singleAvailableVariantKey {
            Button {
                addToFolderPayload = AddToFolderSheetPayload(card: card, variantKey: variantKey)
            } label: {
                cardActionBody(
                    title: "Add to Folder",
                    systemImage: "folder.badge.plus",
                    tint: Color(red: 0.18, green: 0.72, blue: 0.88)
                )
            }
            .buttonStyle(.plain)
        } else {
            Menu {
                variantSelectionMenuContent(
                    sectionHeader: "Select Variant to add to folder",
                    showWishlistCheckmarks: false,
                    onSelect: { key in
                        addToFolderPayload = AddToFolderSheetPayload(card: card, variantKey: key)
                    }
                )
            } label: {
                cardActionBody(
                    title: "Add to Folder",
                    systemImage: "folder.badge.plus",
                    tint: Color(red: 0.18, green: 0.72, blue: 0.88)
                )
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
        }
    }

    private var shareActionButton: some View {
        Button {
            showCardShare = true
        } label: {
            cardActionBody(
                title: "Share",
                systemImage: "square.and.arrow.up",
                tint: Color(red: 0.36, green: 0.61, blue: 0.97)
            )
        }
        .buttonStyle(.plain)
    }

    private func tradeActionButton(action: @escaping (Card, Int) -> Void) -> some View {
        let totalOwned = visibleCollectionItems.reduce(0) { $0 + $1.quantity }
        return Button {
            if totalOwned > 1 {
                tradeListPickerQuantity = 1
                showTradeListQuantityPicker = true
            } else {
                action(card, 1)
            }
        } label: {
            cardActionBody(
                title: tradeActionLabel,
                systemImage: "arrow.left.arrow.right.circle.fill",
                tint: CardDetailPalette.chartLine
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showTradeListQuantityPicker) {
            VStack(spacing: 16) {
                Text("How many to trade?")
                    .font(.headline)
                Stepper("Quantity: \(tradeListPickerQuantity)", value: $tradeListPickerQuantity, in: 1...totalOwned)
                Text("You own \(totalOwned) copies")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Cancel") { showTradeListQuantityPicker = false }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    Button("Add") {
                        showTradeListQuantityPicker = false
                        action(card, tradeListPickerQuantity)
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
            .frame(minWidth: 260)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func cardActionBody(title: String, systemImage: String, tint: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassCardStyle(cornerRadius: 14, interactive: false)
        .accessibilityLabel(title)
    }

    private var collectionSection: some View {
        DetailSurface(title: "Collection") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(groupedHoldings) { group in
                    holdingCard(for: group)
                }
            }
        }
    }

    private func holdingCard(for group: HoldingGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("\(group.totalQuantity) x \(variantTitle(group.variantKey))")
                    .font(.headline)
                    .foregroundStyle(.primary)
                infoBadge(label: group.itemKind == ProductKind.gradedItem.rawValue ? "Graded" : "Raw", tint: CardDetailPalette.chartLine)
                if let company = cleaned(group.gradingCompany), let grade = cleaned(group.grade) {
                    infoBadge(label: "\(company) \(grade)", tint: CardDetailPalette.gold)
                }
            }

            VStack(spacing: 10) {
                ForEach(group.lines) { line in
                    holdingSourceRow(line)
                }
            }

            if let notes = cleaned(group.primaryItem.notes) {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        }
        .padding(.vertical, 6)
    }

    private func holdingSourceRow(_ line: HoldingLine) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Left Column: Details
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    infoBadge(label: line.directionTitle, tint: line.tint)
                    Text("Qty \(line.quantity)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                
                HStack(spacing: 6) {
                    Text(line.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let priceText = line.priceText {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(priceText)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(CardDetailPalette.chartLine)
                    }
                }
            }
            
            Spacer()
            
            // Right Side: Quick Action Icons or Compact Buttons
            HStack(spacing: 8) {
                Button {
                    editingLine = line
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .bold))
                        Text("Edit")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                    )
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                
                Button {
                    dispositionLine = line
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Mark As")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(CardDetailPalette.chartLine.opacity(0.12))
                    )
                    .foregroundStyle(CardDetailPalette.chartLine)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(sectionInsetBackground.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var cardDetailsSection: some View {
        DetailSurface(title: "Card Details") {
            VStack(alignment: .leading, spacing: 14) {
                if !summaryFacts.isEmpty {
                    let factRows = stride(from: 0, to: summaryFacts.count, by: 2).map {
                        Array(summaryFacts[$0..<min($0 + 2, summaryFacts.count)])
                    }
                    VStack(spacing: 10) {
                        ForEach(Array(factRows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 12) {
                                ForEach(row, id: \.0) { fact in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(fact.0)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        Text(fact.1)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(sectionInsetBackground)
                                    )
                                }
                                if row.count < 2 {
                                    Color.clear.frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                }

                if let attacks = card.attacks, !attacks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Attacks")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        ForEach(Array(attacks.enumerated()), id: \.offset) { _, attack in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(attack.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Spacer(minLength: 8)
                                    if let damage = cleaned(attack.damage) {
                                        Text(damage)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(CardDetailPalette.chartLine)
                                    }
                                }

                                if let cost = cleanedList(attack.cost) {
                                    Text(cost)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }

                                if let effect = cleaned(attack.effect) {
                                    Text(effect)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(sectionInsetBackground)
                            )
                        }
                    }
                }

                if let abilities = card.abilities, !abilities.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Abilities")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        ForEach(Array(abilities.enumerated()), id: \.offset) { _, ability in
                            if let text = cleaned(ability.text) {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 8) {
                                        if let type = cleaned(ability.type) {
                                            Text(type.uppercased())
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(CardDetailPalette.chartLine)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(
                                                    Capsule(style: .continuous)
                                                        .fill(CardDetailPalette.chartLine.opacity(0.14))
                                                )
                                        }

                                        if let name = cleaned(ability.name) {
                                            Text(name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                        }
                                    }

                                    Text(text)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(sectionInsetBackground)
                                )
                            }
                        }
                    }
                }

                if let rules = cleaned(card.rules) {
                    detailTextBlock(title: "Rules", body: rules)
                }

                if let flavorText = cleaned(card.flavorText) {
                    detailTextBlock(title: "Flavor Text", body: flavorText)
                }
            }
        }
    }

    private func detailTextBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func labelValueRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
        }
    }

    private func infoBadge(label: String, tint: Color) -> some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            )
    }

    private var groupedHoldings: [HoldingGroup] {
        var groups: [String: HoldingGroup] = [:]

        for item in visibleCollectionItems {
            for lot in (item.costLots ?? []).filter({ $0.quantityRemaining > 0 }) {
                let line = lot.sourceLedgerLine
                let direction = line.flatMap { LedgerDirection(rawValue: $0.direction) } ?? .bought
                let date = line?.occurredAt ?? item.dateAcquired
                let counterparty = cleaned(line?.counterparty)
                let description = cleaned(line?.lineDescription)
                let unitPrice = line?.unitPrice
                let currencyCode = line?.currencyCode ?? "USD"
                let groupKey = [
                    item.itemKind,
                    item.variantKey,
                    cleaned(item.gradingCompany) ?? "",
                    cleaned(item.grade) ?? ""
                ].joined(separator: "|")

                let lineID = [
                    groupKey,
                    direction.rawValue,
                    counterparty ?? "",
                    description ?? "",
                    currencyCode,
                    (unitPrice.map { String(format: "%.6f", $0) } ?? ""),
                    String(Int(date.timeIntervalSince1970))
                ].joined(separator: "|")
                let holdingLine = HoldingLine(
                    id: lineID + "|\(lot.id.uuidString)",
                    item: item,
                    itemKind: item.itemKind,
                    variantKey: item.variantKey,
                    gradingCompany: cleaned(item.gradingCompany),
                    grade: cleaned(item.grade),
                    quantity: lot.quantityRemaining,
                    date: date,
                    direction: direction,
                    unitPrice: unitPrice,
                    currencyCode: currencyCode,
                    counterparty: counterparty,
                    description: description,
                    lotIDs: [lot.id]
                )

                if var existingGroup = groups[groupKey] {
                    existingGroup.totalQuantity += lot.quantityRemaining
                    if let existingLineIndex = existingGroup.lines.firstIndex(where: { $0.identityKey == holdingLine.identityKey }) {
                        existingGroup.lines[existingLineIndex].quantity += lot.quantityRemaining
                        existingGroup.lines[existingLineIndex].lotIDs.insert(lot.id)
                    } else {
                        existingGroup.lines.append(holdingLine)
                    }
                    groups[groupKey] = existingGroup
                } else {
                    groups[groupKey] = HoldingGroup(
                        id: groupKey,
                        primaryItem: item,
                        itemKind: item.itemKind,
                        variantKey: item.variantKey,
                        gradingCompany: cleaned(item.gradingCompany),
                        grade: cleaned(item.grade),
                        totalQuantity: lot.quantityRemaining,
                        lines: [holdingLine]
                    )
                }
            }
        }

        return groups.values
            .map { group in
                var mutable = group
                mutable.lines.sort { $0.date > $1.date }
                return mutable
            }
            .sorted { lhs, rhs in
                (lhs.lines.first?.date ?? .distantPast) > (rhs.lines.first?.date ?? .distantPast)
            }
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
                        Text(variantTitle(key))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                }
            }
        } header: {
            Text(sectionHeader)
        }
    }

    private func refreshWishlistState() {
        guard let wl = services.wishlist else {
            isCurrentCardWishlisted = false
            return
        }
        isCurrentCardWishlisted = wl.isInWishlist(cardID: card.masterCardId)
    }

    private func loadWishlistVariantKeys() async {
        var keys = await services.pricing.variantKeys(for: card)
        if keys.isEmpty, let pv = card.pricingVariants, !pv.isEmpty {
            keys = pv
        }
        if keys.isEmpty {
            keys = ["normal"]
        }
        wishlistVariantKeys = keys
        refreshWishlistState()
    }

    private func addToWishlist(variantKey: String) {
        guard let wl = services.wishlist else {
            wishlistAlertMessage = "Wishlist isn’t available yet. Try again in a moment."
            showWishlistAlert = true
            return
        }
        do {
            try wl.addItem(cardID: card.masterCardId, variantKey: variantKey, notes: "")
            isCurrentCardWishlisted = true
            HapticManager.notification(.success)
        } catch let error as WishlistError {
            switch error {
            case .limitReached:
                showWishlistPaywall = true
            case .alreadyExists:
                wishlistAlertMessage = "This card and variant are already on your wishlist."
                showWishlistAlert = true
            case .saveFailed(let inner):
                wishlistAlertMessage = inner.localizedDescription
                showWishlistAlert = true
            }
        } catch {
            wishlistAlertMessage = error.localizedDescription
            showWishlistAlert = true
        }
    }

    private func removeCurrentCardFromWishlist() {
        guard let wl = services.wishlist else {
            wishlistAlertMessage = "Wishlist isn’t available yet. Try again in a moment."
            showWishlistAlert = true
            return
        }
        do {
            try wl.removeAllItems(forCardID: card.masterCardId)
            isCurrentCardWishlisted = false
            HapticManager.notification(.success)
        } catch let error as WishlistError {
            switch error {
            case .saveFailed(let inner):
                wishlistAlertMessage = inner.localizedDescription
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
        addToCollectionPayload = AddToCollectionSheetPayload(card: card, variantKey: variantKey, availableVariantKeys: wishlistVariantKeys)
        HapticManager.impact(.medium)
    }

    private func wishlistRowShowsCheckmark(for key: String) -> Bool {
        services.wishlist?.isInWishlist(cardID: card.masterCardId, variantKey: key) == true
    }

    private func variantTitle(_ key: String) -> String {
        let spaced = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return spaced.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func cleanedList(_ values: [String]?) -> String? {
        guard let values else { return nil }
        let cleanedValues = values.compactMap { cleaned($0) }
        guard !cleanedValues.isEmpty else { return nil }
        return cleanedValues.joined(separator: ", ")
    }

    private func currencyFormatter(code: String) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 2
        return formatter
    }

    private var pageBackground: Color {
        colorScheme == .dark ? .black : .white
    }

    private var cardAuraColors: [Color] {
        if extractedAuraColors.count >= 3 {
            return Array(extractedAuraColors.prefix(3))
        }
        if let first = extractedAuraColors.first {
            return [first, first.opacity(0.74), first.opacity(0.52)]
        }
        return [
            Color(red: 0.50, green: 0.60, blue: 0.74),
            Color(red: 0.63, green: 0.52, blue: 0.76),
            Color(red: 0.72, green: 0.60, blue: 0.68)
        ]
    }

    private func updateAuraColors(from image: UIImage) {
        let imageArea = image.size.width * image.size.height
        guard imageArea >= auraSourceImageArea else { return }

        auraSourceImageArea = imageArea

        Task.detached(priority: .utility) {
            let extracted = image.bindrAuraColors(maxColors: 3)
            guard !extracted.isEmpty else { return }
            await MainActor.run {
                extractedAuraColors = extracted
            }
        }
    }

    private var sectionInsetBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)
    }

    private var sectionBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }
}

private struct DetailSurface<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.primary)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(surfaceBorder, lineWidth: 1)
        )
    }

    @Environment(\.colorScheme) private var colorScheme

    private var surfaceBackground: Color {
        colorScheme == .dark ? .black : .white
    }

    private var surfaceBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }
}

struct HoldingGroup: Identifiable {
    let id: String
    let primaryItem: CollectionItem
    let itemKind: String
    let variantKey: String
    let gradingCompany: String?
    let grade: String?
    var totalQuantity: Int
    var lines: [HoldingLine]
}

struct HoldingLine: Identifiable {
    let id: String
    let item: CollectionItem
    let itemKind: String
    let variantKey: String
    let gradingCompany: String?
    let grade: String?
    var quantity: Int
    let date: Date
    let direction: LedgerDirection
    let unitPrice: Double?
    let currencyCode: String
    let counterparty: String?
    let description: String?
    var lotIDs: Set<UUID>

    var identityKey: String {
        [
            itemKind,
            variantKey,
            gradingCompany ?? "",
            grade ?? "",
            direction.rawValue,
            counterparty ?? "",
            description ?? "",
            currencyCode,
            (unitPrice.map { String(format: "%.6f", $0) } ?? ""),
            String(Int(date.timeIntervalSince1970))
        ].joined(separator: "|")
    }

    var priceText: String? {
        guard let unitPrice, unitPrice > 0 else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.string(from: NSNumber(value: unitPrice))
    }

    var directionTitle: String {
        switch direction {
        case .bought: return "Bought"
        case .packed: return "Packed"
        case .sold: return "Sold"
        case .tradedIn, .tradedOut: return "Traded"
        case .giftedIn, .giftedOut: return "Gifted"
        case .importedIn: return "Imported"
        case .adjustmentIn, .adjustmentOut: return "Adjusted"
        }
    }

    var tint: Color {
        switch direction {
        case .packed: return CardDetailPalette.gold
        case .bought: return CardDetailPalette.chartLine
        case .sold, .tradedOut, .giftedOut, .adjustmentOut: return CardDetailPalette.danger
        case .tradedIn, .giftedIn, .adjustmentIn, .importedIn: return CardDetailPalette.success
        }
    }

    var counterpartyLabel: String {
        switch direction {
        case .bought: return "From"
        case .sold: return "To"
        case .tradedIn, .tradedOut: return "Trade"
        case .giftedIn, .giftedOut: return "With"
        case .packed, .adjustmentIn, .adjustmentOut, .importedIn: return "Source"
        }
    }
}

enum CardDetailPalette {
    static let chartLine = Color(red: 0.12, green: 0.52, blue: 1.0)
    static let success = Color(red: 0.28, green: 0.84, blue: 0.39)
    static let gold = Color(red: 0.99, green: 0.72, blue: 0.22)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.34)
}

private extension UIImage {
    struct AuraBin: Hashable {
        let r: Int
        let g: Int
        let b: Int
    }

    func bindrAuraColors(maxColors: Int) -> [Color] {
        guard maxColors > 0 else { return [] }
        guard let cgImage else { return [] }

        let sampleWidth = 44
        let sampleHeight = 62
        let bytesPerPixel = 4
        let bytesPerRow = sampleWidth * bytesPerPixel
        let bitsPerComponent = 8
        var raw = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)

        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: &raw,
                width: sampleWidth,
                height: sampleHeight,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return []
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        var histogram: [AuraBin: Double] = [:]
        let step = 32.0

        for y in 0 ..< sampleHeight {
            for x in 0 ..< sampleWidth {
                let i = y * bytesPerRow + (x * bytesPerPixel)
                let r = Double(raw[i])
                let g = Double(raw[i + 1])
                let b = Double(raw[i + 2])
                let a = Double(raw[i + 3]) / 255.0
                guard a > 0.6 else { continue }

                let maxC = max(r, g, b) / 255.0
                let minC = min(r, g, b) / 255.0
                let delta = maxC - minC
                let saturation = maxC == 0 ? 0 : (delta / maxC)
                let brightness = maxC

                // Favor vibrant mid-tone regions from the artwork and avoid edge neutrals.
                guard saturation >= 0.22 else { continue }
                guard brightness >= 0.18 && brightness <= 0.94 else { continue }

                let rb = Int(floor(r / step))
                let gb = Int(floor(g / step))
                let bb = Int(floor(b / step))
                let weight = (0.3 + saturation * 1.6 + brightness * 0.2)
                histogram[AuraBin(r: rb, g: gb, b: bb), default: 0] += weight
            }
        }

        let sortedBins = histogram.sorted { $0.value > $1.value }.map(\.key)
        guard !sortedBins.isEmpty else { return [] }

        var selected: [SIMD3<Double>] = []

        for bin in sortedBins {
            let candidate = SIMD3<Double>(
                (Double(bin.r) + 0.5) * step / 255.0,
                (Double(bin.g) + 0.5) * step / 255.0,
                (Double(bin.b) + 0.5) * step / 255.0
            )

            let isDistinct = selected.allSatisfy { existing in
                let diff = candidate - existing
                let distance = sqrt((diff.x * diff.x) + (diff.y * diff.y) + (diff.z * diff.z))
                return distance > 0.22
            }

            if isDistinct {
                selected.append(candidate)
            }
            if selected.count == maxColors { break }
        }

        if selected.isEmpty, let fallback = sortedBins.first {
            selected = [
                SIMD3<Double>(
                    (Double(fallback.r) + 0.5) * step / 255.0,
                    (Double(fallback.g) + 0.5) * step / 255.0,
                    (Double(fallback.b) + 0.5) * step / 255.0
                )
            ]
        }

        if selected.count == 1, let first = selected.first {
            selected.append(first * 0.86)
            selected.append(first * 0.72)
        } else if selected.count == 2, let first = selected.first {
            selected.append((selected[1] * 0.7) + (first * 0.3))
        }

        return selected.prefix(maxColors).map { rgb in
            Color(red: rgb.x, green: rgb.y, blue: rgb.z)
        }
    }
}

struct HoldingDispositionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    let line: HoldingLine
    let cardDisplayName: String

    @State private var dispositionKind: CollectionDispositionKind = .sold
    @State private var quantity: Int = 1
    @State private var priceText: String = ""
    @State private var counterparty: String = ""
    @State private var notes: String = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(line.variantKey)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Status", selection: $dispositionKind) {
                        ForEach(CollectionDispositionKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...max(line.quantity, 1))
                }

                if dispositionKind == .sold {
                    Section {
                        TextField("Sold price per card", text: $priceText)
                            .keyboardType(.decimalPad)
                    }
                }

                Section {
                    TextField(counterpartyLabel, text: $counterparty)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .tint(colorScheme == .dark ? .white : .black)
            .navigationTitle("Mark Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                }
            }
            .onAppear {
                quantity = min(max(line.quantity, 1), quantity)
                services.setupCollectionLedger(modelContext: modelContext)
            }
        }
    }

    private var counterpartyLabel: String {
        switch dispositionKind {
        case .sold: return "Sold to"
        case .traded: return "Traded with"
        case .gifted: return "Gifted to"
        case .lost: return "Lost details"
        case .damaged: return "Damage details"
        }
    }

    private func save() {
        errorMessage = nil
        guard let ledger = services.collectionLedger else {
            errorMessage = "Collection isn’t ready. Try again."
            return
        }

        do {
            try ledger.recordSingleCardDisposition(
                item: line.item,
                kind: dispositionKind,
                quantity: quantity,
                currencyCode: services.priceDisplay.currency == .gbp ? "GBP" : "USD",
                cardDisplayName: cardDisplayName,
                unitPrice: try parsedOptionalPrice(priceText),
                counterparty: counterparty,
                notes: notes,
                preferredLotIDs: line.lotIDs
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parsedOptionalPrice(_ text: String) throws -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")) else {
            throw HoldingDispositionError.invalidPrice
        }
        return value
    }
}

enum HoldingDispositionError: LocalizedError {
    case invalidPrice

    var errorDescription: String? {
        switch self {
        case .invalidPrice:
            return "Enter a valid price."
        }
    }
}

// MARK: - Edit collection stack

struct EditCollectionItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    let line: HoldingLine
    let cardDisplayName: String
    let availableVariantKeys: [String]

    @State private var acquisitionKind: CollectionAcquisitionKind
    @State private var selectedVariantKey: String
    @State private var quantity: Int
    @State private var cardCondition: CardCondition
    @State private var gradingCompany: GradingCompany
    @State private var occurredAt: Date
    @State private var unitPriceText: String
    @State private var counterparty: String
    @State private var sourceDescription: String
    @State private var notes: String
    @State private var errorMessage: String?

    init(line: HoldingLine, cardDisplayName: String, availableVariantKeys: [String] = ["normal"]) {
        self.line = line
        self.cardDisplayName = cardDisplayName
        self.availableVariantKeys = availableVariantKeys.isEmpty ? ["normal"] : availableVariantKeys
        _acquisitionKind = State(initialValue: Self.acquisitionKind(for: line.direction))
        _selectedVariantKey = State(initialValue: line.variantKey)
        _quantity = State(initialValue: max(line.quantity, 1))
        _cardCondition = State(initialValue: line.itemKind == ProductKind.gradedItem.rawValue ? .graded : .raw)
        _gradingCompany = State(initialValue: Self.gradingCompany(for: line.gradingCompany))
        _occurredAt = State(initialValue: line.date)
        _unitPriceText = State(initialValue: line.unitPrice.map { String($0) } ?? "")
        _counterparty = State(initialValue: line.counterparty ?? "")
        _sourceDescription = State(initialValue: line.description ?? "")
        _notes = State(initialValue: line.item.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Purchase type", selection: $acquisitionKind) {
                        ForEach(CollectionAcquisitionKind.manualAddCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    if availableVariantKeys.count > 1 {
                        Picker("Variant", selection: $selectedVariantKey) {
                            ForEach(availableVariantKeys, id: \.self) { key in
                                Text(variantLabel(key)).tag(key)
                            }
                        }
                    } else {
                        HStack {
                            Text("Variant")
                            Spacer()
                            Text(variantLabel(selectedVariantKey))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Picker("Condition", selection: $cardCondition) {
                        ForEach(CardCondition.allCases, id: \.self) { condition in
                            Text(condition.title).tag(condition)
                        }
                    }
                    .pickerStyle(.segmented)

                    if cardCondition == .graded {
                        Picker("Grading company", selection: $gradingCompany) {
                            ForEach(GradingCompany.allCases, id: \.self) { company in
                                Text(company.title).tag(company)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                }

                Section {
                    DatePicker("Date", selection: $occurredAt, displayedComponents: .date)
                    TextField("Bought value / unit price", text: $unitPriceText)
                        .keyboardType(.decimalPad)
                    TextField("Source", text: $counterparty)
                    TextField("Details", text: $sourceDescription, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Button(role: .destructive) {
                        deleteItem()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete from Collection")
                                .bold()
                            Spacer()
                        }
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .tint(colorScheme == .dark ? .white : .black)
            .navigationTitle("Edit in collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
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
        guard services.collectionLedger != nil else {
            errorMessage = "Collection isn’t ready. Try again."
            return
        }
        do {
            let trimmedCounterparty = counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDescription = sourceDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            let parsedUnitPrice = try parsedOptionalPrice(unitPriceText)
            let directionRaw = acquisitionKind.ledgerDirection.rawValue
            let previousQuantity = line.quantity
            let delta = quantity - previousQuantity
            let targetProductKind = cardCondition == .graded ? ProductKind.gradedItem.rawValue : ProductKind.singleCard.rawValue
            let targetGradingCompany = cardCondition == .graded ? gradingCompany.rawValue : nil
            let targetGrade = cardCondition == .graded ? "10" : nil
            let isConditionOrVariantChange = line.item.itemKind != targetProductKind
                || line.item.variantKey != selectedVariantKey
                || line.item.gradingCompany != targetGradingCompany
                || line.item.grade != targetGrade

            if isConditionOrVariantChange {
                guard let ledger = services.collectionLedger else {
                    errorMessage = "Collection isn’t ready. Try again."
                    return
                }
                let target = try ledger.reclassifyCardUnits(
                    item: line.item,
                    quantity: min(quantity, line.item.quantity),
                    targetVariantKey: selectedVariantKey,
                    targetProductKind: targetProductKind,
                    targetGradingCompany: targetGradingCompany,
                    targetGrade: targetGrade,
                    preferredLotIDs: line.lotIDs
                )
                target.notes = notes
                try modelContext.save()
                dismiss()
                return
            }

            let selectedLots = (line.item.costLots ?? []).filter { line.lotIDs.contains($0.id) }
            let selectedUnits = selectedLots.reduce(0) { $0 + $1.quantityRemaining }
            if selectedUnits > 0 {
                var remaining = quantity
                let sorted = selectedLots.sorted { $0.createdAt > $1.createdAt }
                for lot in sorted {
                    let assigned = min(remaining, lot.quantityRemaining)
                    lot.quantityRemaining = assigned
                    remaining -= assigned
                }
                if remaining > 0, let first = sorted.first {
                    first.quantityRemaining += remaining
                }
            }

            if delta != 0 {
                line.item.quantity = max(1, line.item.quantity + delta)
            }

            for lot in selectedLots {
                if let ledgerLine = lot.sourceLedgerLine {
                    ledgerLine.occurredAt = occurredAt
                    ledgerLine.direction = directionRaw
                    ledgerLine.unitPrice = parsedUnitPrice
                    ledgerLine.currencyCode = services.priceDisplay.currency == .gbp ? "GBP" : "USD"
                    ledgerLine.counterparty = trimmedCounterparty.isEmpty ? nil : trimmedCounterparty
                    ledgerLine.lineDescription = trimmedDescription.isEmpty ? cardDisplayName : trimmedDescription
                    ledgerLine.quantity = selectedLots
                        .filter { $0.sourceLedgerLine?.id == ledgerLine.id }
                        .reduce(0) { $0 + $1.quantityRemaining }
                }
            }

            line.item.notes = notes
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteItem() {
        errorMessage = nil
        services.setupCollectionLedger(modelContext: modelContext)
        guard let ledger = services.collectionLedger else {
            errorMessage = "Collection isn’t ready. Try again."
            return
        }
        do {
            let selectedLots = (line.item.costLots ?? []).filter { line.lotIDs.contains($0.id) }
            for lot in selectedLots {
                if let ledgerLine = lot.sourceLedgerLine {
                    try ledger.deleteLedgerLineAndReconcileCollection(ledgerLine)
                }
                modelContext.delete(lot)
            }
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parsedOptionalPrice(_ text: String) throws -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")) else {
            throw HoldingDispositionError.invalidPrice
        }
        return value
    }

    private func variantLabel(_ key: String) -> String {
        let spaced = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return spaced.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private static func acquisitionKind(for direction: LedgerDirection) -> CollectionAcquisitionKind {
        switch direction {
        case .bought: return .bought
        case .packed: return .packed
        case .giftedIn, .giftedOut: return .gifted
        case .tradedIn, .tradedOut: return .trade
        case .importedIn: return .imported
        case .sold, .adjustmentIn, .adjustmentOut: return .bought
        }
    }

    private static func gradingCompany(for raw: String?) -> GradingCompany {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() else { return .psa }
        return GradingCompany(rawValue: raw) ?? .psa
    }
}
