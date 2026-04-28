import SwiftUI

struct PublicWishlistDetailView: View {
    let cardIDs: [String]
    let title: String
    let cardLoader: (String) async -> Card?
    let priceFormatter: (Double) -> String
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppServices.self) private var services
    
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(cardIDs, id: \.self) { cardID in
                        PublicWishlistDetailItem(
                            cardID: cardID,
                            cardLoader: cardLoader,
                            priceFormatter: priceFormatter
                        )
                    }
                }
                .padding(20)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct PublicWishlistDetailItem: View {
    let cardID: String
    let cardLoader: (String) async -> Card?
    let priceFormatter: (Double) -> String
    
    @State private var card: Card?
    @State private var price: Double?
    @Environment(\.colorScheme) var colorScheme
    @Environment(AppServices.self) private var services
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Card Thumbnail
            ZStack {
                if let imageURLString = card?.imageLowSrc {
                    CachedAsyncImage(url: AppConfiguration.imageURL(relativePath: imageURLString)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.1)
                    }
                } else {
                    Color.gray.opacity(0.1)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(5/7, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(card?.cardName ?? "Loading...")
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                
                if let setCode = card?.setCode {
                    Text(setCode)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                
                if let price = price {
                    Text(priceFormatter(price))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.blue)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
        )
        .task {
            card = await cardLoader(cardID)
            if let card = card {
                price = await services.pricing.usdPrice(for: card, printing: "normal")
            }
        }
    }
}
