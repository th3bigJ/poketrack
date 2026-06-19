import SwiftData
import SwiftUI

/// In-app results for the universal search field (sets + cards; sealed placeholder until indexed).
struct UniversalSearchResultsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentCard) private var presentCard
    @Query(sort: \CollectionItem.dateAcquired, order: .reverse) private var collectionItems: [CollectionItem]
    let query: String
    let selectedBrand: TCGBrand
    let sourceScope: SearchSourceScope
    let idleContent: AnyView
    let onCommitSearch: () -> Void

    @State private var matchingSets: [SearchSetMatch] = []
    @State private var cards: [Card] = []
    @State private var isSearching = false
    @State private var isLoadingAllCards = false
    @State private var hasMoreCardResults = false
    @State private var showAllCards = false
    @State private var debouncedQuery = ""
    @State private var lastSearchTaskKey = ""
    @State private var lastSearchCards: [Card] = []
    @State private var lastSearchSets: [SearchSetMatch] = []

    private let previewCardLimit = 9

    private struct SearchSetMatch: Identifiable {
        let set: TCGSet
        let brand: TCGBrand

        var id: String { "\(brand.rawValue)|\(set.id)" }
    }

    private var liveTrimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmed: String {
        debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isAllCardsScope: Bool {
        sourceScope == .allCards
    }

    private var showPokemonDexSection: Bool {
        isAllCardsScope && selectedBrand == .pokemon
    }

    private var matchingPokemon: [NationalDexPokemon] {
        guard showPokemonDexSection else { return [] }
        return services.cardData.searchPokemon(matching: trimmed)
    }

    private var emptyStateDescription: String {
        if sourceScope == .myCollection {
            return "Type to search your collection."
        }
        if showPokemonDexSection {
            return "Type to find cards, sets, and Pokémon."
        }
        return "Type to find cards and sets."
    }

    private let cardColumns = [GridItem(.adaptive(minimum: 110), spacing: 12)]
    private var displayedCards: [Card] { showAllCards ? cards : Array(cards.prefix(previewCardLimit)) }

    var body: some View {
        Group {
            if trimmed.isEmpty {
                idleContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
                        if sourceScope == .allCards && !matchingSets.isEmpty {
                            sectionHeader("Sets")
                            VStack(spacing: 0) {
                                ForEach(matchingSets) { set in
                                    NavigationLink(value: SearchNavRoot.set(set.set, brand: set.brand)) {
                                        HStack(spacing: 12) {
                                            SetLogoAsyncImage(logoSrc: set.set.logoSrc, height: 36, brand: set.brand)
                                                .frame(width: 72, height: 36)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(set.set.name)
                                                    .foregroundStyle(.primary)
                                                Text(set.brand.displayTitle + " · " + set.set.setCode.uppercased())
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer(minLength: 0)
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 16)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .simultaneousGesture(TapGesture().onEnded(onCommitSearch))
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }

                        // MARK: Pokémon
                        if sourceScope == .allCards && !matchingPokemon.isEmpty {
                            sectionHeader("Pokémon")
                            VStack(spacing: 0) {
                                ForEach(matchingPokemon) { mon in
                                    NavigationLink(
                                        value: SearchNavRoot.dex(
                                            dexId: mon.nationalDexNumber,
                                            displayName: mon.displayName,
                                            brand: selectedBrand
                                        )
                                    ) {
                                        HStack(spacing: 12) {
                                            CachedAsyncImage(
                                                url: AppConfiguration.pokemonArtURL(imageFileName: mon.imageUrl)
                                            ) { img in
                                                img.resizable().scaledToFit()
                                            } placeholder: {
                                                Color.gray.opacity(0.12)
                                            }
                                            .frame(width: 44, height: 44)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(mon.displayName)
                                                    .foregroundStyle(.primary)
                                                Text("#\(mon.nationalDexNumber)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer(minLength: 0)
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 16)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .simultaneousGesture(TapGesture().onEnded(onCommitSearch))
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }

                        // MARK: Cards
                        cardsSectionHeader
                        if isSearching && cards.isEmpty {
                            ProgressView("Searching…")
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else if cards.isEmpty {
                            Text("No matches yet.")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                                .padding(.horizontal, 16)
                        } else {
                            LazyVGrid(columns: cardColumns, spacing: 12) {
                                ForEach(displayedCards) { card in
                                    Button {
                                        onCommitSearch()
                                        SearchHistoryStore.recordViewedCard(card.masterCardId)
                                        presentCard(card, displayedCards)
                                    } label: {
                                        CardGridCell(card: card, services: services, colorScheme: colorScheme)
                                    }
                                    .buttonStyle(CardCellButtonStyle())
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .background(Color.clear)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: query) {
            if liveTrimmed.isEmpty {
                debouncedQuery = ""
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            debouncedQuery = query
        }
        .task(id: searchTaskKey) {
            guard !trimmed.isEmpty else {
                matchingSets = []
                cards = []
                isSearching = false
                isLoadingAllCards = false
                hasMoreCardResults = false
                showAllCards = false
                lastSearchTaskKey = ""
                lastSearchCards = []
                lastSearchSets = []
                return
            }
            if lastSearchTaskKey == searchTaskKey {
                matchingSets = lastSearchSets
                cards = Array(lastSearchCards.prefix(previewCardLimit))
                hasMoreCardResults = lastSearchCards.count > previewCardLimit
                return
            }
            isLoadingAllCards = false
            hasMoreCardResults = false
            showAllCards = false
            try? await Task.sleep(nanoseconds: 225_000_000)
            guard !Task.isCancelled else { return }
            if showPokemonDexSection, services.cardData.nationalDexPokemon.isEmpty {
                await services.cardData.loadNationalDexPokemon()
            }
            isSearching = true
            defer { isSearching = false }

            if sourceScope == .allCards {
                let brandSets = await services.cardData.catalogSets(for: selectedBrand)
                let q = trimmed.lowercased()
                let matches = brandSets.filter { set in
                    set.name.lowercased().contains(q)
                        || set.setCode.lowercased().contains(q)
                        || (set.seriesName?.lowercased().contains(q) == true)
                }
                matchingSets = matches.map { SearchSetMatch(set: $0, brand: selectedBrand) }

                let allBrandCards = await services.cardData.search(query: trimmed, catalogBrand: selectedBrand)
                cards = Array(allBrandCards.prefix(previewCardLimit))
                hasMoreCardResults = allBrandCards.count > previewCardLimit
                lastSearchTaskKey = searchTaskKey
                lastSearchSets = matchingSets
                lastSearchCards = allBrandCards
            } else {
                matchingSets = []
                let allCollectionCards = await collectionSearchResults(query: trimmed, brand: selectedBrand)
                cards = Array(allCollectionCards.prefix(previewCardLimit))
                hasMoreCardResults = allCollectionCards.count > previewCardLimit
                lastSearchTaskKey = searchTaskKey
                lastSearchSets = []
                lastSearchCards = allCollectionCards
            }
        }
    }

    @MainActor
    private func loadAllCardResults(for query: String) async {
        guard !query.isEmpty else { return }
        guard !isLoadingAllCards else { return }

        isLoadingAllCards = true
        defer { isLoadingAllCards = false }

        let allCards: [Card]
        if sourceScope == .allCards {
            allCards = await services.cardData.search(query: query, catalogBrand: selectedBrand)
        } else {
            allCards = await collectionSearchResults(query: query, brand: selectedBrand)
        }
        guard self.trimmed == query else { return }
        cards = allCards
        showAllCards = true
        hasMoreCardResults = allCards.count > previewCardLimit
        lastSearchTaskKey = searchTaskKey
        lastSearchCards = allCards
    }

    private var searchTaskKey: String {
        "\(trimmed)|\(selectedBrand.rawValue)|\(sourceScope.rawValue)"
    }

    private func collectionSearchResults(query: String, brand: TCGBrand) async -> [Card] {
        let ownedIDs = Set(
            collectionItems
                .filter { TCGBrand.inferredFromMasterCardId($0.cardID) == brand }
                .map(\.cardID)
        )
        guard !ownedIDs.isEmpty else { return [] }

        let brandCards = await services.cardData.search(query: query, catalogBrand: brand)
        return brandCards.filter { ownedIDs.contains($0.masterCardId) }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }

    private var cardsSectionHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Cards")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            if hasMoreCardResults && !showAllCards {
                Button {
                    Task { await loadAllCardResults(for: trimmed) }
                } label: {
                    if isLoadingAllCards {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("View all")
                            .font(.footnote.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func searchListRow(title: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}
