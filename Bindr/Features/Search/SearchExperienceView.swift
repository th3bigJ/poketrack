import SwiftUI

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

struct SearchExperienceView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentCard) private var presentCard

    @Binding var query: String
    @Binding var scopeCategory: SearchScopeCategory
    let showsScopeHeader: Bool
    let onOpenPost: (UUID) -> Void

    @State private var recentSearches: [String] = SearchHistoryStore.strings(forKey: SearchHistoryStore.recentSearchesKey)
    @State private var recentlyViewedCardIDs: [String] = SearchHistoryStore.strings(forKey: SearchHistoryStore.recentlyViewedCardsKey)
    @State private var recentlyViewedCards: [Card] = []
    @State private var recentSets: [TCGSet] = []

    var body: some View {
        VStack(spacing: 0) {
            if showsScopeHeader {
                scopeHeader
            }

            UniversalSearchResultsView(
                query: query,
                selectedBrand: services.brandSettings.selectedCatalogBrand,
                scopeCategory: scopeCategory,
                idleContent: AnyView(idleContent),
                onCommitSearch: {
                    SearchHistoryStore.addSearch(query)
                    recentSearches = SearchHistoryStore.strings(forKey: SearchHistoryStore.recentSearchesKey)
                },
                onOpenPost: onOpenPost
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .bindrPageBackground()
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: recentlyViewedCardIDs) {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await loadRecentlyViewedCards()
        }
        .task(id: services.brandSettings.selectedCatalogBrand) {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let sets = await services.cardData.catalogSets(for: services.brandSettings.selectedCatalogBrand)
            recentSets = Array(sets.prefix(4))
        }
        .onReceive(NotificationCenter.default.publisher(for: SearchHistoryStore.didChange)) { _ in
            recentSearches = SearchHistoryStore.strings(forKey: SearchHistoryStore.recentSearchesKey)
            recentlyViewedCardIDs = SearchHistoryStore.strings(forKey: SearchHistoryStore.recentlyViewedCardsKey)
        }
    }

    private var scopeHeader: some View {
        SearchCategoryChipBar(selection: $scopeCategory)
            .padding(.top, RootChromeEnvironment.searchOverlayHeaderTopInset)
            .padding(.bottom, 4)
    }

    private var idleContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RootChromeEnvironment.searchOverlaySectionSpacing) {
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
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var sectionDividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)
    }

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent Searches")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Clear") {
                    recentSearches = []
                    UserDefaults.standard.set([], forKey: SearchHistoryStore.recentSearchesKey)
                }
                .font(.subheadline.weight(.medium))
                .bindrAccentForeground(services.theme.accentColor)
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
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(recent)
                                    .font(.subheadline)
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
                    .padding(.vertical, 10)
                    if recent != recentSearches.last {
                        Divider()
                            .overlay(sectionDividerColor)
                    }
                }
            }
        }
        .padding(16)
        .glassCardStyle(cornerRadius: 16, interactive: false)
    }

    private var recentlyViewedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recently Viewed")
                .font(.title3.weight(.semibold))

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
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .glassCardStyle(cornerRadius: 16, interactive: false)
    }

    private var exploreSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Explore Recent Sets")
                .font(.title3.weight(.semibold))

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
                            .overlay(sectionDividerColor)
                    }
                }
            }
        }
        .padding(16)
        .glassCardStyle(cornerRadius: 16, interactive: false)
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
