import SwiftData
import SwiftUI

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

    @State private var index: Int
    @State private var navigationPath = NavigationPath()

    init(
        cards: [Card],
        startIndex: Int,
        addToDeckAction: ((Card, String, Int) -> Void)? = nil,
        showsHeaderChromeActions: Bool = true,
        showsWishlistWhenChromeHidden: Bool = false
    ) {
        self.cards = cards
        self.addToDeckAction = addToDeckAction
        self.showsHeaderChromeActions = showsHeaderChromeActions
        self.showsWishlistWhenChromeHidden = showsWishlistWhenChromeHidden
        let clamped: Int = {
            guard !cards.isEmpty else { return 0 }
            return min(max(0, startIndex), cards.count - 1)
        }()
        _index = State(initialValue: clamped)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
                                onOpenSet: {
                                    if let set = services.cardData.sets.first(where: { $0.setCode == card.setCode }) {
                                        navigationPath.append(set)
                                    }
                                }
                            )
                            .tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.clear)
                }
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
                ImagePrefetcher.shared.prefetchHighResForDetailView(cards, currentIndex: index, window: 2)
            }
            .onChange(of: index) { _, _ in
                HapticManager.selection()
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
    let onOpenSet: () -> Void

    @State private var editingLine: HoldingLine?
    @State private var dispositionLine: HoldingLine?
    @State private var addToCollectionPayload: AddToCollectionSheetPayload?
    @State private var addToFolderPayload: AddToFolderSheetPayload?
    @State private var showCardShare = false
    @State private var wishlistVariantKeys: [String] = ["normal"]
    @State private var isCurrentCardWishlisted = false
    @State private var showWishlistPaywall = false
    @State private var wishlistAlertMessage: String?
    @State private var showWishlistAlert = false
    @State private var deckAddQuantity: Int = 1
    @State private var imageAppeared = false

    private static let wishlistActiveStarColor = Color(red: 0.98, green: 0.78, blue: 0.18)

    init(
        card: Card,
        set: TCGSet?,
        addToDeckAction: ((Card, String, Int) -> Void)?,
        showsCollectionAction: Bool,
        showsWishlistAction: Bool,
        onOpenSet: @escaping () -> Void
    ) {
        self.card = card
        self.set = set
        self.addToDeckAction = addToDeckAction
        self.showsCollectionAction = showsCollectionAction
        self.showsWishlistAction = showsWishlistAction
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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                cardImage
                    .padding(.top, 20)
                    .padding(.horizontal, 6)

                cardMetaRow

                CardPricingPanel(card: card)
                recentSoldOnEbayButton

                if showsCollectionSection {
                    collectionSection
                }

                if !summaryFacts.isEmpty || card.attacks != nil || card.abilities != nil || cleaned(card.rules) != nil || cleaned(card.flavorText) != nil {
                    cardDetailsSection
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, minHeight: 0, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pageBackground)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .task(id: card.masterCardId) {
            await loadWishlistVariantKeys()
        }
        .onAppear {
            services.setupCollectionLedger(modelContext: modelContext)
        }
        .sheet(item: $editingLine) { line in
            EditCollectionItemSheet(line: line, cardDisplayName: card.cardName)
        }
        .sheet(item: $dispositionLine) { line in
            HoldingDispositionSheet(line: line, cardDisplayName: card.cardName)
        }
        .sheet(item: $addToCollectionPayload) { payload in
            AddToCollectionSheet(card: payload.card, variantKey: payload.variantKey)
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

    private var recentSoldOnEbayButton: some View {
        Button {
            guard let url = ebayRecentSoldURL else { return }
            openURL(url)
        } label: {
            HStack(spacing: 10) {
                ebayWordmark
                Text("Recent Sold on eBay")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right.square")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(sectionInsetBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(sectionBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open recent sold listings on eBay")
    }

    private var ebayWordmark: some View {
        HStack(spacing: 0) {
            Text("e").foregroundStyle(Color(red: 0.89, green: 0.15, blue: 0.13))
            Text("B").foregroundStyle(Color(red: 0.00, green: 0.38, blue: 0.75))
            Text("a").foregroundStyle(Color(red: 0.97, green: 0.74, blue: 0.06))
            Text("y").foregroundStyle(Color(red: 0.44, green: 0.68, blue: 0.11))
        }
        .font(.system(size: 18, weight: .bold, design: .rounded))
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
        ProgressiveAsyncImage(
            lowResURL: AppConfiguration.imageURL(relativePath: card.imageLowSrc),
            highResURL: card.imageHighSrc.map { AppConfiguration.imageURL(relativePath: $0) }
        ) {
            Color(uiColor: .tertiarySystemFill)
                .aspectRatio(5 / 7, contentMode: .fit)
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

                if let variantKey = singleAvailableVariantKey {
                    Button {
                        deckAction(card, variantKey, deckAddQuantity)
                        deckAddQuantity = 1
                    } label: {
                        cardActionBody(
                            title: "Add to Deck",
                            systemImage: "plus.circle.fill",
                            tint: CardDetailPalette.chartLine
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    Menu {
                        Section {
                            Stepper("Quantity: \(deckAddQuantity)", value: $deckAddQuantity, in: 1...20)
                        }
                        Section("Select Variant") {
                            ForEach(wishlistVariantKeys, id: \.self) { key in
                                Button {
                                    deckAction(card, key, deckAddQuantity)
                                    deckAddQuantity = 1
                                } label: {
                                    Text(variantTitle(key))
                                }
                            }
                        }
                    } label: {
                        cardActionBody(
                            title: "Add to Deck",
                            systemImage: "plus.circle.fill",
                            tint: CardDetailPalette.chartLine
                        )
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                }
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
                    title: "Add to Collection",
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
                    title: "Add to Collection",
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
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(glassButtonBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(glassButtonBorder, lineWidth: 1)
                )
        }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                infoBadge(label: line.directionTitle, tint: line.tint)
                Text("Qty \(line.quantity)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(line.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if let priceText = line.priceText {
                    labelValueRow(label: "Price", value: priceText)
                }
                if let counterparty = line.counterparty {
                    labelValueRow(label: line.counterpartyLabel, value: counterparty)
                }
                Spacer(minLength: 8)
                Button("Edit") { editingLine = line }
                    .buttonStyle(.bordered)
                    .tint(colorScheme == .dark ? .white : .black)
                Button("Mark As") { dispositionLine = line }
                    .buttonStyle(.borderedProminent)
                    .tint(CardDetailPalette.chartLine)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(sectionInsetBackground.opacity(0.55))
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
        addToCollectionPayload = AddToCollectionSheetPayload(card: card, variantKey: variantKey)
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

    private var glassButtonBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
    }

    private var glassButtonBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
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

private struct HoldingGroup: Identifiable {
    let id: String
    let primaryItem: CollectionItem
    let itemKind: String
    let variantKey: String
    let gradingCompany: String?
    let grade: String?
    var totalQuantity: Int
    var lines: [HoldingLine]
}

private struct HoldingLine: Identifiable {
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
        case .adjustmentIn, .adjustmentOut: return "Adjusted"
        }
    }

    var tint: Color {
        switch direction {
        case .packed: return CardDetailPalette.gold
        case .bought: return CardDetailPalette.chartLine
        case .sold, .tradedOut, .giftedOut, .adjustmentOut: return CardDetailPalette.danger
        case .tradedIn, .giftedIn, .adjustmentIn: return CardDetailPalette.success
        }
    }

    var counterpartyLabel: String {
        switch direction {
        case .bought: return "From"
        case .sold: return "To"
        case .tradedIn, .tradedOut: return "Trade"
        case .giftedIn, .giftedOut: return "With"
        case .packed, .adjustmentIn, .adjustmentOut: return "Source"
        }
    }
}

private enum CardDetailPalette {
    static let chartLine = Color(red: 0.12, green: 0.52, blue: 1.0)
    static let success = Color(red: 0.28, green: 0.84, blue: 0.39)
    static let gold = Color(red: 0.99, green: 0.72, blue: 0.22)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.34)
}

private struct HoldingDispositionSheet: View {
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

private enum HoldingDispositionError: LocalizedError {
    case invalidPrice

    var errorDescription: String? {
        switch self {
        case .invalidPrice:
            return "Enter a valid price."
        }
    }
}

// MARK: - Edit collection stack

private struct EditCollectionItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    let line: HoldingLine
    let cardDisplayName: String

    @State private var acquisitionKind: CollectionAcquisitionKind
    @State private var quantity: Int
    @State private var cardCondition: CardCondition
    @State private var gradingCompany: GradingCompany
    @State private var occurredAt: Date
    @State private var unitPriceText: String
    @State private var counterparty: String
    @State private var sourceDescription: String
    @State private var notes: String
    @State private var errorMessage: String?

    init(line: HoldingLine, cardDisplayName: String) {
        self.line = line
        self.cardDisplayName = cardDisplayName
        _acquisitionKind = State(initialValue: Self.acquisitionKind(for: line.direction))
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
                        ForEach(CollectionAcquisitionKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
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

            line.item.itemKind = cardCondition == .graded ? ProductKind.gradedItem.rawValue : ProductKind.singleCard.rawValue
            line.item.gradingCompany = cardCondition == .graded ? gradingCompany.rawValue : nil
            line.item.grade = cardCondition == .graded ? "10" : nil
            line.item.notes = notes
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

    private static func acquisitionKind(for direction: LedgerDirection) -> CollectionAcquisitionKind {
        switch direction {
        case .bought: return .bought
        case .packed: return .packed
        case .giftedIn, .giftedOut: return .gifted
        case .tradedIn, .tradedOut: return .trade
        case .sold, .adjustmentIn, .adjustmentOut: return .bought
        }
    }

    private static func gradingCompany(for raw: String?) -> GradingCompany {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() else { return .psa }
        return GradingCompany(rawValue: raw) ?? .psa
    }
}
