import SwiftUI

struct SelectableCardGrid: View {
    @Environment(AppServices.self) private var services

    let cardIDs: [String]
    @Binding var isSelectMode: Bool
    @Binding var selectedCardIDs: Set<String>
    let cardLoader: (String) async -> Card?
    var quantityByCardID: [String: Int] = [:]
    var sealedProductLoader: ((String) async -> SealedProduct?)? = nil
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
                    quantity: quantityByCardID[id],
                    accentColor: services.theme.accentColor,
                    cardLoader: cardLoader,
                    sealedProductLoader: sealedProductLoader
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
    private static let thumbnailSize = CGSize(width: 220, height: 308)

    let cardID: String
    let isSelectMode: Bool
    let isSelected: Bool
    let quantity: Int?
    let accentColor: Color
    let cardLoader: (String) async -> Card?
    var sealedProductLoader: ((String) async -> SealedProduct?)? = nil
    let onTap: () -> Void

    @State private var card: Card?
    @State private var sealedProduct: SealedProduct?
    @State private var isLoading = true

    private var isSealedItem: Bool {
        cardID.hasPrefix("sealed:")
    }

    var body: some View {
        Button(action: onTap) {
            Group {
                if let card, !card.displayImageSrc.isEmpty {
                    CachedAsyncImage(
                        url: AppConfiguration.imageURL(relativePath: card.displayImageSrc),
                        targetSize: Self.thumbnailSize
                    ) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        shimmer
                    }
                } else if let sealedProduct, let imageURL = sealedProduct.imageURL {
                    CachedAsyncImage(
                        url: imageURL,
                        targetSize: Self.thumbnailSize
                    ) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        shimmer
                    }
                } else if isLoading {
                    shimmer
                } else {
                    placeholderView
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(5/7, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(hex: "E8B84B"), lineWidth: 2.5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelectMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isSelected ? Color(hex: "E8B84B") : Color.white.opacity(0.7))
                        .shadow(color: .black.opacity(0.5), radius: 3)
                        .padding(4)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !isSelectMode, let quantity, quantity > 0 {
                    ZStack {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 24, height: 24)
                        Text("×\(quantity)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                    }
                    .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
                    .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .task(id: cardID) {
            isLoading = true
            card = nil
            sealedProduct = nil
            if isSealedItem, let sealedProductLoader {
                sealedProduct = await sealedProductLoader(cardID)
            } else {
                card = await cardLoader(cardID)
            }
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
