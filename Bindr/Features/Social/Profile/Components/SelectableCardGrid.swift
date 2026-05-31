import SwiftUI

struct SelectableCardGrid: View {
    let cardIDs: [String]
    @Binding var isSelectMode: Bool
    @Binding var selectedCardIDs: Set<String>
    let cardLoader: (String) async -> Card?
    var onCardTap: ((String) -> Void)? = nil

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
                SelectableCardCell(
                    cardID: id,
                    isSelectMode: isSelectMode,
                    isSelected: selectedCardIDs.contains(id),
                    cardLoader: cardLoader
                ) {
                    if isSelectMode {
                        if selectedCardIDs.contains(id) {
                            selectedCardIDs.remove(id)
                        } else {
                            selectedCardIDs.insert(id)
                        }
                    } else {
                        onCardTap?(id)
                    }
                }
            }

            if hasMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .onAppear { loadNextPage() }
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

private struct SelectableCardCell: View {
    let cardID: String
    let isSelectMode: Bool
    let isSelected: Bool
    let cardLoader: (String) async -> Card?
    let onTap: () -> Void

    @State private var card: Card?

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
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
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(hex: "E8B84B"), lineWidth: 2.5)
                    }
                }

                if isSelectMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isSelected ? Color(hex: "E8B84B") : Color.white.opacity(0.7))
                        .shadow(color: .black.opacity(0.5), radius: 3)
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .task { card = await cardLoader(cardID) }
    }

    private var shimmer: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.05))
    }
}
