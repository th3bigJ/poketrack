import SwiftUI
import SwiftData

struct FolderContentsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.presentCard) private var presentCard
    @Environment(\.dismiss) private var dismiss

    let folder: CardFolder
    @Binding var gridOptions: BrowseGridOptions

    @State private var query = ""
    @State private var filters = BrowseCardGridFilters()
    @State private var cardsByCardID: [String: Card] = [:]
    @State private var setNameByBrandAndCode: [String: String] = [:]
    @State private var showShare = false
    @State private var editingItem: CardFolderItem?

    private var folderSignature: String {
        (folder.items ?? []).map { "\($0.cardID)|\($0.variantKey)" }.joined(separator: "§")
    }

    private var resolvedPairs: [(item: CardFolderItem, card: Card)] {
        (folder.items ?? []).compactMap { item in
            guard let card = cardsByCardID[item.cardID] else { return nil }
            return (item, card)
        }
    }

    private var resolvedCards: [Card] { resolvedPairs.map(\.card) }

    private var orderedCards: [Card] { resolvedPairs.map { $0.card } }

    private var filteredPairs: [(item: CardFolderItem, card: Card)] {
        let pairs = resolvedPairs
        guard filters.hasActiveFieldFilters || !query.isEmpty else { return pairs }
        let allCards = pairs.map { $0.card }
        let filtered = filterBrowseCards(
            allCards,
            query: query,
            filters: filters,
            ownedCardIDs: [],
            brand: services.brandSettings.selectedCatalogBrand,
            sets: services.cardData.sets
        )
        let filteredIDs = Set(filtered.map { $0.masterCardId })
        return pairs.filter { filteredIDs.contains($0.card.masterCardId) }
    }

    private var indexedFilteredPairs: [IndexedFolderItem] {
        filteredPairs.enumerated().map { IndexedFolderItem(index: $0.offset, item: $0.element.item, card: $0.element.card) }
    }

    private var setNameCacheKey: String {
        services.brandSettings.enabledBrands.map(\.rawValue).sorted().joined(separator: ",")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)

                BrowseInlineSearchField(
                    title: "Search \((folder.items ?? []).count) \((folder.items ?? []).count == 1 ? "card" : "cards")",
                    text: $query
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                if indexedFilteredPairs.isEmpty {
                    emptyState
                } else {
                    EagerVGrid(items: indexedFilteredPairs, columns: safeColumnCount(gridOptions.columnCount), spacing: 12) { indexed in
                        folderCell(item: indexed.item, card: indexed.card)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showShare) {
            SocialShareSheet(item: .folder(folder))
                .environment(services)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .sheet(item: $editingItem) { item in
            FolderItemQuantitySheet(item: item)
                .presentationDetents([.height(180)])
                .presentationDragIndicator(.visible)
        }
        .task(id: folderSignature) {
            await resolveCards()
        }
        .task(id: setNameCacheKey) {
            await refreshSetNameCache()
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text(folder.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 64)

            HStack {
                ChromeGlassCircleButton(accessibilityLabel: "Back") { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    ChromeGlassCircleButton(accessibilityLabel: "Share folder") { showShare = true } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    Menu {
                        BrowseGridFiltersMenuContent(
                            brand: services.brandSettings.selectedCatalogBrand,
                            filters: $filters,
                            energyOptions: cardEnergyOptions(resolvedCards),
                            rarityOptions: cardRarityOptions(resolvedCards),
                            trainerTypeOptions: cardTrainerTypeOptions(resolvedCards),
                            gridOptions: $gridOptions
                        )
                    } label: {
                        Image(systemName: filters.hasActiveFieldFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)
                            .modifier(ChromeGlassCircleGlyphModifier())
                    }
                    .buttonStyle(.plain)
                    .menuActionDismissBehavior(.disabled)
                    .menuOrder(.fixed)
                    .menuIndicator(.hidden)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Cells

    @ViewBuilder
    private func folderCell(item: CardFolderItem, card: Card) -> some View {
        Button {
            presentCard(card, orderedCards)
        } label: {
            let qty = ownedQuantity(for: item)
            CardGridCell(
                card: card,
                gridOptions: gridOptions,
                setName: setName(for: card),
                isOwned: qty > 0,
                ownedCountBadge: qty,
                footnote: nil
            )
        }
        .buttonStyle(CardCellButtonStyle())
        .contextMenu {
            Button {
                editingItem = item
            } label: {
                Label("Edit Quantity", systemImage: "pencil")
            }
            Button(role: .destructive) {
                removeItem(item)
            } label: {
                Label("Remove from Folder", systemImage: "folder.badge.minus")
            }
        }
        .accessibilityLabel("\(card.cardName), \(item.variantKey)")
    }

    @ViewBuilder
    private var emptyState: some View {
        if (folder.items ?? []).isEmpty {
            ContentUnavailableView(
                "Empty Folder",
                systemImage: "folder",
                description: Text("Open a card and tap \"Add to Folder\" to add cards here.")
            )
            .frame(minHeight: 280)
        } else {
            ContentUnavailableView.search(text: query)
                .frame(minHeight: 280)
        }
    }

    // MARK: - Data

    private func resolveCards() async {
        for item in folder.items ?? [] {
            guard cardsByCardID[item.cardID] == nil else { continue }
            if let card = await services.cardData.loadCard(masterCardId: item.cardID) {
                cardsByCardID[item.cardID] = card
            }
        }
    }

    private func removeItem(_ item: CardFolderItem) {
        modelContext.delete(item)
        try? modelContext.save()
    }

    private func setName(for card: Card) -> String? {
        let brand = TCGBrand.inferredFromMasterCardId(card.masterCardId)
        return setNameByBrandAndCode[setNameKey(brand: brand, setCode: card.setCode)]
    }

    private func refreshSetNameCache() async {
        var map: [String: String] = [:]
        for brand in services.brandSettings.enabledBrands {
            guard let sets = try? await CatalogStore.shared.fetchAllSets(for: brand) else { continue }
            for set in sets where map[setNameKey(brand: brand, setCode: set.setCode)] == nil {
                map[setNameKey(brand: brand, setCode: set.setCode)] = set.name
            }
        }
        setNameByBrandAndCode = map
    }

    private func ownedQuantity(for folderItem: CardFolderItem) -> Int {
        max(0, folderItem.quantity)
    }

    private func setNameKey(brand: TCGBrand, setCode: String) -> String {
        "\(brand.rawValue)|\(setCode)"
    }

    private func cardEnergyOptions(_ cards: [Card]) -> [String] {
        Set(cards.flatMap { $0.elementTypes ?? [] })
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted()
    }

    private func cardRarityOptions(_ cards: [Card]) -> [String] {
        Set(cards.compactMap { $0.rarity?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter { !$0.isEmpty }
            .sorted()
    }

    private func cardTrainerTypeOptions(_ cards: [Card]) -> [String] {
        Set(cards.compactMap { $0.trainerType?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter { !$0.isEmpty }
            .sorted()
    }

    private func safeColumnCount(_ value: Int) -> Int {
        min(max(value, 1), 4)
    }
}

private struct IndexedFolderItem: Identifiable {
    let index: Int
    let item: CardFolderItem
    let card: Card

    var id: String { "\(item.cardID)|\(item.variantKey)" }
}

private struct FolderItemQuantitySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let item: CardFolderItem
    @State private var quantity: Int = 1

    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Quantity")
                .font(.headline)
            Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                .padding(.horizontal)
            Button("Save") {
                item.quantity = quantity
                try? modelContext.save()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .onAppear { quantity = item.quantity }
    }
}
