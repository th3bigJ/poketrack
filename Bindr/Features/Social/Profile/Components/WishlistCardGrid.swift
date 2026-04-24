import SwiftUI

struct WishlistCardGrid: View {
    let cardIDs: [String]
    let cardLoader: (String) async -> Card?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(cardIDs, id: \.self) { id in
                WishlistCardCell(cardID: id, cardLoader: cardLoader)
            }
        }
    }
}

private struct WishlistCardCell: View {
    let cardID: String
    let cardLoader: (String) async -> Card?

    @State private var card: Card?

    var body: some View {
        ZStack {
            if let imageURLString = card?.imageLowSrc {
                CachedAsyncImage(url: AppConfiguration.imageURL(relativePath: imageURLString)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    shimmer
                }
            } else {
                shimmer
            }
        }
        .aspectRatio(5/7, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task {
            card = await cardLoader(cardID)
        }
    }

    private var shimmer: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.05))
    }
}
