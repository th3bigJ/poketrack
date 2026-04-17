import SwiftUI

/// In-app results for the universal search field (sets + cards; sealed placeholder until indexed).
struct UniversalSearchResultsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.presentCard) private var presentCard
    let query: String

    @State private var matchingSets: [SearchSetMatch] = []
    @State private var cards: [Card] = []
    @State private var isSearching = false
    @State private var isLoadingAllCards = false
    @State private var hasMoreCardResults = false
    @State private var showAllCards = false

    private let previewCardLimit = 9

    private struct SearchSetMatch: Identifiable {
        let set: TCGSet
        let brand: TCGBrand

        var id: String { "\(brand.rawValue)|\(set.id)" }
    }

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var pokemonCatalogEnabled: Bool {
        services.brandSettings.enabledBrands.contains(.pokemon)
    }

    private var showPokemonDexSection: Bool {
        pokemonCatalogEnabled
    }

    private var matchingPokemon: [NationalDexPokemon] {
        guard showPokemonDexSection else { return [] }
        return services.cardData.searchPokemon(matching: trimmed)
    }

    private var showOnePieceBrowseSections: Bool {
        services.brandSettings.enabledBrands.contains(.onePiece)
    }

    private var matchingOnePieceCharacters: [String] {
        guard showOnePieceBrowseSections else { return [] }
        return services.cardData.searchOnePieceCharacterNames(matching: trimmed)
    }

    private var matchingOnePieceSubtypes: [String] {
        guard showOnePieceBrowseSections else { return [] }
        return services.cardData.searchOnePieceCharacterSubtypes(matching: trimmed)
    }

    private var emptyStateDescription: String {
        if showPokemonDexSection {
            return "Type to find cards, sets, and Pokémon."
        }
        if showOnePieceBrowseSections {
            return "Type to find cards, sets, characters, and subtypes."
        }
        return "Type to find cards and sets."
    }

    private let cardColumns = [GridItem(.adaptive(minimum: 110), spacing: 12)]
    private var displayedCards: [Card] { showAllCards ? cards : Array(cards.prefix(previewCardLimit)) }

    var body: some View {
        Group {
            if trimmed.isEmpty {
                ContentUnavailableView(
                    "Search",
                    systemImage: "magnifyingglass",
                    description: Text(emptyStateDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
                        // MARK: Sets
                        if !matchingSets.isEmpty {
                            sectionHeader("Sets")
                            VStack(spacing: 0) {
                                ForEach(matchingSets) { set in
                                    NavigationLink(value: SearchNavRoot.set(set.set)) {
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
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }

                        // MARK: Pokémon
                        if !matchingPokemon.isEmpty {
                            sectionHeader("Pokémon")
                            VStack(spacing: 0) {
                                ForEach(matchingPokemon) { mon in
                                    NavigationLink(
                                        value: SearchNavRoot.dex(
                                            dexId: mon.nationalDexNumber,
                                            displayName: mon.displayName
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
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }

                        if !matchingOnePieceCharacters.isEmpty {
                            sectionHeader("Characters")
                            VStack(spacing: 0) {
                                ForEach(matchingOnePieceCharacters, id: \.self) { name in
                                    NavigationLink(value: SearchNavRoot.onePieceCharacter(name: name)) {
                                        searchListRow(title: name)
                                    }
                                    .buttonStyle(.plain)
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }

                        if !matchingOnePieceSubtypes.isEmpty {
                            sectionHeader("Subtypes")
                            VStack(spacing: 0) {
                                ForEach(matchingOnePieceSubtypes, id: \.self) { subtype in
                                    NavigationLink(value: SearchNavRoot.onePieceSubtype(name: subtype)) {
                                        searchListRow(title: subtype)
                                    }
                                    .buttonStyle(.plain)
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
                                    Button { presentCard(card, displayedCards) } label: {
                                        CardGridCell(card: card)
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
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: trimmed) {
            guard !trimmed.isEmpty else {
                matchingSets = []
                cards = []
                isSearching = false
                isLoadingAllCards = false
                hasMoreCardResults = false
                showAllCards = false
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
            if showOnePieceBrowseSections,
               services.cardData.onePieceCharacterNames.isEmpty || services.cardData.onePieceCharacterSubtypes.isEmpty {
                await services.cardData.loadOnePieceBrowseMetadata()
            }
            isSearching = true
            defer { isSearching = false }
            let enabledBrands = services.brandSettings.enabledBrands.sorted { $0.menuOrder < $1.menuOrder }

            var allSetMatches: [SearchSetMatch] = []
            for brand in enabledBrands {
                let brandSets = await services.cardData.catalogSets(for: brand)
                let q = trimmed.lowercased()
                let matches = brandSets.filter { set in
                    set.name.lowercased().contains(q)
                        || set.setCode.lowercased().contains(q)
                        || (set.seriesName?.lowercased().contains(q) == true)
                }
                allSetMatches.append(contentsOf: matches.map { SearchSetMatch(set: $0, brand: brand) })
            }
            matchingSets = allSetMatches

            var previewCards: [Card] = []
            var totalMatchedCardCount = 0
            for brand in enabledBrands {
                let brandCards = await services.cardData.search(query: trimmed, catalogBrand: brand)
                totalMatchedCardCount += brandCards.count
                if previewCards.count < previewCardLimit {
                    let remaining = previewCardLimit - previewCards.count
                    previewCards.append(contentsOf: brandCards.prefix(remaining))
                }
                if totalMatchedCardCount > previewCardLimit {
                    break
                }
            }
            cards = previewCards
            hasMoreCardResults = totalMatchedCardCount > previewCardLimit
        }
    }

    @MainActor
    private func loadAllCardResults(for query: String) async {
        guard !query.isEmpty else { return }
        guard !isLoadingAllCards else { return }

        isLoadingAllCards = true
        defer { isLoadingAllCards = false }

        let enabledBrands = services.brandSettings.enabledBrands.sorted { $0.menuOrder < $1.menuOrder }
        var allCards: [Card] = []
        for brand in enabledBrands {
            let brandCards = await services.cardData.search(query: query, catalogBrand: brand)
            allCards.append(contentsOf: brandCards)
        }
        guard self.trimmed == query else { return }
        cards = allCards
        showAllCards = true
        hasMoreCardResults = allCards.count > previewCardLimit
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
