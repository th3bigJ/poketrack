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
    var tradeAction: ((Card, Int) -> Void)? = nil
    var tradeActionLabel: String = "Trade"
    var addToDeckAction: ((Card, String, Int) -> Void)? = nil

    @State private var index: Int
    @State private var scrollIndex: Int?
    @State private var hasAppliedInitialScrollPosition = false
    @State private var editingLine: HoldingLine?
    @State private var dispositionLine: HoldingLine?
    @State private var addToCollectionPayload: AddToCollectionSheetPayload?
    @State private var folderContextRequest: CardContextActionRequest?
    @State private var showCardShare = false
    @State private var showTradeListQuantityPicker = false
    @State private var tradeListPickerQuantity = 1
    @State private var wishlistVariantKeys: [String] = ["normal"]
    @State private var isCurrentCardWishlisted = false
    @State private var showWishlistPaywall = false
    @State private var wishlistAlertMessage: String?
    @State private var showWishlistAlert = false
    @State private var auraColorsByCardID: [String: [Color]] = [:]
    @State private var auraSourceImageAreaByCardID: [String: CGFloat] = [:]
    @State private var pushedSet: TCGSet? = nil

    private static let wishlistActiveStarColor = Color(red: 0.98, green: 0.78, blue: 0.18)

    init(cards: [Card], startIndex: Int = 0, tradeAction: ((Card, Int) -> Void)? = nil, tradeActionLabel: String = "Trade", addToDeckAction: ((Card, String, Int) -> Void)? = nil) {
        self.cards = cards
        self.tradeAction = tradeAction
        self.tradeActionLabel = tradeActionLabel
        self.addToDeckAction = addToDeckAction
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
        .sheet(item: $dispositionLine) { line in
            HoldingDispositionSheet(line: line, cardDisplayName: currentCard.cardName)
        }
        .sheet(item: $addToCollectionPayload) { payload in
            AddToCollectionSheet(card: payload.card, variantKey: payload.variantKey, availableVariantKeys: payload.availableVariantKeys)
                .environment(services)
        }
        .sheet(item: $folderContextRequest) { req in
            CardContextActionSheet(request: req)
                .environment(services)
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
        .sheet(item: $pushedSet) { set in
            NavigationStack { SetCardsView(set: set) }
        }
        .alert("Wishlist", isPresented: $showWishlistAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(wishlistAlertMessage ?? "")
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .presentationCornerRadius(20)
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

    @Query private var tradeListItems: [TradeListItem]

    private func cardMetaRow(for card: Card) -> some View {
        VStack(spacing: 12) {
            titleBlock(for: card)
            
            CardActionMenu(
                card: card,
                isOwned: showsCollectionSection(for: card),
                isWishlisted: isCurrentCardWishlisted,
                tradeActionLabel: showsCollectionSection(for: card) ? "Trade List" : (tradeAction != nil ? tradeActionLabel : nil),
                onSaveToCollection: {
                    if let variantKey = singleAvailableVariantKey {
                        addToCollectionVariant(card: card, variantKey: variantKey)
                    } else {
                        addToCollectionVariant(card: card, variantKey: wishlistVariantKeys.first ?? "normal")
                    }
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
                onAddToFolder: {
                    let variantKey = singleAvailableVariantKey ?? wishlistVariantKeys.first ?? "normal"
                    folderContextRequest = CardContextActionRequest(
                        card: card,
                        availableVariantKeys: wishlistVariantKeys,
                        initialVariantKey: variantKey,
                        initialAction: .folder
                    )
                },
                onTradeAction: {
                    if let _ = tradeListItems.first(where: { $0.cardID == card.masterCardId }) {
                        performTradeAction(card: card, quantity: 1)
                    } else {
                        let totalOwned = visibleCollectionItems.reduce(0) { $0 + $1.quantity }
                        if totalOwned > 1 {
                            tradeListPickerQuantity = 1
                            showTradeListQuantityPicker = true
                        } else {
                            performTradeAction(card: card, quantity: 1)
                        }
                    }
                },
                onShareAction: {
                    showCardShare = true
                },
                onEditAction: {
                    if let firstItem = visibleCollectionItems.first,
                       let lot = firstItem.costLots?.first(where: { $0.quantityRemaining > 0 }),
                       let line = lot.sourceLedgerLine {
                        // Re-implement the manual HoldingLine creation logic
                        let direction = LedgerDirection(rawValue: line.direction) ?? .bought
                        let date = line.occurredAt
                        let counterparty = cleaned(line.counterparty)
                        let description = cleaned(line.lineDescription)
                        let unitPrice = line.unitPrice
                        let currencyCode = line.currencyCode
                        let groupKey = [firstItem.itemKind, firstItem.variantKey, cleaned(firstItem.gradingCompany) ?? "", cleaned(firstItem.grade) ?? ""].joined(separator: "|")
                        let lineID = [groupKey, direction.rawValue, counterparty ?? "", description ?? "", currencyCode, (unitPrice.map { String(format: "%.6f", $0) } ?? ""), String(Int(date.timeIntervalSince1970))].joined(separator: "|")
                        
                        editingLine = HoldingLine(
                            id: lineID + "|\(lot.id.uuidString)", item: firstItem, itemKind: firstItem.itemKind,
                            variantKey: firstItem.variantKey, gradingCompany: cleaned(firstItem.gradingCompany), grade: cleaned(firstItem.grade),
                            quantity: lot.quantityRemaining, date: date, direction: direction, unitPrice: unitPrice,
                            currencyCode: currencyCode, counterparty: counterparty, description: description, lotIDs: [lot.id]
                        )
                    }
                },
                onToggleTradeable: {
                    if let firstItem = visibleCollectionItems.first,
                       let lot = firstItem.costLots?.first(where: { $0.quantityRemaining > 0 }),
                       let line = lot.sourceLedgerLine {
                        // Using same manual creation for disposition line
                        let direction = LedgerDirection(rawValue: line.direction) ?? .bought
                        let date = line.occurredAt
                        let counterparty = cleaned(line.counterparty)
                        let description = cleaned(line.lineDescription)
                        let unitPrice = line.unitPrice
                        let currencyCode = line.currencyCode
                        let groupKey = [firstItem.itemKind, firstItem.variantKey, cleaned(firstItem.gradingCompany) ?? "", cleaned(firstItem.grade) ?? ""].joined(separator: "|")
                        let lineID = [groupKey, direction.rawValue, counterparty ?? "", description ?? "", currencyCode, (unitPrice.map { String(format: "%.6f", $0) } ?? ""), String(Int(date.timeIntervalSince1970))].joined(separator: "|")
                        
                        dispositionLine = HoldingLine(
                            id: lineID + "|\(lot.id.uuidString)", item: firstItem, itemKind: firstItem.itemKind,
                            variantKey: firstItem.variantKey, gradingCompany: cleaned(firstItem.gradingCompany), grade: cleaned(firstItem.grade),
                            quantity: lot.quantityRemaining, date: date, direction: direction, unitPrice: unitPrice,
                            currencyCode: currencyCode, counterparty: counterparty, description: description, lotIDs: [lot.id]
                        )
                    }
                },
                onRemoveFromCollection: {
                    removeCurrentCardFromCollection()
                },
                isTradeable: tradeListItems.contains(where: { $0.cardID == currentCard.masterCardId }),
                onAddToDeck: addToDeckAction.map { action in
                    { action(card, wishlistVariantKeys.first ?? "normal", 1) }
                }
            )
            .popover(isPresented: $showTradeListQuantityPicker) {
                let totalOwned = visibleCollectionItems.reduce(0) { $0 + $1.quantity }
                VStack(spacing: 16) {
                    Text("How many to trade?").font(.headline)
                    Stepper("Quantity: \(tradeListPickerQuantity)", value: $tradeListPickerQuantity, in: 1...max(totalOwned, 1))
                    Text("You own \(totalOwned) copies").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button("Cancel") { showTradeListQuantityPicker = false }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                        Button("Add") { showTradeListQuantityPicker = false; performTradeAction(card: card, quantity: tradeListPickerQuantity) }
                            .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .frame(width: 280)
            }
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

    // MARK: - Action buttons

    @ViewBuilder
    private func collectionActionButton(for card: Card) -> some View {
        if let variantKey = singleAvailableVariantKey {
            Button { addToCollectionVariant(card: card, variantKey: variantKey) } label: {
                cardActionBody(title: "Collection", systemImage: "plus.circle.fill", tint: DebugPalette.success)
            }
            .buttonStyle(.plain)
        } else {
            Menu {
                variantSelectionMenuContent(for: card, sectionHeader: "Select Variant", showWishlistCheckmarks: false) { addToCollectionVariant(card: card, variantKey: $0) }
            } label: {
                cardActionBody(title: "Collection", systemImage: "plus.circle.fill", tint: DebugPalette.success)
            }
            .menuStyle(.button).menuIndicator(.hidden)
        }
    }

    @ViewBuilder
    private func wishlistActionButton(for card: Card) -> some View {
        if isCurrentCardWishlisted {
            Button { removeCurrentCardFromWishlist() } label: {
                cardActionBody(title: "Wish List", systemImage: "star.fill", tint: Self.wishlistActiveStarColor)
            }
            .buttonStyle(.plain)
        } else if let variantKey = singleAvailableVariantKey {
            Button { addToWishlist(variantKey: variantKey) } label: {
                cardActionBody(title: "Wish List", systemImage: "star", tint: DebugPalette.gold)
            }
            .buttonStyle(.plain)
        } else {
            Menu {
                variantSelectionMenuContent(for: card, sectionHeader: "Select Variant", showWishlistCheckmarks: true, onSelect: addToWishlist)
            } label: {
                cardActionBody(title: "Wish List", systemImage: "star", tint: DebugPalette.gold)
            }
            .menuStyle(.button).menuIndicator(.hidden)
        }
    }

    @ViewBuilder
    private func folderActionButton(for card: Card) -> some View {
        if let variantKey = singleAvailableVariantKey {
            Button {
                folderContextRequest = CardContextActionRequest(
                    card: card,
                    availableVariantKeys: wishlistVariantKeys,
                    initialVariantKey: variantKey,
                    initialAction: .folder
                )
            } label: {
                cardActionBody(title: "Add to Folder", systemImage: "folder.badge.plus", tint: Color(red: 0.18, green: 0.72, blue: 0.88))
            }
            .buttonStyle(.plain)
        } else {
            Menu {
                variantSelectionMenuContent(for: card, sectionHeader: "Select Variant", showWishlistCheckmarks: false) { key in
                    folderContextRequest = CardContextActionRequest(
                        card: card,
                        availableVariantKeys: wishlistVariantKeys,
                        initialVariantKey: key,
                        initialAction: .folder
                    )
                }
            } label: {
                cardActionBody(title: "Add to Folder", systemImage: "folder.badge.plus", tint: Color(red: 0.18, green: 0.72, blue: 0.88))
            }
            .menuStyle(.button).menuIndicator(.hidden)
        }
    }

    private var shareActionButton: some View {
        Button { showCardShare = true } label: {
            cardActionBody(title: "Share", systemImage: "square.and.arrow.up", tint: Color(red: 0.36, green: 0.61, blue: 0.97))
        }
        .buttonStyle(.plain)
    }

    private func removeCurrentCardFromCollection() {
        for item in collectionItems {
            modelContext.delete(item)
        }
        try? modelContext.save()
        Haptics.success()
    }

    private func performTradeAction(card: Card, quantity: Int) {
        if let tradeAction {
            tradeAction(card, quantity)
        } else {
            // Default toggle logic for collection/browse management
            if let existing = tradeListItems.first(where: { $0.cardID == card.masterCardId }) {
                modelContext.delete(existing)
                Haptics.lightImpact()
            } else {
                let newItem = TradeListItem(cardID: card.masterCardId, quantity: quantity)
                modelContext.insert(newItem)
                Haptics.success()
            }
            try? modelContext.save()
            services.socialCardLibrary.scheduleAutoSyncTradeList(items: tradeListItems)
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

            HStack(spacing: 6) {
                holdingActionButton(systemImage: "pencil", title: "Edit acquisition", tint: .primary, usesNeutralFill: true) {
                    editingLine = line
                }

                holdingActionButton(systemImage: "tag.fill", title: "Mark disposition", tint: DebugPalette.chartLine) {
                    dispositionLine = line
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(sectionBorder.opacity(0.7), lineWidth: 1)
                )
        )
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
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(usesNeutralFill
                            ? (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.055))
                            : tint.opacity(0.12))
                )
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
                                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(sectionInsetBackground))
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
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(sectionInsetBackground))
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
                                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(sectionInsetBackground))
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
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(.primary)
            Text(body).font(.subheadline).foregroundStyle(.secondary)
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

    private var sectionInsetBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)
    }
    private var sectionBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }
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

private extension UIImage {
    func bindrAuraColors(maxColors: Int) -> [Color] {
        guard maxColors > 0, let cgImage else { return [] }
        let sampleWidth = 44, sampleHeight = 62, bytesPerPixel = 4
        let bytesPerRow = sampleWidth * bytesPerPixel
        var raw = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &raw, width: sampleWidth, height: sampleHeight,
                                     bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [] }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
        struct AuraBin: Hashable { let r, g, b: Int }
        var histogram: [AuraBin: Double] = [:]
        let step = 32.0
        for y in 0..<sampleHeight {
            for x in 0..<sampleWidth {
                let i = y * bytesPerRow + x * bytesPerPixel
                let r = Double(raw[i]), g = Double(raw[i+1]), b = Double(raw[i+2]), a = Double(raw[i+3]) / 255.0
                guard a > 0.6 else { continue }
                let maxC = max(r, g, b) / 255.0, minC = min(r, g, b) / 255.0
                let delta = maxC - minC
                let saturation = maxC == 0 ? 0.0 : delta / maxC
                let brightness = maxC
                guard saturation >= 0.22, brightness >= 0.18, brightness <= 0.94 else { continue }
                let bin = AuraBin(r: Int(floor(r/step)), g: Int(floor(g/step)), b: Int(floor(b/step)))
                histogram[bin, default: 0] += 0.3 + saturation * 1.6 + brightness * 0.2
            }
        }
        let sortedBins = histogram.sorted { $0.value > $1.value }.map(\.key)
        guard !sortedBins.isEmpty else { return [] }
        var selected: [SIMD3<Double>] = []
        for bin in sortedBins {
            let c = SIMD3<Double>((Double(bin.r)+0.5)*step/255, (Double(bin.g)+0.5)*step/255, (Double(bin.b)+0.5)*step/255)
            if selected.allSatisfy({ existing in let d = c - existing; return sqrt(d.x*d.x+d.y*d.y+d.z*d.z) > 0.22 }) {
                selected.append(c)
            }
            if selected.count == maxColors { break }
        }
        if selected.isEmpty, let f = sortedBins.first {
            selected = [SIMD3<Double>((Double(f.r)+0.5)*step/255, (Double(f.g)+0.5)*step/255, (Double(f.b)+0.5)*step/255)]
        }
        if selected.count == 1, let f = selected.first { selected += [f*0.86, f*0.72] }
        else if selected.count == 2 { selected.append(selected[1]*0.7 + selected[0]*0.3) }
        return selected.prefix(maxColors).map { Color(red: $0.x, green: $0.y, blue: $0.z) }
    }
}
