import SwiftUI

struct BrowseAllPokemonView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var rows: [NationalDexPokemon] = []
    @State private var isLoading = true

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading Pokémon…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(rows) { item in
                            NavigationLink(value: item) {
                                VStack(spacing: 6) {
                                    CachedAsyncImage(
                                        url: AppConfiguration.pokemonArtURL(imageFileName: item.imageUrl),
                                        offlineRelativePath: AppConfiguration.pokemonArtRelativePath(imageFileName: item.imageUrl),
                                        offlineBrand: .pokemon
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
                    }
                    .padding()
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
            guard services.brandSettings.enabledBrands.contains(.pokemon) else {
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
