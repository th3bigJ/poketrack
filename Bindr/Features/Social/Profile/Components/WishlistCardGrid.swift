import SwiftUI

struct WishlistCardGrid: View {
    let cardIDs: [String]
    let cardLoader: (String) async -> Card?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    private let pageSize = 36

    @State private var visibleCount: Int = 0
    @State private var isLoadingNextPage = false

    private var visibleIDs: [String] {
        Array(cardIDs.prefix(visibleCount))
    }

    private var hasMore: Bool {
        visibleCount < cardIDs.count
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(visibleIDs.enumerated()), id: \.offset) { _, id in
                WishlistCardCell(cardID: id, cardLoader: cardLoader)
            }

            if hasMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .onAppear {
                        loadNextPage()
                    }
            }
        }
        .onAppear {
            if visibleCount == 0 {
                visibleCount = min(pageSize, cardIDs.count)
            }
        }
        .onChange(of: cardIDs) { _, updated in
            visibleCount = min(pageSize, updated.count)
            isLoadingNextPage = false
        }
    }

    private func loadNextPage() {
        guard hasMore, !isLoadingNextPage else { return }
        isLoadingNextPage = true
        defer { isLoadingNextPage = false }
        visibleCount = min(visibleCount + pageSize, cardIDs.count)
    }
}

private struct WishlistCardCell: View {
    let cardID: String
    let cardLoader: (String) async -> Card?

    @State private var card: Card?

    var body: some View {
        ZStack {
            if let imageURLString = card?.displayImageSrc {
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
