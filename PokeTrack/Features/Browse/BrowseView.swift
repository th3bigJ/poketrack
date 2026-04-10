import SwiftUI

// MARK: - Shared card grid cell

struct CardGridCell: View {
    let card: Card
    /// Optional line under the name (e.g. wishlist variant key).
    var footnote: String? = nil

    /// Target size for memory-efficient downsampling (~2x display size for retina)
    private static let thumbnailSize = CGSize(width: 220, height: 308)

    var body: some View {
        VStack(spacing: 4) {
            CachedAsyncImage(
                url: AppConfiguration.imageURL(relativePath: card.imageLowSrc),
                targetSize: Self.thumbnailSize
            ) { img in
                img.resizable().scaledToFit()
            } placeholder: {
                Color.gray.opacity(0.12)
                    .aspectRatio(5/7, contentMode: .fit)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(5/7, contentMode: .fit)
            Text(card.cardName)
                .font(.caption2)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
            if let footnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.caption2)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Subtle spring scale on press for all card grid cells — gives a premium tactile feel.
struct CardCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - Browse feed

struct BrowseView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.presentCard) private var presentCard
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @EnvironmentObject private var chromeScroll: ChromeScrollCoordinator

    @State private var shuffledRefs: [CardRef] = []
    @State private var nextRefIndex = 0
    @State private var displayedCards: [Card] = []
    @State private var isLoadingInitial = true
    @State private var isLoadingMore = false
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    private static let initialBatchSize = 60
    private static let pageSize = 30
    private static let prefetchBuffer = 15

    var body: some View {
        Group {
            if isLoadingInitial {
                ProgressView("Loading cards…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedCards.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No cards in the catalog yet.")
                        .foregroundStyle(.secondary)
                    if let err = services.cardData.lastError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                    Text("Pull to refresh after your catalog syncs, or check POKETRACK_R2_BASE_URL in Info.plist.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding()
            } else {
                scrollTrackedCardGrid
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .tabBarChromeFromScroll()
        .task { await bootstrapFeed(forceReshuffle: false) }
        .refreshable { await bootstrapFeed(forceReshuffle: true) }
    }

    private var browseCardGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(displayedCards.enumerated()), id: \.element.id) { index, card in
                Button { presentCard(card, displayedCards) } label: {
                    CardGridCell(card: card)
                }
                .buttonStyle(CardCellButtonStyle())
                .onAppear {
                    ImagePrefetcher.shared.prefetchCardWindow(displayedCards, startingAt: index + 1)
                    if index >= displayedCards.count - Self.prefetchBuffer {
                        Task { await loadNextPageIfNeeded() }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 16)
    }

    private var scrollTrackedCardGrid: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Keeps first row clear of the overlaid search bar; spacer scrolls away so cards can pass under the glass.
                Color.clear.frame(height: rootFloatingChromeInset)
                ScrollOffsetAnchor { y in chromeScroll.reportScrollOffsetY(y) }
                browseCardGrid
                if isLoadingMore {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            }
        }
        .coordinateSpace(name: "scroll")
    }

    private func bootstrapFeed(forceReshuffle: Bool) async {
        if !forceReshuffle && !displayedCards.isEmpty { return }
        ImagePrefetcher.shared.cancelAll()
        isLoadingInitial = true
        let refs = await services.cardData.browseFeedCardRefs(forceReshuffle: forceReshuffle)
        shuffledRefs = refs
        nextRefIndex = 0
        displayedCards = []
        guard !refs.isEmpty else { isLoadingInitial = false; return }
        let firstEnd = min(Self.initialBatchSize, refs.count)
        let batch = Array(refs[..<firstEnd])
        nextRefIndex = firstEnd
        displayedCards = await services.cardData.cardsInOrder(refs: batch)
        isLoadingInitial = false
        // Aggressively prefetch initial batch for instant display
        ImagePrefetcher.shared.prefetchInitialBatch(displayedCards, count: 60)
        prefetchNextWindow()
    }

    private func loadNextPageIfNeeded() async {
        guard !isLoadingMore, nextRefIndex < shuffledRefs.count else { return }
        isLoadingMore = true
        let end = min(nextRefIndex + Self.pageSize, shuffledRefs.count)
        let batch = Array(shuffledRefs[nextRefIndex..<end])
        nextRefIndex = end
        let more = await services.cardData.cardsInOrder(refs: batch)
        displayedCards.append(contentsOf: more)
        isLoadingMore = false
        prefetchNextWindow()
    }

    private func prefetchNextWindow() {
        let end = min(nextRefIndex + Self.pageSize, shuffledRefs.count)
        guard nextRefIndex < end else { return }
        let upcoming = Array(shuffledRefs[nextRefIndex..<end])
        Task.detached(priority: .low) {
            let cards = await services.cardData.cardsInOrder(refs: upcoming)
            let urls = cards.map { AppConfiguration.imageURL(relativePath: $0.imageLowSrc) }
            ImagePrefetcher.shared.prefetch(urls)
        }
    }
}

// MARK: - Set cards

struct SetCardsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.presentCard) private var presentCard
    let set: TCGSet

    @State private var cards: [Card] = []
    @State private var isLoading = true
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().padding()
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        Button { presentCard(card, cards) } label: { CardGridCell(card: card) }
                            .buttonStyle(CardCellButtonStyle())
                            .onAppear {
                                ImagePrefetcher.shared.prefetchCardWindow(cards, startingAt: index + 1)
                            }
                    }
                }
                .padding()
            }
        }
        .navigationTitle(set.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            isLoading = true
            let loaded = await services.cardData.loadCards(forSetCode: set.setCode)
            cards = sortCardsByLocalIdHighestFirst(loaded)
            ImagePrefetcher.shared.prefetchCardWindow(cards, startingAt: 0, count: 24)
            isLoading = false
        }
    }
}

/// Browse-by-set grid: highest catalog `localId` first (numeric when possible); ties and missing `localId` use `masterCardId`.
private func sortCardsByLocalIdHighestFirst(_ cards: [Card]) -> [Card] {
    cards.sorted { a, b in
        let va = localIdNumericSortValue(a.localId)
        let vb = localIdNumericSortValue(b.localId)
        if va != vb { return va > vb }
        return a.masterCardId > b.masterCardId
    }
}

/// Parses `localId` like `"102"` for ordering; missing or non-numeric sorts last (same as `Int.min`).
private func localIdNumericSortValue(_ raw: String?) -> Int {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
        return Int.min
    }
    if let v = Int(raw) { return v }
    let digits = raw.prefix { $0.isNumber }
    if let v = Int(String(digits)), !digits.isEmpty { return v }
    return Int.min
}

// MARK: - Dex cards

struct DexCardsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.presentCard) private var presentCard
    let dexId: Int
    let displayName: String

    @State private var cards: [Card] = []
    @State private var isLoading = true
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().padding()
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        Button { presentCard(card, cards) } label: { CardGridCell(card: card) }
                            .buttonStyle(CardCellButtonStyle())
                            .onAppear {
                                ImagePrefetcher.shared.prefetchCardWindow(cards, startingAt: index + 1)
                            }
                    }
                }
                .padding()
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            isLoading = true
            cards = await services.cardData.cards(matchingNationalDex: dexId)
            ImagePrefetcher.shared.prefetchCardWindow(cards, startingAt: 0, count: 24)
            isLoading = false
        }
    }
}

#Preview {
    NavigationStack { BrowseView() }
        .environment(AppServices())
        .environmentObject(ChromeScrollCoordinator())
}
