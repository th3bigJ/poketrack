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
            ForEach(visibleIDs, id: \.self) { id in
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
    @State private var isLoading = true

    var body: some View {
        ZStack {
            if let imageURL = card?.displayImageURL {
                CachedAsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    shimmer
                }
            } else if isLoading {
                shimmer
            } else {
                placeholderView
            }
        }
        .aspectRatio(5/7, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: cardID) {
            isLoading = true
            card = nil
            card = await cardLoader(cardID)
            isLoading = false
        }
    }

    private var shimmer: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.primary.opacity(0.05))
    }

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.primary.opacity(0.04))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text("Unavailable")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
            }
    }
}
