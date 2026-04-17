import SwiftUI
import SwiftData

struct DecksRootView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]

    @State private var showCreateSheet = false
    @State private var showPaywall = false
    @State private var brandFilter: TCGBrand? = nil
    @State private var deckToDelete: Deck?
    @State private var showDeleteConfirm = false

    private var filteredDecks: [Deck] {
        guard let brand = brandFilter else { return decks }
        return decks.filter { $0.brand == brand.rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    Text("Deck Builder")
                        .font(.largeTitle.bold())
                    Spacer()
                    brandFilterMenu
                    Button { handleCreateTap() } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, rootFloatingChromeInset)
                .padding(.bottom, 12)

                if filteredDecks.isEmpty {
                    ContentUnavailableView {
                        Label("No Decks", systemImage: "rectangle.on.rectangle.angled")
                    } description: {
                        Text(decks.isEmpty ? "Build your first deck." : "No decks for this brand.")
                    } actions: {
                        if decks.isEmpty {
                            Button("Create a Deck") { handleCreateTap() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .frame(minHeight: 300)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredDecks) { deck in
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
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
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

    @ViewBuilder
    private var brandFilterMenu: some View {
        Menu {
            Button("All") { brandFilter = nil }
            Divider()
            ForEach(TCGBrand.allCases) { brand in
                Button(brand.displayTitle) { brandFilter = brand }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.title3.weight(.semibold))
        }
    }

    private func handleCreateTap() {
        if !services.store.isPremium && decks.count >= 1 {
            showPaywall = true
        } else {
            showCreateSheet = true
        }
    }
}

private struct DeckListRow: View {
    let deck: Deck

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(brandColor(deck.tcgBrand))
                .frame(width: 6)
                .frame(maxHeight: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(deck.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(deck.tcgBrand.displayTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(deck.deckFormat.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("\(deck.totalCardCount) / \(deck.deckFormat.deckSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Circle()
                .fill(validityColor(deck))
                .frame(width: 8, height: 8)
        }
    }

    private func brandColor(_ brand: TCGBrand) -> Color {
        switch brand {
        case .pokemon:  return .red
        case .onePiece: return .yellow
        case .lorcana:  return .blue
        }
    }

    private func validityColor(_ deck: Deck) -> Color {
        let total = deck.totalCardCount
        let target = deck.deckFormat.deckSize
        if deck.isValid { return .green }
        if total > target { return .red }
        return Color(uiColor: .systemOrange)
    }
}
