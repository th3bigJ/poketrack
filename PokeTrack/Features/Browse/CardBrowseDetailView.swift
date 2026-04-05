import SwiftUI

struct CardBrowseDetailView: View {
    @Environment(AppServices.self) private var services

    let card: Card

    @State private var gbp: String = "—"

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
            }
            .padding()
        }
        .navigationTitle("Card")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let p = await services.pricing.gbpPrice(for: card, printing: CardPrinting.standard.rawValue) {
                gbp = String(format: "£%.2f", p)
            }
        }
    }
}
