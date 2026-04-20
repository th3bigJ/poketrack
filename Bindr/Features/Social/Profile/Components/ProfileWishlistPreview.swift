import SwiftUI

struct ProfileWishlistPreview: View {
    let cardIDs: [String]
    let onEditTapped: () -> Void
    let cardLoader: (String) async -> Card?
    let priceFormatter: (Double) -> String
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(AppServices.self) private var services
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Wishlist Preview")
                    .font(.headline)
                Spacer()
                Button("View All") {
                    onEditTapped()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
            }
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(cardIDs.prefix(10), id: \.self) { cardID in
                        WishlistPreviewItem(
                            cardID: cardID,
                            cardLoader: cardLoader,
                            priceFormatter: priceFormatter
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

private struct WishlistPreviewItem: View {
    let cardID: String
    let cardLoader: (String) async -> Card?
    let priceFormatter: (Double) -> String
    
    @State private var card: Card?
    @State private var price: Double?
    @Environment(\.colorScheme) var colorScheme
    @Environment(AppServices.self) private var services
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Card Thumbnail
            ZStack {
                if let imageURLString = card?.imageLowSrc, let url = URL(string: imageURLString) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.1)
                    }
                } else {
                    Color.gray.opacity(0.1)
                }
            }
            .frame(width: 52, height: 73)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(card?.cardName ?? "Loading...")
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                
                if let price = price {
                    Text(priceFormatter(price))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Text("---")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        )
        .frame(width: 80)
        .task {
            card = await cardLoader(cardID)
            if let card = card {
                price = await services.pricing.usdPrice(for: card, printing: "normal")
            }
        }
    }
}
