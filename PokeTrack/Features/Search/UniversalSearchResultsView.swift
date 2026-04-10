import SwiftUI

/// In-app results for the universal search field (sets + cards; sealed placeholder until indexed).
struct UniversalSearchResultsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.presentCard) private var presentCard
    let query: String

    @State private var cards: [Card] = []
    @State private var isSearching = false

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchingSets: [TCGSet] {
        services.cardData.searchSets(matching: trimmed)
    }

    private var matchingPokemon: [NationalDexPokemon] {
        services.cardData.searchPokemon(matching: trimmed)
    }

    private let cardColumns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        Group {
            if trimmed.isEmpty {
                ContentUnavailableView(
                    "Search",
                    systemImage: "magnifyingglass",
                    description: Text("Type to find cards, sets, and Pokémon, or open Browse sets / Browse Pokémon above.")
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
                                    NavigationLink(value: SearchNavRoot.set(set)) {
                                        HStack(spacing: 12) {
                                            SetLogoAsyncImage(logoSrc: set.logoSrc, height: 36)
                                                .frame(width: 72, height: 36)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(set.name)
                                                    .foregroundStyle(.primary)
                                                Text(set.setCode.uppercased())
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
                                            CachedAsyncImage(url: AppConfiguration.pokemonArtURL(imageFileName: mon.imageUrl)) { img in
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

                        // MARK: Cards
                        sectionHeader("Cards")
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
                                ForEach(cards) { card in
                                    Button { presentCard(card, cards) } label: {
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
                cards = []
                isSearching = false
                return
            }
            if services.cardData.nationalDexPokemon.isEmpty {
                await services.cardData.loadNationalDexPokemon()
            }
            isSearching = true
            defer { isSearching = false }
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            cards = await services.cardData.search(query: trimmed)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }
}
