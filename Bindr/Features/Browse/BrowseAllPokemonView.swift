import SwiftUI

struct BrowseAllPokemonView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var rows: [NationalDexPokemon] = []
    @State private var isLoading = true
    @State private var query = ""

    private let columnCount = 3

    private var filteredRows: [NationalDexPokemon] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rows }
        let q = trimmed.lowercased()
        return rows.filter { item in
            item.name.lowercased().contains(q)
                || item.displayName.lowercased().contains(q)
                || String(item.nationalDexNumber).contains(q)
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading Pokémon…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if services.brandSettings.selectedCatalogBrand != .pokemon {
                ContentUnavailableView(
                    "Pokémon not active",
                    systemImage: "hare",
                    description: Text("Switch the active game to Pokémon from More to browse the National Dex.")
                )
            } else if !services.brandSettings.enabledBrands.contains(.pokemon) {
                ContentUnavailableView(
                    "Pokémon catalog off",
                    systemImage: "hare",
                    description: Text("Turn on Pokémon under Account → Card catalog to browse by National Dex.")
                )
            } else if rows.isEmpty {
                ContentUnavailableView(
                    "No Pokédex list",
                    systemImage: "hare",
                    description: Text("Add pokemon.json next to sets.json on your CDN.")
                )
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        BrowseInlineSearchField(title: "Search Pokémon", text: $query)
                            .padding(.horizontal)
                            .padding(.top)
                        if filteredRows.isEmpty {
                            ContentUnavailableView(
                                "No matching Pokémon",
                                systemImage: "magnifyingglass",
                                description: Text("Try a different name or National Dex number.")
                            )
                            .padding(.horizontal)
                            .padding(.bottom)
                        } else {
                            EagerVGrid(items: filteredRows, columns: columnCount, spacing: 12) { item in
                                NavigationLink(value: item) {
                                    VStack(spacing: 6) {
                                        CachedAsyncImage(
                                            url: AppConfiguration.pokemonArtURL(imageFileName: item.imageUrl)
                                        ) { img in
                                            img.resizable().scaledToFit()
                                        } placeholder: {
                                            Color.gray.opacity(0.12)
                                        }
                                        .frame(height: 140)
                                        Text(item.displayName)
                                            .font(.caption2)
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                        Text("#\(item.nationalDexNumber)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(6)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.08)))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal)
                            .padding(.bottom)
                        }
                    }
                }
            }
        }
        .navigationDestination(for: NationalDexPokemon.self) { mon in
            DexCardsView(dexId: mon.nationalDexNumber, displayName: mon.displayName)
        }
        .navigationTitle("Browse Pokémon")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            isLoading = true
            defer { isLoading = false }
            guard services.brandSettings.selectedCatalogBrand == .pokemon,
                  services.brandSettings.enabledBrands.contains(.pokemon) else {
                rows = []
                return
            }
            if services.cardData.nationalDexPokemon.isEmpty {
                await services.cardData.loadNationalDexPokemon()
            }
            rows = services.cardData.nationalDexPokemonSorted()
        }
    }
}

