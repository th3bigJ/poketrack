import SwiftData
import SwiftUI
import UIKit

struct CardDetailSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var collectionItems: [CollectionItem]

    let cards: [Card]
    /// When opened from a specific friend context (profile, trade wall), trade goes directly to them.
    var directTradeContext: CardTradeContext? = nil

    @State private var index: Int
    @State private var scrollIndex: Int?
    @State private var hasAppliedInitialScrollPosition = false
    @State private var editingLine: HoldingLine?
    @State private var dispositionFlowPayload: CollectionDispositionFlowPayload?
    @State private var addToCollectionPayload: AddToCollectionSheetPayload?
    @State private var shareCard: Card? = nil
    @State private var wishlistVariantKeys: [String] = ["normal"]
    @State private var isCurrentCardWishlisted = false
    @State private var showWishlistPaywall = false
    @State private var wishlistAlertMessage: String?
    @State private var showWishlistAlert = false
    @State private var collectionSuccessSparkTrigger = 0
    @State private var wishlistSuccessSparkTrigger = 0
    @State private var collectionAddSuccessPresentation: AddToCollectionSuccessPresentation?
    @State private var auraColorsByCardID: [String: [Color]] = [:]
    @State private var auraSourceImageAreaByCardID: [String: CGFloat] = [:]
    @State private var pushedSet: TCGSet? = nil

    private static let wishlistActiveStarColor = Color(red: 0.98, green: 0.78, blue: 0.18)

    init(
        cards: [Card],
        startIndex: Int = 0,
        directTradeContext: CardTradeContext? = nil
    ) {
        self.cards = cards
        self.directTradeContext = directTradeContext
        let clamped = cards.isEmpty ? 0 : min(max(0, startIndex), cards.count - 1)
        _index = State(initialValue: clamped)
        _scrollIndex = State(initialValue: clamped)
        let cardID = cards.isEmpty ? "" : cards[clamped].masterCardId
        _collectionItems = Query(
            filter: #Predicate<CollectionItem> { $0.cardID == cardID },
            sort: [SortDescriptor(\.variantKey)]
        )
    }

    private var currentCard: Card { cards[index] }
    private func set(for card: Card) -> TCGSet? { services.cardData.sets.first { $0.setCode == card.setCode } }

    private var visibleCollectionItems: [CollectionItem] {
        collectionItems.filter { $0.quantity > 0 }
    }

    private func showsCollectionSection(for card: Card) -> Bool {
        let brand = TCGBrand.inferredFromMasterCardId(card.masterCardId)
        guard services.brandSettings.enabledBrands.contains(brand) else { return false }
        return !visibleCollectionItems.isEmpty
    }

    private var singleAvailableVariantKey: String? {
        wishlistVariantKeys.count == 1 ? wishlistVariantKeys[0] : nil
    }

    private func summaryFacts(for card: Card) -> [(String, String)] {
        var facts: [(String, String)] = []
        if let number = cleaned(card.printedNumber) ?? cleaned(card.cardNumber) { facts.append(("Number", number)) }
        if let rarity = cleaned(card.rarity) { facts.append(("Rarity", rarity)) }
        if let category = cleaned(card.category) { facts.append(("Category", category)) }
        if let stage = cleaned(card.stage) { facts.append(("Stage", stage)) }
        if let hp = card.hp { facts.append(("HP", "\(hp)")) }
        if let types = cleanedList(card.elementTypes) { facts.append(("Type", types)) }
        if let subtypes = cleanedList(card.subtypes) ?? cleaned(card.subtype) { facts.append(("Subtype", subtypes)) }
        if let trainerType = cleaned(card.trainerType) { facts.append(("Trainer", trainerType)) }
        if let energyType = cleaned(card.energyType) { facts.append(("Energy", energyType)) }
        if let regulationMark = cleaned(card.regulationMark) { facts.append(("Regulation", regulationMark)) }
        if let evolvesFrom = cleaned(card.evolveFrom) { facts.append(("Evolves From", evolvesFrom)) }
        if let artist = cleaned(card.artist) { facts.append(("Artist", artist)) }
        if let weakness = cleaned(card.weakness) { facts.append(("Weakness", weakness)) }
        if let resistance = cleaned(card.resistance) { facts.append(("Resistance", resistance)) }
        if let retreatCost = card.retreatCost { facts.append(("Retreat", "\(retreatCost)")) }
        if let attributes = cleanedList(card.opAttributes) { facts.append(("Attributes", attributes)) }
        if let cost = card.opCost { facts.append(("Cost", "\(cost)")) }
        if let counter = card.opCounter { facts.append(("Counter", "\(counter)")) }
        if let life = card.opLife { facts.append(("Life", "\(life)")) }
        return facts
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(cards.indices), id: \.self) { i in
                        cardPage(for: cards[i])
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id(i)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrollIndex)
            .scrollContentBackground(.hidden)
            .onChange(of: scrollIndex) { _, i in
                guard let i else { return }
                index = i
                HapticManager.selection()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(sheetBackground)
        .task(id: currentCard.masterCardId) {
            await loadWishlistVariantKeys()
        }
        .onAppear {
            services.setupCollectionLedger(modelContext: modelContext)
            applyInitialScrollPositionIfNeeded()
        }
        .sheet(item: $editingLine) { line in
            EditCollectionItemSheet(
                line: line,
                cardDisplayName: currentCard.cardName,
                availableVariantKeys: wishlistVariantKeys
            )
        }
        .sheet(item: $dispositionFlowPayload) { payload in
            CollectionDispositionFlowSheet(lines: payload.lines, cardDisplayName: payload.cardDisplayName)
        }
        .sheet(item: $addToCollectionPayload) { payload in
            AddToCollectionSheet(
                card: payload.card,
                variantKey: payload.variantKey,
                availableVariantKeys: payload.availableVariantKeys,
                onSaved: { context in
                    scheduleCollectionAddSuccess(context)
                }
            )
                .environment(services)
        }
        .sheet(item: $shareCard) { card in
            SocialShareSheet(item: .cardDetail(card))
                .environment(services)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showWishlistPaywall) {
            PaywallSheet()
                .environment(services)
        }
        .sheet(item: $pushedSet) { set in
            NavigationStack { SetCardsView(set: set) }
        }
        .alert("Wishlist", isPresented: $showWishlistAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(wishlistAlertMessage ?? "")
        }
        .overlay {
            if let collectionAddSuccessPresentation {
                AddToCollectionSuccessOverlay(presentation: collectionAddSuccessPresentation)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: collectionAddSuccessPresentation?.id)
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .presentationCornerRadius(20)
    }

    private func scheduleCollectionAddSuccess(_ context: AddToCollectionSuccessContext) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(360))
            let presentation = await makeAddToCollectionSuccessPresentation(for: context, services: services)
            collectionSuccessSparkTrigger += 1

            withAnimation(.easeOut(duration: 0.18)) {
                collectionAddSuccessPresentation = presentation
            }

            let activeID = presentation.id
            try? await Task.sleep(for: .milliseconds(presentation.isSpecial ? 1_150 : 900))
            guard collectionAddSuccessPresentation?.id == activeID else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                collectionAddSuccessPresentation = nil
            }
        }
    }

    private func applyInitialScrollPositionIfNeeded() {
        guard !hasAppliedInitialScrollPosition else { return }
        hasAppliedInitialScrollPosition = true
        let targetIndex = index

        Task { @MainActor in
            scrollIndex = nil
            await Task.yield()
            await Task.yield()

            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                scrollIndex = targetIndex
            }
        }
    }

    private func cardPage(for pageCard: Card) -> some View {
        let facts = summaryFacts(for: pageCard)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                cardHeroSection(for: pageCard)
                CardPricingPanel(card: pageCard, useGlass: true)
                    .glassCardStyle(cornerRadius: 26, interactive: false)
                recentSoldOnEbayButton(for: pageCard)
                    .glassCardStyle(cornerRadius: 26, interactive: false)
                if showsCollectionSection(for: pageCard) { collectionSection }
                if !facts.isEmpty || pageCard.attacks != nil || pageCard.abilities != nil || cleaned(pageCard.rules) != nil || cleaned(pageCard.flavorText) != nil {
                    cardDetailsSection(for: pageCard, facts: facts)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    // MARK: - Hero

    private func cardHeroSection(for card: Card) -> some View {
        VStack(spacing: 10) {
            cardImage(for: card)
                .padding(.top, 20)
                .padding(.horizontal, 6)
            cardMetaRow(for: card)
        }
    }

    private func cardImage(for card: Card) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(
                    colors: cardAuraColors.map { $0.opacity(colorScheme == .dark ? 0.52 : 0.36) },
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(maxWidth: .infinity)
                .aspectRatio(5 / 7, contentMode: .fit)
                .blur(radius: colorScheme == .dark ? 40 : 32)
                .scaleEffect(1.05)

            ProgressiveAsyncImage(
                lowResURL: AppConfiguration.imageURL(relativePath: card.displayImageSrc),
                highResURL: card.imageHighSrc.map { AppConfiguration.imageURL(relativePath: $0) },
                onImageLoaded: { updateAuraColors(from: $0, cardID: card.masterCardId) }
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
    }

    private func cardMetaRow(for card: Card) -> some View {
        VStack(spacing: 12) {
            titleBlock(for: card)
            
            CardActionMenu(
                isOwned: showsCollectionSection(for: card),
                isWishlisted: isCurrentCardWishlisted,
                availableVariantKeys: wishlistVariantKeys,
                card: card,
                onSaveToCollection: { variantKey in
                    addToCollectionVariant(card: card, variantKey: variantKey)
                },
                onRemoveFromCollection: {
                    openRemoveFromCollectionFlow(for: card)
                },
                onAddToWishlist: {
                    if let variantKey = singleAvailableVariantKey {
                        addToWishlist(variantKey: variantKey)
                    } else {
                        addToWishlist(variantKey: wishlistVariantKeys.first ?? "normal")
                    }
                },
                onRemoveFromWishlist: {
                    removeCurrentCardFromWishlist()
                },
                onShareAction: {
                    shareCard = card
                },
                collectionSuccessTrigger: collectionSuccessSparkTrigger,
                wishlistSuccessTrigger: wishlistSuccessSparkTrigger
            )

            CardFriendTradeMatchesSection(card: card, directContext: directTradeContext)
        }
    }

    private func titleBlock(for card: Card) -> some View {
        VStack(spacing: 4) {
            Text(card.cardName)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
            centeredSetBlock(for: card)
        }
    }

    @ViewBuilder
    private func centeredSetBlock(for card: Card) -> some View {
        if let set = set(for: card) {
            Button { pushedSet = set } label: {
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

    private var allHoldingLines: [HoldingLine] {
        groupedHoldings
            .flatMap(\.lines)
            .sorted { $0.date > $1.date }
    }

    private func openRemoveFromCollectionFlow(for card: Card) {
        let lines = allHoldingLines
        guard !lines.isEmpty else { return }
        dispositionFlowPayload = CollectionDispositionFlowPayload(lines: lines, cardDisplayName: card.cardName)
        Haptics.lightImpact()
    }

    // MARK: - eBay

    private func recentSoldOnEbayButton(for card: Card) -> some View {
        Button {
            guard let url = ebayRecentSoldURL(for: card) else { return }
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
                    .glassInsetCircleStyle()
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
            .glassInsetStyle(cornerRadius: 12)
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

    private func ebayRecentSoldURL(for card: Card) -> URL? {
        let cardName = card.cardName.trimmingCharacters(in: .whitespacesAndNewlines)
        let setName = cleaned(set(for: card)?.name) ?? card.setCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let cardNumber = (cleaned(card.printedNumber) ?? cleaned(card.cardNumber) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let searchText = [cardName, setName, cardNumber].filter { !$0.isEmpty }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchText.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.ebay.com/sch/i.html")
        components?.queryItems = [
            URLQueryItem(name: "_nkw", value: searchText),
            URLQueryItem(name: "LH_Sold", value: "1"),
            URLQueryItem(name: "LH_Complete", value: "1")
        ]
        return components?.url
    }

    // MARK: - Collection section

    private var collectionSection: some View {
        DebugDetailSurface(title: "Collection") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(groupedHoldings) { group in holdingCard(for: group) }
            }
        }
    }

    private func holdingCard(for group: HoldingGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(group.totalQuantity) \(group.totalQuantity == 1 ? "copy" : "copies")")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(variantTitle(group.variantKey))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    infoBadge(label: group.itemKind == ProductKind.gradedItem.rawValue ? "Graded" : "Raw", tint: DebugPalette.chartLine)
                    if let company = cleaned(group.gradingCompany), let grade = cleaned(group.grade) {
                        infoBadge(label: "\(company) \(grade)", tint: DebugPalette.gold)
                    }
                }
            }

            VStack(spacing: 8) {
                ForEach(group.lines) { line in holdingSourceRow(line) }
            }

            if let notes = cleaned(group.primaryItem.notes) {
                Label(notes, systemImage: "note.text")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func holdingSourceRow(_ line: HoldingLine) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(line.tint.opacity(colorScheme == .dark ? 0.20 : 0.14))
                    .frame(width: 42, height: 42)
                Image(systemName: holdingIcon(for: line.direction))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(line.tint)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(line.directionTitle)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Qty \(line.quantity)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(line.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(line.tint.opacity(0.12), in: Capsule())
                }

                HStack(spacing: 5) {
                    Text(line.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    if let priceText = line.priceText {
                        separatorDot
                        Text(priceText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DebugPalette.chartLine)
                    }

                    if let source = holdingSourceText(for: line) {
                        separatorDot
                        Text(source)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            holdingActionButton(systemImage: "pencil", title: "Edit acquisition", tint: .primary, usesNeutralFill: true) {
                editingLine = line
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .glassInsetStyle(cornerRadius: 18)
    }

    private var separatorDot: some View {
        Circle()
            .fill(Color.secondary.opacity(0.45))
            .frame(width: 3, height: 3)
    }

    private func holdingActionButton(
        systemImage: String,
        title: String,
        tint: Color,
        usesNeutralFill: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if usesNeutralFill {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 40, height: 40)
                        .glassInsetCircleStyle()
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(tint.opacity(0.12)))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func holdingIcon(for direction: LedgerDirection) -> String {
        switch direction {
        case .packed: return "shippingbox.fill"
        case .bought: return "cart.fill"
        case .sold: return "dollarsign.circle.fill"
        case .tradedIn, .tradedOut: return "arrow.left.arrow.right"
        case .giftedIn, .giftedOut: return "gift.fill"
        case .adjustmentIn, .adjustmentOut: return "slider.horizontal.3"
        case .importedIn: return "square.and.arrow.down.fill"
        }
    }

    private func holdingSourceText(for line: HoldingLine) -> String? {
        if let counterparty = cleaned(line.counterparty) {
            return "\(line.counterpartyLabel) \(counterparty)"
        }
        return cleaned(line.description)
    }

    // MARK: - Card details section

    private func cardDetailsSection(for card: Card, facts: [(String, String)]) -> some View {
        DebugDetailSurface(title: "Card Details") {
            VStack(alignment: .leading, spacing: 14) {
                if !facts.isEmpty {
                    let factRows = stride(from: 0, to: facts.count, by: 2).map { Array(facts[$0..<min($0+2, facts.count)]) }
                    VStack(spacing: 10) {
                        ForEach(Array(factRows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 12) {
                                ForEach(row, id: \.0) { fact in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(fact.0).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                        Text(fact.1).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .glassInsetStyle(cornerRadius: 16)
                                }
                                if row.count < 2 { Color.clear.frame(maxWidth: .infinity) }
                            }
                        }
                    }
                }
                if let attacks = card.attacks, !attacks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Attacks").font(.headline).foregroundStyle(.primary)
                        ForEach(Array(attacks.enumerated()), id: \.offset) { _, attack in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(attack.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    Spacer(minLength: 8)
                                    if let damage = cleaned(attack.damage) {
                                        Text(damage).font(.subheadline.weight(.bold)).foregroundStyle(DebugPalette.chartLine)
                                    }
                                }
                                if let cost = cleanedList(attack.cost) {
                                    Text(cost).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                }
                                if let effect = cleaned(attack.effect) {
                                    Text(effect).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .glassInsetStyle(cornerRadius: 18)
                        }
                    }
                }
                if let abilities = card.abilities, !abilities.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Abilities").font(.headline).foregroundStyle(.primary)
                        ForEach(Array(abilities.enumerated()), id: \.offset) { _, ability in
                            if let text = cleaned(ability.text) {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 8) {
                                        if let type = cleaned(ability.type) {
                                            Text(type.uppercased())
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(DebugPalette.chartLine)
                                                .padding(.horizontal, 8).padding(.vertical, 4)
                                                .background(Capsule(style: .continuous).fill(DebugPalette.chartLine.opacity(0.14)))
                                        }
                                        if let name = cleaned(ability.name) {
                                            Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        }
                                    }
                                    Text(text).font(.subheadline).foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .glassInsetStyle(cornerRadius: 18)
                            }
                        }
                    }
                }
                if let rules = cleaned(card.rules) { detailTextBlock(title: "Rules", body: rules) }
                if let flavorText = cleaned(card.flavorText) { detailTextBlock(title: "Flavor Text", body: flavorText) }
            }
        }
    }

    private func detailTextBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(.primary)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .glassInsetStyle(cornerRadius: 18)
        }
    }

    private func labelValueRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.medium)).foregroundStyle(.primary)
        }
    }

    private func infoBadge(label: String, tint: Color) -> some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule(style: .continuous).fill(tint.opacity(0.14)))
    }

    // MARK: - Variant menu

    @ViewBuilder
    private func variantSelectionMenuContent(for card: Card, sectionHeader: String, showWishlistCheckmarks: Bool, onSelect: @escaping (String) -> Void) -> some View {
        Section {
            ForEach(wishlistVariantKeys, id: \.self) { key in
                Button { onSelect(key) } label: {
                    HStack(spacing: 10) {
                        if showWishlistCheckmarks {
                            if services.wishlist?.isInWishlist(cardID: card.masterCardId, variantKey: key) == true {
                                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Self.wishlistActiveStarColor).frame(width: 18, alignment: .leading)
                            } else {
                                Color.clear.frame(width: 18, height: 1)
                            }
                        }
                        Text(variantTitle(key)).foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                }
            }
        } header: { Text(sectionHeader) }
    }

    // MARK: - Grouped holdings

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
                let groupKey = [item.itemKind, item.variantKey, cleaned(item.gradingCompany) ?? "", cleaned(item.grade) ?? ""].joined(separator: "|")
                let lineID = [groupKey, direction.rawValue, counterparty ?? "", description ?? "", currencyCode, (unitPrice.map { String(format: "%.6f", $0) } ?? ""), String(Int(date.timeIntervalSince1970))].joined(separator: "|")
                let holdingLine = HoldingLine(
                    id: lineID + "|\(lot.id.uuidString)", item: item, itemKind: item.itemKind,
                    variantKey: item.variantKey, gradingCompany: cleaned(item.gradingCompany), grade: cleaned(item.grade),
                    quantity: lot.quantityRemaining, date: date, direction: direction, unitPrice: unitPrice,
                    currencyCode: currencyCode, counterparty: counterparty, description: description, lotIDs: [lot.id]
                )
                if var existingGroup = groups[groupKey] {
                    existingGroup.totalQuantity += lot.quantityRemaining
                    if let idx = existingGroup.lines.firstIndex(where: { $0.identityKey == holdingLine.identityKey }) {
                        existingGroup.lines[idx].quantity += lot.quantityRemaining
                        existingGroup.lines[idx].lotIDs.insert(lot.id)
                    } else {
                        existingGroup.lines.append(holdingLine)
                    }
                    groups[groupKey] = existingGroup
                } else {
                    groups[groupKey] = HoldingGroup(id: groupKey, primaryItem: item, itemKind: item.itemKind,
                        variantKey: item.variantKey, gradingCompany: cleaned(item.gradingCompany), grade: cleaned(item.grade),
                        totalQuantity: lot.quantityRemaining, lines: [holdingLine])
                }
            }
        }
        return groups.values.map { var m = $0; m.lines.sort { $0.date > $1.date }; return m }.sorted { ($0.lines.first?.date ?? .distantPast) > ($1.lines.first?.date ?? .distantPast) }
    }

    // MARK: - Wishlist actions

    private func refreshWishlistState() {
        isCurrentCardWishlisted = services.wishlist?.isInWishlist(cardID: currentCard.masterCardId) ?? false
    }

    private func loadWishlistVariantKeys() async {
        var keys = await services.pricing.variantKeys(for: currentCard)
        if keys.isEmpty, let pv = currentCard.pricingVariants, !pv.isEmpty { keys = pv }
        if keys.isEmpty { keys = ["normal"] }
        wishlistVariantKeys = keys
        refreshWishlistState()
    }

    private func addToWishlist(variantKey: String) {
        guard let wl = services.wishlist else {
            wishlistAlertMessage = "Wishlist isn't available yet. Try again in a moment."
            showWishlistAlert = true
            return
        }
        do {
            try wl.addItem(cardID: currentCard.masterCardId, variantKey: variantKey, notes: "")
            isCurrentCardWishlisted = true
            wishlistSuccessSparkTrigger += 1
            HapticManager.notification(.success)
        } catch let error as WishlistError {
            switch error {
            case .limitReached: showWishlistPaywall = true
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
            wishlistAlertMessage = "Wishlist isn't available yet. Try again in a moment."
            showWishlistAlert = true
            return
        }
        do {
            try wl.removeAllItems(forCardID: currentCard.masterCardId)
            isCurrentCardWishlisted = false
            HapticManager.notification(.success)
        } catch let error as WishlistError {
            switch error {
            case .saveFailed(let inner):
                wishlistAlertMessage = inner.localizedDescription
                showWishlistAlert = true
            case .limitReached, .alreadyExists: break
            }
        } catch {
            wishlistAlertMessage = error.localizedDescription
            showWishlistAlert = true
        }
    }

    private func addToCollectionVariant(card: Card, variantKey: String) {
        addToCollectionPayload = AddToCollectionSheetPayload(card: card, variantKey: variantKey, availableVariantKeys: wishlistVariantKeys)
        HapticManager.impact(.medium)
    }

    private func variantTitle(_ key: String) -> String {
        let spaced = key.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return spaced.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
    }

    private func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func cleanedList(_ values: [String]?) -> String? {
        guard let values else { return nil }
        let items = values.compactMap { cleaned($0) }
        guard !items.isEmpty else { return nil }
        return items.joined(separator: ", ")
    }

    // MARK: - Aura

    private var sheetBackground: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.white)
            cardAuraColors[0].opacity(colorScheme == .dark ? 0.30 : 0.16)
            LinearGradient(
                colors: [
                    cardAuraColors[1].opacity(colorScheme == .dark ? 0.24 : 0.14),
                    .clear,
                    cardAuraColors[2].opacity(colorScheme == .dark ? 0.24 : 0.14),
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
        .ignoresSafeArea()
    }

    private var cardAuraColors: [Color] {
        let extracted = auraColorsByCardID[currentCard.masterCardId] ?? []
        if extracted.count >= 3 { return Array(extracted.prefix(3)) }
        if let first = extracted.first { return [first, first.opacity(0.74), first.opacity(0.52)] }
        return [Color(red: 0.50, green: 0.60, blue: 0.74), Color(red: 0.63, green: 0.52, blue: 0.76), Color(red: 0.72, green: 0.60, blue: 0.68)]
    }

    private func updateAuraColors(from image: UIImage, cardID: String) {
        let imageArea = image.size.width * image.size.height
        let knownArea = auraSourceImageAreaByCardID[cardID] ?? 0
        guard imageArea >= knownArea else { return }
        auraSourceImageAreaByCardID[cardID] = imageArea
        Task.detached(priority: .utility) {
            let extracted = image.bindrAuraColors(maxColors: 3)
            guard !extracted.isEmpty else { return }
            await MainActor.run { self.auraColorsByCardID[cardID] = extracted }
        }
    }

    // MARK: - Styling
}

// MARK: - Supporting types (local copies)

private struct DebugDetailSurface<Content: View>: View {
    let title: String
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(Color.primary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(cornerRadius: 26, interactive: false)
    }
}

private enum DebugPalette {
    static let chartLine = Color(red: 0.12, green: 0.52, blue: 1.0)
    static let success = Color(red: 0.28, green: 0.84, blue: 0.39)
    static let gold = Color(red: 0.99, green: 0.72, blue: 0.22)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.34)
}
