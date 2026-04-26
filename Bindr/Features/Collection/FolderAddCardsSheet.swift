import SwiftUI
import SwiftData

struct FolderAddCardsSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let folder: CardFolder

    @Query(sort: \CollectionItem.dateAcquired, order: .reverse) private var collectionItems: [CollectionItem]

    private enum Source: String, CaseIterable, Identifiable {
        case all        = "All Cards"
        case collection = "Collection"
        var id: String { rawValue }
    }

    private static let initialBatch = 36
    private static let pageSize     = 24

    @State private var source: Source = .all
    @State private var query = ""
    @State private var debouncedQuery = ""
    @State private var allCardRefs: [CardRef] = []
    @State private var displayedCards: [Card] = []
    @State private var searchResults: [Card] = []
    @State private var nextRefIndex = 0
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var isSearching = false
    @State private var addedKeys: Set<String> = []
    @State private var gridOptions = BrowseGridOptions(showCardName: true, showSetName: true, showSetID: false,
                                                       showPricing: false, showOwned: true, columnCount: 3)

    private var brand: TCGBrand { services.brandSettings.selectedCatalogBrand }

    private var ownedIDs: Set<String> { Set(collectionItems.map(\.cardID)) }

    private var inFolderKeys: Set<String> {
        Set((folder.items ?? []).map { "\($0.cardID)|\($0.variantKey)" })
    }

    private var debouncedTrimmed: String { debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isQueryActive: Bool { !debouncedTrimmed.isEmpty }

    private var allCardsBase: [Card] { isQueryActive ? searchResults : displayedCards }

    private var collectionCards: [Card] {
        let q = debouncedTrimmed.lowercased()
        return collectionItems.compactMap { item in
            guard TCGBrand.inferredFromMasterCardId(item.cardID) == brand else { return nil }
            // Use already-resolved cards if available, else skip until resolved
            return nil
        }
    }

    // Collection entries resolved via pre-loaded card data
    @State private var resolvedByID: [String: Card] = [:]

    private var collectionEntries: [Card] {
        let q = debouncedTrimmed.lowercased()
        return collectionItems.compactMap { item in
            guard TCGBrand.inferredFromMasterCardId(item.cardID) == brand else { return nil }
            guard let card = resolvedByID[item.cardID] else { return nil }
            if !q.isEmpty {
                guard card.cardName.lowercased().contains(q)
                   || card.cardNumber.lowercased().contains(q) else { return nil }
            }
            return card
        }
    }

    private var visibleCards: [Card] {
        switch source {
        case .all:        return allCardsBase
        case .collection: return collectionEntries
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: min(max(gridOptions.columnCount, 1), 4))
    }

    private var preloadTriggerID: String? { visibleCards.suffix(4).first?.masterCardId }

    private var searchTaskKey: String { "\(source.rawValue)|\(debouncedTrimmed)" }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && visibleCards.isEmpty && !isSearching {
                    ProgressView("Loading cards…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            pickerHeader

                            if isSearching && visibleCards.isEmpty {
                                ProgressView("Searching…")
                                    .frame(maxWidth: .infinity, minHeight: 220).padding(.top, 24)
                            } else if visibleCards.isEmpty {
                                ContentUnavailableView(
                                    debouncedTrimmed.isEmpty ? "No cards found" : "No matching cards",
                                    systemImage: debouncedTrimmed.isEmpty ? "rectangle.stack" : "magnifyingglass"
                                )
                                .frame(maxWidth: .infinity, minHeight: 280).padding(.top, 24)
                            } else {
                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(visibleCards, id: \.masterCardId) { card in
                                        let key = "\(card.masterCardId)|normal"
                                        let alreadyIn = inFolderKeys.contains(key) || addedKeys.contains(key)
                                        Button { toggleCard(card) } label: {
                                            folderPickerCell(card: card, alreadyIn: alreadyIn)
                                        }
                                        .buttonStyle(CardCellButtonStyle())
                                        .onAppear {
                                            guard source == .all, !isQueryActive else { return }
                                            guard card.masterCardId == preloadTriggerID else { return }
                                            Task { await loadNextPage() }
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                            }

                            if isLoadingMore {
                                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 16)
                            }
                            Spacer(minLength: 0).frame(height: 40)
                        }
                    }
                }
            }
            .navigationTitle("Add Cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.primary)
                }
            }
            .task { await loadAllCards() }
            .task(id: collectionItems.map(\.cardID).joined()) {
                await resolveCollectionCards()
            }
            .task(id: query) {
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { debouncedQuery = ""; return }
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard !Task.isCancelled else { return }
                debouncedQuery = query
            }
            .task(id: searchTaskKey) { await handleQueryChanged() }
        }
        .presentationDetents([.large])
    }

    // MARK: - Header

    private var pickerHeader: some View {
        VStack(spacing: 12) {
            SlidingSegmentedPicker(selection: $source, items: Source.allCases, title: { $0.rawValue })

            BrowseInlineSearchField(
                title: source == .all ? "Search all \(brand.displayTitle) cards" : "Search your collection",
                text: $query
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Cell

    private func folderPickerCell(card: Card, alreadyIn: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            CardGridCell(card: card, gridOptions: gridOptions)

            if alreadyIn {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white, services.theme.accentColor)
                    .background(Circle().fill(Color.white))
                    .padding(6)
            } else if ownedIDs.contains(card.masterCardId) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white, .green)
                    .background(Circle().fill(Color.white))
                    .padding(6)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(uiColor: .secondarySystemBackground)))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    alreadyIn ? services.theme.accentColor : Color.primary.opacity(0.06),
                    lineWidth: alreadyIn ? 2 : 1
                )
        }
        .opacity(alreadyIn ? 0.55 : 1)
    }

    // MARK: - Actions

    private func toggleCard(_ card: Card) {
        let key = "\(card.masterCardId)|normal"
        let isCurrentlyIn = inFolderKeys.contains(key) || addedKeys.contains(key)
        if isCurrentlyIn {
            addedKeys.remove(key)
            if let item = (folder.items ?? []).first(where: { $0.cardID == card.masterCardId && $0.variantKey == "normal" }) {
                modelContext.delete(item)
                try? modelContext.save()
            }
        } else {
            let item = CardFolderItem(cardID: card.masterCardId, variantKey: "normal")
            item.folder = folder
            modelContext.insert(item)
            try? modelContext.save()
            addedKeys.insert(key)
        }
    }

    // MARK: - Data loading

    private func loadAllCards() async {
        isLoading = true
        do {
            try CatalogStore.shared.open()
            let refs = try CatalogStore.shared.fetchAllCardRefs(for: brand)
            await MainActor.run {
                allCardRefs = refs
                displayedCards = []
                nextRefIndex = 0
            }
            await loadNextPage(reset: true)
        } catch {
            await MainActor.run { isLoading = false }
        }
    }

    private func loadNextPage(reset: Bool = false) async {
        guard !isQueryActive else { return }
        guard !isLoadingMore else { return }
        guard reset || nextRefIndex < allCardRefs.count else {
            isLoading = false
            return
        }
        isLoadingMore = !reset
        let start = reset ? 0 : nextRefIndex
        let end = min(start + (reset ? Self.initialBatch : Self.pageSize), allCardRefs.count)
        let batch = Array(allCardRefs[start..<end])
        let cards = await loadCardsInOrder(batch)
        await MainActor.run {
            if reset { displayedCards = cards } else { displayedCards.append(contentsOf: cards) }
            for card in cards { resolvedByID[card.masterCardId] = card }
            nextRefIndex = end
            isLoading = false
            isLoadingMore = false
        }
    }

    private func loadCardsInOrder(_ refs: [CardRef]) async -> [Card] {
        guard !refs.isEmpty else { return [] }
        var bySet: [String: Set<String>] = [:]
        for ref in refs { bySet[ref.setCode, default: []].insert(ref.masterCardId) }
        var cardByKey: [String: Card] = [:]
        for (setCode, ids) in bySet {
            let loaded = await services.cardData.loadCards(forSetCode: setCode, catalogBrand: brand)
            for card in loaded where ids.contains(card.masterCardId) {
                cardByKey["\(card.setCode)|\(card.masterCardId)"] = card
            }
        }
        return refs.compactMap { cardByKey["\($0.setCode)|\($0.masterCardId)"] }
    }

    private func handleQueryChanged() async {
        guard source == .all else { return }
        let trimmed = debouncedTrimmed
        if trimmed.isEmpty {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        let results = await services.cardData.search(query: trimmed, catalogBrand: brand)
        await MainActor.run {
            searchResults = results
            isSearching = false
            isLoading = false
        }
    }

    private func resolveCollectionCards() async {
        for item in collectionItems where TCGBrand.inferredFromMasterCardId(item.cardID) == brand {
            guard resolvedByID[item.cardID] == nil else { continue }
            if let card = await services.cardData.loadCard(masterCardId: item.cardID) {
                resolvedByID[card.masterCardId] = card
            }
        }
    }
}
