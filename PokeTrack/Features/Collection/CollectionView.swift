import SwiftData
import SwiftUI

struct CollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Query(sort: \CollectionCard.addedAt, order: .reverse) private var collectionCards: [CollectionCard]

    @State private var showAdd = false
    @State private var showPaywall = false

    var body: some View {
        Group {
            if collectionCards.isEmpty {
                ContentUnavailableView(
                    "No cards yet",
                    systemImage: "square.grid.2x2",
                    description: Text("Add cards from the Cards tab or use the scanner (Premium).")
                )
            } else {
                List {
                    ForEach(collectionCards, id: \.id) { row in
                        NavigationLink {
                            CollectionCardDetailView(collectionCard: row)
                        } label: {
                            CollectionCardRowView(collectionCard: row)
                        }
                    }
                    .onDelete(perform: deleteRows)
                }
            }
        }
        .navigationTitle("Collection")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if FreemiumGate.canAddCollectionRow(
                        currentRowCount: collectionCards.count,
                        isPremium: services.store.isPremium
                    ) {
                        showAdd = true
                    } else {
                        showPaywall = true
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddCollectionCardSheet()
                .environment(services)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet()
                .environment(services)
        }
    }

    private func deleteRows(at offsets: IndexSet) {
        for i in offsets {
            modelContext.delete(collectionCards[i])
        }
    }
}

struct CollectionCardRowView: View {
    @Environment(AppServices.self) private var services
    let collectionCard: CollectionCard
    @State private var displayPrice: String = "—"

    var body: some View {
        HStack(spacing: 12) {
            cardThumb
            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.headline)
                Text("\(collectionCard.printing) · ×\(collectionCard.quantity)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(displayPrice)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: collectionCard.id) {
            await refreshPrice()
        }
    }

    private var titleText: String {
        if let c = services.cardData.card(
            masterCardId: collectionCard.masterCardId,
            setCode: collectionCard.setCode
        ) {
            return c.cardName
        }
        return collectionCard.masterCardId
    }

    private var cardThumb: some View {
        Group {
            if let c = services.cardData.card(
                masterCardId: collectionCard.masterCardId,
                setCode: collectionCard.setCode
            ) {
                AsyncImage(url: AppConfiguration.imageURL(relativePath: c.imageLowSrc)) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFit()
                    default:
                        Color.gray.opacity(0.15)
                    }
                }
                .frame(width: 44, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 44, height: 62)
            }
        }
    }

    private func refreshPrice() async {
        guard let card = services.cardData.card(
            masterCardId: collectionCard.masterCardId,
            setCode: collectionCard.setCode
        ) else {
            displayPrice = "—"
            return
        }
        if let manual = collectionCard.unlistedPrice {
            displayPrice = String(format: "£%.2f (manual)", manual)
            return
        }
        if let p = await services.pricing.gbpPrice(for: card, printing: collectionCard.printing) {
            displayPrice = String(format: "£%.2f", p)
        } else {
            displayPrice = "—"
        }
    }
}
