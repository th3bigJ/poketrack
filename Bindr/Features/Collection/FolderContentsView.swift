import SwiftUI
import SwiftData

struct FolderContentsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.presentCard) private var presentCard
    @Environment(\.dismiss) private var dismiss

    let folder: CardFolder

    @State private var query = ""
    @State private var filters = BrowseCardGridFilters()
    @State private var gridOptions = BrowseGridOptions()
    @State private var cardsByCardID: [String: Card] = [:]
    @State private var showShare = false

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
        .task(id: folderSignature) {
            await resolveCards()
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
            CardGridCell(card: card, gridOptions: gridOptions, footnote: item.variantKey != "normal" ? item.variantKey : nil)
        }
        .buttonStyle(CardCellButtonStyle())
        .contextMenu {
            Button("Remove from Folder", role: .destructive) {
                removeItem(item)
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
