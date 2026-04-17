import SwiftUI
import SwiftData

struct BinderSlotPickerView: View {
    @Environment(AppServices.self) private var services
    @Query private var collectionItems: [CollectionItem]
    @Environment(\.dismiss) private var dismiss

    var onSelect: (String, String, String) -> Void

    @State private var query = ""
    @State private var results: [Card] = []
    @State private var isSearching = false
    @FocusState private var isSearchFieldFocused: Bool

    private var ownedCardIDs: Set<String> {
        Set(collectionItems.map { $0.cardID })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BrowseInlineSearchField(title: "Search all cards", text: $query)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .focused($isSearchFieldFocused)

                Group {
                    if results.isEmpty && query.isEmpty {
                        ContentUnavailableView("Search for a Card", systemImage: "magnifyingglass", description: Text("Type a card name to find it."))
                    } else if results.isEmpty && !query.isEmpty && isSearching {
                        VStack {
                            Spacer()
                            ProgressView("Searching…")
                            Spacer()
                        }
                    } else if results.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                                ForEach(results) { card in
                                    Button {
                                        onSelect(card.masterCardId, card.pricingVariants?.first ?? "normal", card.cardName)
                                        dismiss()
                                    } label: {
                                        PickerCardCell(card: card, isOwned: ownedCardIDs.contains(card.masterCardId))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(12)
                        }
                    }
                }
            }
            .navigationTitle("Add Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: query) { _, newQuery in
                performSearch(newQuery)
            }
            .onAppear {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    isSearchFieldFocused = true
                }
            }
        }
        .presentationDetents([.large])
    }

    private func performSearch(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            isSearching = false
            results = []
            return
        }
        isSearching = true
        Task {
            let brand = services.brandSettings.selectedCatalogBrand
            let found = await services.cardData.search(query: trimmed, catalogBrand: brand)
            await MainActor.run {
                results = found
                isSearching = false
            }
        }
    }
}

private struct PickerCardCell: View {
    let card: Card
    let isOwned: Bool

    private static let thumbSize = CGSize(width: 160, height: 224)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                CachedAsyncImage(
                    url: AppConfiguration.imageURL(relativePath: card.imageLowSrc),
                    targetSize: Self.thumbSize
                ) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    Color(uiColor: .systemGray5)
                        .aspectRatio(5/7, contentMode: .fit)
                }
                .aspectRatio(5/7, contentMode: .fit)
                Text(card.cardName)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }

            if isOwned {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
                    .background(Circle().fill(.white).padding(1))
                    .padding(4)
            }
        }
    }
}
