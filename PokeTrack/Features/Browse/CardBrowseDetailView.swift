import SwiftUI

struct CardBrowseDetailView: View {
    @Environment(AppServices.self) private var services

    let cards: [Card]
    @State private var index: Int
    @State private var navigationPath = NavigationPath()

    init(cards: [Card], startIndex: Int) {
        self.cards = cards
        let clamped: Int = {
            guard !cards.isEmpty else { return 0 }
            return min(max(0, startIndex), cards.count - 1)
        }()
        _index = State(initialValue: clamped)
    }

    private var currentCard: Card? {
        guard cards.indices.contains(index) else { return cards.first }
        return cards[index]
    }

    private var currentSet: TCGSet? {
        guard let card = currentCard else { return nil }
        return services.cardData.sets.first { $0.setCode == card.setCode }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .top) {
                if cards.isEmpty {
                    ContentUnavailableView("No card", systemImage: "rectangle.on.rectangle.slash")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TabView(selection: $index) {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { i, card in
                            CardBrowseDetailPage(card: card)
                                .tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: .top)
                }

                headerRow
            }
            .background(Color.black)
            .navigationBarHidden(true)
            .navigationDestination(for: TCGSet.self) { set in
                SetCardsView(set: set)
            }
            .navigationDestination(for: NationalDexPokemon.self) { mon in
                DexCardsView(dexId: mon.nationalDexNumber, displayName: mon.displayName)
            }
        }
        .presentationBackground(Color.black)
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .presentationCornerRadius(20)
    }

    private var currentPokemon: NationalDexPokemon? {
        guard let dexId = currentCard?.dexIds?.first else { return nil }
        return services.cardData.nationalDexPokemon.first { $0.nationalDexNumber == dexId }
    }

    private var pokemonImageURL: URL? {
        guard let imageUrl = currentPokemon?.imageUrl else { return nil }
        return AppConfiguration.pokemonArtURL(imageFileName: imageUrl)
    }

    @ViewBuilder
    private var headerRow: some View {
        let slotWidth: CGFloat = 80

        HStack(spacing: 0) {
            // Set logo — tappable, fixed-width left slot
            Button { if let set = currentSet { navigationPath.append(set) } } label: {
                if let set = currentSet {
                    SetLogoAsyncImage(logoSrc: set.logoSrc, height: 22)
                        .frame(maxWidth: slotWidth, maxHeight: 22)
                } else {
                    Color.clear
                }
            }
            .buttonStyle(.plain)
            .frame(width: slotWidth, alignment: .leading)

            // Card name + set name — truly centred
            VStack(spacing: 2) {
                Text(currentCard?.cardName ?? "")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .animation(.easeInOut(duration: 0.15), value: currentCard?.cardName)

                if let setName = currentSet?.name {
                    Text(setName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .animation(.easeInOut(duration: 0.15), value: setName)
                }
            }
            .frame(maxWidth: .infinity)

            // Pokémon art — right slot, fixed size always to keep header height stable
            Button {
                if let mon = currentPokemon { navigationPath.append(mon) }
            } label: {
                Group {
                    if let url = pokemonImageURL {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().scaledToFit()
                        } placeholder: {
                            Color.clear
                        }
                    } else {
                        Color.clear
                    }
                }
                .frame(width: slotWidth, height: 44, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .disabled(currentPokemon == nil)
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .background(.ultraThinMaterial.opacity(0.85))
        .background(Color.black.opacity(0.3))
    }
}

// MARK: - Single page (one card)

private struct CardBrowseDetailPage: View {
    let card: Card

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                AsyncImage(url: AppConfiguration.imageURL(relativePath: card.imageHighSrc ?? card.imageLowSrc)) {
                    $0.resizable().scaledToFit()
                } placeholder: {
                    Color.gray.opacity(0.12)
                        .aspectRatio(5/7, contentMode: .fit)
                }
                .padding(.horizontal, 16)
                .padding(.top, 64 + 8)

                CardPricingPanel(card: card)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }
}
