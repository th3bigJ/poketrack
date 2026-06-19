import SwiftUI

enum SearchIdleCategory: String, CaseIterable, Identifiable {
    case cards
    case sets
    case pokemon
    case sealed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cards: return "Cards"
        case .sets: return "Sets"
        case .pokemon: return "Pokémon"
        case .sealed: return "Sealed"
        }
    }

    var subtitle: String {
        switch self {
        case .cards: return "Browse the catalogue"
        case .sets: return "Explore expansions"
        case .pokemon: return "Search by Pokédex"
        case .sealed: return "Boxes, packs and more"
        }
    }

    var symbol: String {
        switch self {
        case .cards: return "rectangle.stack.fill"
        case .sets: return "square.grid.2x2.fill"
        case .pokemon: return "pawprint.fill"
        case .sealed: return "shippingbox.fill"
        }
    }
}

enum SearchHistoryStore {
    static let recentSearchesKey = "bindr.search.recentQueries"
    static let recentlyViewedCardsKey = "bindr.search.recentlyViewedCards"
    static let didChange = Notification.Name("bindr.search.history.didChange")

    static func strings(forKey key: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func addSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var searches = strings(forKey: recentSearchesKey)
        searches.removeAll { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
        searches.insert(trimmed, at: 0)
        UserDefaults.standard.set(Array(searches.prefix(5)), forKey: recentSearchesKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static func recordViewedCard(_ cardID: String) {
        guard !cardID.isEmpty else { return }
        var cardIDs = strings(forKey: recentlyViewedCardsKey)
        cardIDs.removeAll { $0 == cardID }
        cardIDs.insert(cardID, at: 0)
        UserDefaults.standard.set(Array(cardIDs.prefix(8)), forKey: recentlyViewedCardsKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}

enum SearchSourceScope: String, CaseIterable, Identifiable {
    case allCards
    case myCollection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allCards: return "All cards"
        case .myCollection: return "My collection"
        }
    }
}

struct SearchExperienceView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @Environment(\.presentCard) private var presentCard

    @Binding var query: String
    let onOpenCategory: (SearchIdleCategory) -> Void

    @State private var recentSearches: [String] = SearchHistoryStore.strings(forKey: SearchHistoryStore.recentSearchesKey)
    @State private var recentlyViewedCardIDs: [String] = SearchHistoryStore.strings(forKey: SearchHistoryStore.recentlyViewedCardsKey)
    @State private var sourceScope: SearchSourceScope = .allCards
    @State private var recentlyViewedCards: [Card] = []
    @State private var recentSets: [TCGSet] = []

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Text(services.brandSettings.selectedCatalogBrand.displayTitle)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .padding(.horizontal, 2)

                Picker("Search source", selection: $sourceScope) {
                    ForEach(SearchSourceScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 16)
            .padding(.top, rootFloatingChromeInset + 12)
            .padding(.bottom, 10)

            UniversalSearchResultsView(
                query: query,
                selectedBrand: services.brandSettings.selectedCatalogBrand,
                sourceScope: sourceScope,
                idleContent: AnyView(idleContent),
                onCommitSearch: {
                    SearchHistoryStore.addSearch(query)
                    recentSearches = SearchHistoryStore.strings(forKey: SearchHistoryStore.recentSearchesKey)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color.clear)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: recentlyViewedCardIDs) {
            await loadRecentlyViewedCards()
        }
        .task(id: services.brandSettings.selectedCatalogBrand) {
            let sets = await services.cardData.catalogSets(for: services.brandSettings.selectedCatalogBrand)
            recentSets = Array(sets.prefix(4))
        }
        .onReceive(NotificationCenter.default.publisher(for: SearchHistoryStore.didChange)) { _ in
            recentSearches = SearchHistoryStore.strings(forKey: SearchHistoryStore.recentSearchesKey)
            recentlyViewedCardIDs = SearchHistoryStore.strings(forKey: SearchHistoryStore.recentlyViewedCardsKey)
        }
    }

    private var idleContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2),
                    spacing: 12
                ) {
                    ForEach(SearchIdleCategory.allCases) { category in
                        Button {
                            Haptics.lightImpact()
                            onOpenCategory(category)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: category.symbol)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(services.theme.accentColor)
                                    .frame(width: 36, height: 36)
                                    .background(services.theme.accentColor.opacity(0.12), in: Circle())
                                Text(category.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(category.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .clearGlassCardStyle(cornerRadius: 16, interactive: true)
                            .contentShape(Rectangle())
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.plain)
                    }
                }

                if !recentSearches.isEmpty {
                    recentSearchesSection
                }

                if !recentlyViewedCards.isEmpty {
                    recentlyViewedSection
                } else if !recentSets.isEmpty {
                    exploreSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(Color.clear)
        .scrollDismissesKeyboard(.interactively)
    }

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent searches")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    recentSearches = []
                    UserDefaults.standard.set([], forKey: SearchHistoryStore.recentSearchesKey)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
            }

            VStack(spacing: 0) {
                ForEach(recentSearches, id: \.self) { recent in
                    HStack(spacing: 10) {
                        Button {
                            query = recent
                            SearchHistoryStore.addSearch(recent)
                        } label: {
                            HStack(spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.secondary)
                            Text(recent)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.plain)

                        Button {
                            recentSearches.removeAll { $0 == recent }
                            UserDefaults.standard.set(recentSearches, forKey: SearchHistoryStore.recentSearchesKey)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(recent)")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    if recent != recentSearches.last {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var recentlyViewedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recently viewed")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recentlyViewedCards) { card in
                        Button {
                            SearchHistoryStore.recordViewedCard(card.masterCardId)
                            presentCard(card, recentlyViewedCards)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                CachedAsyncImage(
                                    url: AppConfiguration.imageURL(relativePath: card.displayImageSrc),
                                    targetSize: CGSize(width: 150, height: 210)
                                ) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    Color.primary.opacity(0.06)
                                }
                                .frame(width: 82, height: 115)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                Text(card.cardName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .frame(width: 82, alignment: .leading)
                            }
                            .frame(width: 82, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var exploreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Explore recent sets")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(recentSets) { set in
                    NavigationLink(
                        value: SearchNavRoot.set(
                            set,
                            brand: services.brandSettings.selectedCatalogBrand
                        )
                    ) {
                        HStack(spacing: 12) {
                            SetLogoAsyncImage(
                                logoSrc: set.logoSrc,
                                height: 34,
                                brand: services.brandSettings.selectedCatalogBrand
                            )
                            .frame(width: 68, height: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(set.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(set.releaseDate ?? set.setCode.uppercased())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.plain)
                    if set.id != recentSets.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    @MainActor
    private func loadRecentlyViewedCards() async {
        var cards: [Card] = []
        for cardID in recentlyViewedCardIDs {
            if let card = await services.cardData.loadCard(masterCardId: cardID) {
                cards.append(card)
            }
        }
        recentlyViewedCards = cards
    }
}
