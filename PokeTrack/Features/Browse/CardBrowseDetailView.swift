import SwiftUI

struct CardBrowseDetailView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let cards: [Card]
    @State private var index: Int

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

    var body: some View {
        GeometryReader { geo in
            let topInset = geo.safeAreaInsets.top
            let headerTop = topInset + 8
            let headerHeight: CGFloat = 48
            /// `ScrollView` already respects the top safe area for its *first* layout pass, so the leading
            /// `Color.clear` must only clear the **header row** (8pt below safe area + 48pt bar). Including
            /// `safeAreaInsets.top` again stacks the inset twice and leaves a large black gap under the title.
            let scrollTopClearance = headerHeight + 8

            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                if cards.isEmpty {
                    ContentUnavailableView("No card", systemImage: "rectangle.on.rectangle.slash")
                        .foregroundStyle(.secondary)
                } else {
                    TabView(selection: $index) {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { i, card in
                            CardBrowseDetailPage(
                                card: card,
                                topContentInset: scrollTopClearance,
                                bottomInset: geo.safeAreaInsets.bottom + 16
                            )
                            .tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }

                if let card = currentCard {
                    let set = services.cardData.sets.first { $0.setCode == card.setCode }
                    headerBar(title: card.cardName, set: set, headerTop: headerTop, headerHeight: headerHeight)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    @ViewBuilder
    private func headerBar(title: String, set: TCGSet?, headerTop: CGFloat, headerHeight: CGFloat) -> some View {
        ZStack {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
                .animation(.easeInOut(duration: 0.2), value: title)

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.15)))
                }
                Spacer()
                if let sym = set?.symbolSrc?.trimmingCharacters(in: .whitespacesAndNewlines), !sym.isEmpty {
                    SetSymbolAsyncImage(symbolSrc: sym, height: 28)
                        .frame(width: 28, height: 28)
                        .padding(.trailing, 4)
                }
            }
        }
        .frame(height: headerHeight)
        .padding(.horizontal, 16)
        .padding(.top, headerTop)
    }
}

// MARK: - Single page (one card)

private struct CardBrowseDetailPage: View {
    @Environment(AppServices.self) private var services

    let card: Card
    let topContentInset: CGFloat
    let bottomInset: CGFloat

    @State private var gbp: String = "—"

    private var setForCard: TCGSet? {
        services.cardData.sets.first { $0.setCode == card.setCode }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: topContentInset)

                AsyncImage(url: AppConfiguration.imageURL(relativePath: card.imageHighSrc ?? card.imageLowSrc)) {
                    $0.resizable().scaledToFit()
                } placeholder: {
                    Color.gray.opacity(0.12)
                        .aspectRatio(5/7, contentMode: .fit)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                VStack(spacing: 16) {
                    cardSetAttribution
                    Text("Market (est.): \(gbp)")
                        .font(.headline)
                }
                .padding(.top, 16)
            }
            .padding(.bottom, bottomInset)
        }
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .task(id: "\(card.setCode)|\(card.masterCardId)") {
            gbp = "—"
            if let p = await services.pricing.gbpPrice(for: card, printing: CardPrinting.standard.rawValue) {
                gbp = String(format: "£%.2f", p)
            }
        }
    }

    @ViewBuilder
    private var cardSetAttribution: some View {
        if let set = setForCard {
            SetLogoAsyncImage(logoSrc: set.logoSrc, height: 36)
                .frame(height: 36)
        } else {
            Text("\(card.setCode) · \(card.cardNumber)")
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .padding(.horizontal, 16)
        }
    }
}
