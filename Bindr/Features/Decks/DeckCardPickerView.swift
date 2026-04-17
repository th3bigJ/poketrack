import SwiftUI
import SwiftData

struct DeckCardPickerView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let deck: Deck

    @State private var query = ""
    @State private var results: [Card] = []
    @State private var isSearching = false
    @State private var pendingCard: Card? = nil
    @State private var pendingQty: Int = 1

    private var deckCardMap: [String: DeckCard] {
        Dictionary(uniqueKeysWithValues: deck.cardList.map { ($0.cardID, $0) })
    }

    var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty && query.isEmpty {
                    ContentUnavailableView("Search for a Card", systemImage: "magnifyingglass", description: Text("Type a card name to search the \(deck.tcgBrand.displayTitle) catalog."))
                } else if results.isEmpty && !query.isEmpty && !isSearching {
                    ContentUnavailableView.search(text: query)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                            ForEach(results) { card in
                                Button {
                                    pendingCard = card
                                    pendingQty = 1
                                } label: {
                                    DeckPickerCardCell(
                                        card: card,
                                        inDeckQty: deckCardMap[card.masterCardId]?.quantity
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .navigationTitle("Add to Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search \(deck.tcgBrand.displayTitle) cards")
            .onChange(of: query) { _, q in performSearch(q) }
            .popover(item: $pendingCard) { card in
                QuantityPickerPopover(
                    card: card,
                    isBasicEnergy: isBasicEnergy(card),
                    maxCopies: deck.deckFormat.maxCopiesPerCard,
                    existingQty: deckCardMap[card.masterCardId]?.quantity ?? 0
                ) { qty in
                    addOrUpdate(card: card, qty: qty)
                    pendingCard = nil
                }
            }
        }
        .presentationDetents([.large])
    }

    private func performSearch(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            return
        }
        isSearching = true
        Task {
            let found = await services.cardData.search(query: trimmed, catalogBrand: deck.tcgBrand)
            await MainActor.run {
                results = found
                isSearching = false
            }
        }
    }

    private func isBasicEnergy(_ card: Card) -> Bool {
        deck.tcgBrand == .pokemon && card.cardName.hasPrefix("Basic") && card.category == "Energy"
    }

    private func addOrUpdate(card: Card, qty: Int) {
        if let existing = deckCardMap[card.masterCardId] {
            let newQty = existing.quantity + qty
            if newQty <= 0 {
                modelContext.delete(existing)
            } else {
                existing.quantity = newQty
            }
        } else {
            let deckCard = DeckCard(
                cardID: card.masterCardId,
                variantKey: card.pricingVariants?.first ?? "normal",
                cardName: card.cardName,
                quantity: qty,
                isBasicEnergy: isBasicEnergy(card)
            )
            deckCard.deck = deck
            modelContext.insert(deckCard)
        }
    }
}

private struct DeckPickerCardCell: View {
    let card: Card
    let inDeckQty: Int?

    private static let thumbSize = CGSize(width: 160, height: 224)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                CachedAsyncImage(
                    url: AppConfiguration.imageURL(relativePath: card.imageLowSrc),
                    targetSize: Self.thumbSize
                ) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    Color(uiColor: .systemGray5).aspectRatio(5/7, contentMode: .fit)
                }
                .aspectRatio(5/7, contentMode: .fit)

                Text(card.cardName)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }

            if let qty = inDeckQty {
                Text("In deck: \(qty)")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(4)
            }
        }
    }
}

private struct QuantityPickerPopover: View {
    let card: Card
    let isBasicEnergy: Bool
    let maxCopies: Int
    let existingQty: Int
    let onAdd: (Int) -> Void

    @State private var qty = 1
    @Environment(\.dismiss) private var dismiss

    private var effectiveMax: Int { isBasicEnergy ? 60 : maxCopies }

    var body: some View {
        VStack(spacing: 16) {
            Text(card.cardName)
                .font(.headline)
                .padding(.top)

            if existingQty > 0 {
                Text("Already in deck: \(existingQty)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Stepper("Add \(qty)", value: $qty, in: 1...max(1, effectiveMax - existingQty))
                .padding(.horizontal)

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Add") { onAdd(qty) }
                    .buttonStyle(.borderedProminent)
                    .disabled(existingQty + qty > effectiveMax)
            }
            .padding(.bottom)
        }
        .padding(.horizontal)
        .presentationDetents([.height(200)])
    }
}
