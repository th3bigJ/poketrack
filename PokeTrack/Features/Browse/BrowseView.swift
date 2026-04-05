import SwiftUI

struct BrowseView: View {
    @Environment(AppServices.self) private var services
    @State private var query = ""
    @State private var searchResults: [Card] = []
    @State private var isSearching = false

    var body: some View {
        List {
            Section {
                TextField("Search all cards", text: $query)
                    .textInputAutocapitalization(.never)
                Button("Search") {
                    Task { await runSearch() }
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if isSearching { ProgressView() }
            }

            if !searchResults.isEmpty {
                Section("Results") {
                    ForEach(searchResults) { card in
                        NavigationLink {
                            CardBrowseDetailView(card: card)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.cardName)
                                Text("\(card.setCode) · \(card.cardNumber)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Sets") {
                if services.cardData.isLoading {
                    ProgressView("Loading sets…")
                } else if services.cardData.sets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No sets loaded.")
                            .foregroundStyle(.secondary)
                        if let err = services.cardData.lastError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        Text("Configure POKETRACK_R2_BASE_URL. Catalog JSON uses POKETRACK_R2_CATALOG_PREFIX (default data); pricing uses POKETRACK_R2_PRICING_PREFIX (default root). See Account → About for resolved URLs.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    ForEach(services.cardData.sets) { set in
                        NavigationLink {
                            SetCardsView(set: set)
                        } label: {
                            Text(set.name)
                        }
                    }
                }
            }
        }
        .navigationTitle("Cards")
        .refreshable {
            await services.cardData.loadSets()
        }
    }

    private func runSearch() async {
        isSearching = true
        defer { isSearching = false }
        searchResults = await services.cardData.search(query: query)
    }
}

struct SetCardsView: View {
    @Environment(AppServices.self) private var services
    let set: TCGSet

    @State private var cards: [Card] = []
    @State private var isLoading = true

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().padding()
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(cards) { card in
                        NavigationLink {
                            CardBrowseDetailView(card: card)
                        } label: {
                            VStack(spacing: 6) {
                                AsyncImage(url: AppConfiguration.imageURL(relativePath: card.imageLowSrc)) { p in
                                    p.resizable().scaledToFit()
                                } placeholder: {
                                    Color.gray.opacity(0.12)
                                }
                                .frame(height: 140)
                                Text(card.cardName)
                                    .font(.caption2)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
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
        .navigationTitle(set.name)
        .task {
            isLoading = true
            cards = await services.cardData.loadCards(forSetCode: set.setCode)
            isLoading = false
        }
    }
}
