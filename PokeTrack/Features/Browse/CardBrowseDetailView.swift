import SwiftData
import SwiftUI

struct CardBrowseDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    let card: Card

    @State private var gbp: String = "—"
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AsyncImage(url: AppConfiguration.imageURL(relativePath: card.imageHighSrc ?? card.imageLowSrc)) {
                    $0.resizable().scaledToFit()
                } placeholder: {
                    ProgressView()
                }
                .frame(maxHeight: 400)

                Text(card.cardName).font(.title.bold())
                Text("\(card.setCode) · \(card.cardNumber)")
                    .foregroundStyle(.secondary)

                Text("Market (est.): \(gbp)")
                    .font(.headline)

                HStack {
                    Button("Add to collection") {
                        addToCollection()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Wishlist") {
                        addWishlist()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("Card")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let p = await services.pricing.gbpPrice(for: card, printing: "Standard") {
                gbp = String(format: "£%.2f", p)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet().environment(services)
        }
    }

    private func addToCollection() {
        let count = (try? modelContext.fetch(FetchDescriptor<CollectionCard>()))?.count ?? 0
        guard FreemiumGate.canAddCollectionRow(currentRowCount: count, isPremium: services.store.isPremium) else {
            showPaywall = true
            return
        }
        let row = CollectionCard(
            masterCardId: card.masterCardId,
            setCode: card.setCode,
            quantity: 1,
            printing: "Standard",
            language: "English",
            conditionId: CardCondition.nearMint.rawValue
        )
        modelContext.insert(row)
    }

    private func addWishlist() {
        let w = WishlistItem(masterCardId: card.masterCardId, setCode: card.setCode)
        modelContext.insert(w)
    }
}
