import SwiftUI
import SwiftData

struct DeckDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var deck: Deck
    @Query private var collectionItems: [CollectionItem]

    @State private var showCardPicker = false

    private var ownedCardIDs: Set<String> {
        Set(collectionItems.map { $0.cardID })
    }

    private var sortedCards: [DeckCard] {
        deck.cardList.sorted { $0.cardName < $1.cardName }
    }

    private var validationColor: Color {
        if deck.isValid { return .green }
        let total = deck.totalCardCount
        return total > deck.deckFormat.deckSize ? .red : Color(uiColor: .systemOrange)
    }

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(deck.totalCardCount) / \(deck.deckFormat.deckSize) cards")
                            .font(.headline)
                        if deck.validationIssues.isEmpty {
                            Text("Deck is valid")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Text(deck.validationIssues.first ?? "")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    Circle()
                        .fill(validationColor)
                        .frame(width: 12, height: 12)
                }
            }

            if sortedCards.isEmpty {
                Section {
                    ContentUnavailableView("No Cards", systemImage: "rectangle.on.rectangle.angled", description: Text("Tap \"Add Cards\" to build your deck."))
                        .listRowBackground(Color.clear)
                }
            } else {
                Section("Cards (\(sortedCards.count) entries)") {
                    ForEach(sortedCards) { deckCard in
                        DeckCardRow(
                            deckCard: deckCard,
                            isOwned: ownedCardIDs.contains(deckCard.cardID),
                            maxCopies: deckCard.isBasicEnergy ? 99 : deck.deckFormat.maxCopiesPerCard,
                            onQuantityChange: { newQty in
                                updateQuantity(deckCard: deckCard, qty: newQty)
                            },
                            onDelete: {
                                modelContext.delete(deckCard)
                            }
                        )
                    }
                }
            }
        }
        .listStyle(.plain)
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle($deck.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCardPicker = true } label: {
                    Label("Add Cards", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                ShareLink(item: exportText()) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showCardPicker) {
            DeckCardPickerView(deck: deck)
        }
    }

    private func updateQuantity(deckCard: DeckCard, qty: Int) {
        if qty <= 0 {
            modelContext.delete(deckCard)
        } else {
            deckCard.quantity = qty
        }
    }

    private func exportText() -> String {
        sortedCards
            .map { "\($0.quantity)x \($0.cardName)" }
            .joined(separator: "\n")
    }
}

private struct DeckCardRow: View {
    @Environment(AppServices.self) private var services
    let deckCard: DeckCard
    let isOwned: Bool
    let maxCopies: Int
    let onQuantityChange: (Int) -> Void
    let onDelete: () -> Void

    @State private var imageURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            // Card Preview Thumbnail
            ZStack {
                if let imageURL {
                    CachedAsyncImage(url: imageURL, targetSize: CGSize(width: 80, height: 112)) { img in
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color(uiColor: .systemGray6)
                    }
                } else {
                    Color(uiColor: .systemGray6)
                }
            }
            .frame(width: 40, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(.black.opacity(0.1), lineWidth: 0.5)
            }
            .task {
                if let card = await services.cardData.loadCard(masterCardId: deckCard.cardID) {
                    imageURL = AppConfiguration.imageURL(relativePath: card.imageLowSrc)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(deckCard.cardName)
                    .font(.body.bold())
                Text(isOwned ? "✓ Owned" : "Need \(deckCard.quantity)")
                    .font(.caption)
                    .foregroundStyle(isOwned ? .green : Color(uiColor: .systemOrange))
            }
            Spacer()
            HStack(spacing: 0) {
                Button {
                    onQuantityChange(deckCard.quantity - 1)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Text("\(deckCard.quantity)")
                    .frame(minWidth: 28)
                    .font(.body.monospacedDigit())
                    .multilineTextAlignment(.center)

                Button {
                    onQuantityChange(deckCard.quantity + 1)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(deckCard.quantity >= maxCopies ? Color(uiColor: .systemGray4) : .accentColor)
                .disabled(deckCard.quantity >= maxCopies)
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}

