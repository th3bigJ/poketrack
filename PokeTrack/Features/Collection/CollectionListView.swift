import SwiftData
import SwiftUI

/// Owned cards — same grid pattern as Wishlist / Browse.
struct CollectionListView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.presentCard) private var presentCard
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @Query(sort: \CollectionItem.dateAcquired, order: .reverse) private var items: [CollectionItem]

    @State private var cardsByCardID: [String: Card] = [:]

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    private var collectionSignature: String {
        items.map { "\($0.cardID)|\($0.variantKey)|\($0.quantity)" }.joined(separator: "§")
    }

    private var orderedCards: [Card] {
        items.compactMap { cardsByCardID[$0.cardID] }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                collectionScrollGrid
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: collectionSignature) {
            await resolveCollectionCards()
        }
        .onAppear {
            services.setupCollectionLedger(modelContext: modelContext)
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                Color.clear.frame(height: rootFloatingChromeInset)

                Text("Collection")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)

                ContentUnavailableView(
                    "No collection yet",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("Add cards from card details with the + button.")
                )
                .frame(minHeight: 280)
            }
        }
    }

    private var collectionScrollGrid: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: rootFloatingChromeInset)

                Text("Collection")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        collectionCell(for: item)
                            .onAppear {
                                ImagePrefetcher.shared.prefetchCardWindow(orderedCards, startingAt: index + 1)
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private func collectionCell(for item: CollectionItem) -> some View {
        if let card = cardsByCardID[item.cardID] {
            Button {
                presentCard(card, orderedCards)
            } label: {
                CardGridCell(card: card, footnote: collectionFootnote(for: item))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(card.cardName), \(item.quantity) copies, \(item.variantKey)")
        } else {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .aspectRatio(5 / 7, contentMode: .fit)
                    .overlay {
                        ProgressView()
                    }
                Text(item.cardID)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func collectionFootnote(for item: CollectionItem) -> String {
        let v = item.variantKey
            .replacingOccurrences(of: "_", with: " ")
        return "×\(item.quantity) · \(v)"
    }

    private func resolveCollectionCards() async {
        var next: [String: Card] = [:]
        for item in items {
            if next[item.cardID] != nil { continue }
            if let c = await services.cardData.loadCard(masterCardId: item.cardID) {
                next[item.cardID] = c
            }
        }
        cardsByCardID = next
        ImagePrefetcher.shared.prefetchCardWindow(orderedCards, startingAt: 0, count: 24)
    }
}
