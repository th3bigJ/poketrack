import SwiftUI
import SwiftData

struct DecksRootView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]

    @State private var showCreateSheet = false
    @State private var showPaywall = false
    @State private var deckToDelete: Deck?
    @State private var showDeleteConfirm = false

    private var activeBrand: TCGBrand { services.brandSettings.selectedCatalogBrand }
    private var visibleDecks: [Deck] {
        decks.filter { $0.tcgBrand == activeBrand }
    }

    var body: some View {
        VStack(spacing: 0) {
            decksHeader
            Group {
                if decks.isEmpty {
                    emptyDecksView
                } else if visibleDecks.isEmpty {
                    emptyActiveBrandDecksView
                } else {
                    decksListView
                }
            }
        }
        .navigationTitle("Deck Builder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: Deck.self) { deck in
            DeckDetailView(deck: deck)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateDeckSheet()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet()
                .environment(services)
        }
        .confirmationDialog("Delete Deck?", isPresented: $showDeleteConfirm, presenting: deckToDelete) { deck in
            Button("Delete \"\(deck.title)\"", role: .destructive) {
                modelContext.delete(deck)
            }
            Button("Cancel", role: .cancel) {}
        } message: { deck in
            Text("This will permanently remove \"\(deck.title)\".")
        }
    }

    private var emptyDecksView: some View {
        ScrollView {
            ContentUnavailableView {
                Label("No Decks", systemImage: "rectangle.on.rectangle.angled")
            } description: {
                Text("Build your first deck.")
            } actions: {
                Button("Create a Deck") { handleCreateTap() }
                    .buttonStyle(.borderedProminent)
            }
            .frame(minHeight: 300)
        }
    }

    private var emptyActiveBrandDecksView: some View {
        ScrollView {
            ContentUnavailableView {
                Label("No \(activeBrand.displayTitle) Decks", systemImage: "rectangle.on.rectangle.angled")
            } description: {
                Text("Create a \(activeBrand.displayTitle) deck.")
            } actions: {
                Button("Create a Deck") { handleCreateTap() }
                    .buttonStyle(.borderedProminent)
            }
            .frame(minHeight: 300)
        }
    }

    private var decksListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(visibleDecks) { deck in
                    NavigationLink(value: deck) {
                        DeckListRow(deck: deck)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            deckToDelete = deck
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Deck", systemImage: "trash")
                        }
                    }
                    Divider().padding(.leading, 70) // Align divider past thumbnail
                }
            }
        }
    }

    private var decksHeader: some View {
        ZStack {
            Text("Deck Builder")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)

            HStack {
                Spacer(minLength: 0)
                ChromeGlassCircleButton(accessibilityLabel: "Create Deck") { handleCreateTap() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func handleCreateTap() {
        if !services.store.isPremium && visibleDecks.count >= 1 {
            showPaywall = true
        } else {
            showCreateSheet = true
        }
    }
}

private struct DeckListRow: View {
    @Environment(AppServices.self) private var services
    let deck: Deck
    
    @State private var thumbnailURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            // Card Thumbnail Preview
            ZStack {
                if let thumbnailURL {
                    CachedAsyncImage(url: thumbnailURL, targetSize: CGSize(width: 80, height: 112)) { img in
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color(uiColor: .systemGray6)
                    }
                } else {
                    Color(uiColor: .systemGray6)
                        .overlay {
                            Image(systemName: "rectangle.portrait.badge.plus")
                                .font(.caption)
                                .foregroundStyle(.secondary.opacity(0.5))
                        }
                }
            }
            .frame(width: 40, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(.black.opacity(0.1), lineWidth: 0.5)
            }
            .task {
                if let cardID = deck.heroCardID,
                   let card = await services.cardData.loadCard(masterCardId: cardID) {
                    thumbnailURL = AppConfiguration.imageURL(relativePath: card.imageLowSrc)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(deck.title)
                    .font(.body.weight(.bold))
                    .foregroundStyle(.primary)

                HStack(spacing: 5) {
                    Text(deck.tcgBrand.displayTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(deck.deckFormat.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("\(deck.totalCardCount) cards")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !deck.isValid {
                        let issueCount = deck.validationIssues.count
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Label(issueCount == 1 ? "1 issue" : "\(issueCount) issues", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.quaternary)
        }
    }
}
