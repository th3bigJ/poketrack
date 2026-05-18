import SwiftUI
import SwiftData

struct DecksRootView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.bindrAccent) private var bindrAccent
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]

    @State private var showCreateSheet = false
    @State private var showImportSheet = false
    @State private var showPaywall = false
    @State private var deckToDelete: Deck?
    @State private var showDeleteConfirm = false
    @State private var newDeckMenuHapticSentForCurrentTouch = false
    /// Measured height of the translucent floating header. Read back through
    /// the preference key so `safeAreaInset` reserves exactly the right top
    /// gutter as the header changes — keeps the deck list aligned without
    /// hard-coding magic numbers.
    @State private var decksHeaderHeight: CGFloat = 64

    private var activeBrand: TCGBrand { services.brandSettings.selectedCatalogBrand }
    private var visibleDecks: [Deck] {
        decks.filter { $0.tcgBrand == activeBrand }
    }
    /// `Menu` can swallow tap gestures; zero-distance drag gives a reliable touch-down haptic when opening the New Deck menu.
    private var newDeckMenuTouchDownHapticGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !newDeckMenuHapticSentForCurrentTouch else { return }
                newDeckMenuHapticSentForCurrentTouch = true
                HapticManager.impact(.light)
            }
            .onEnded { _ in
                newDeckMenuHapticSentForCurrentTouch = false
            }
    }

    var body: some View {
        // ZStack overlay pattern (matches Social + Binders + Dashboard's
        // floating chrome): scroll content sits underneath a translucent
        // floating header rather than below an opaque title bar.
        ZStack(alignment: .top) {
            Group {
                if decks.isEmpty {
                    emptyDecksView
                } else if visibleDecks.isEmpty {
                    emptyActiveBrandDecksView
                } else {
                    decksListView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: decksHeaderHeight)
            }
            decksHeader
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: DecksHeaderHeightKey.self, value: geo.size.height)
                    }
                )
                .onPreferenceChange(DecksHeaderHeightKey.self) { decksHeaderHeight = $0 }
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
        .sheet(isPresented: $showImportSheet) {
            ImportPTCGLSheet()
                .environment(services)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet()
                .environment(services)
        }
        .alert("Delete Deck?", isPresented: $showDeleteConfirm, presenting: deckToDelete) { deck in
            Button("Delete", role: .destructive) {
                modelContext.delete(deck)
            }
            Button("Cancel", role: .cancel) {}
        } message: { deck in
            Text("This will permanently remove \"\(deck.title)\".")
        }
        .task(id: decks.map(\.id).map(\.uuidString).sorted().joined(separator: ",")) {
            do {
                try await services.socialShare.reconcileDeletedDecks(localDeckIDs: Set(decks.map(\.id)))
            } catch {
                // Silent best-effort cleanup.
            }
        }
        .background(BindrPageBackground().ignoresSafeArea())
    }

    private var emptyDecksView: some View {
        ScrollView {
            ContentUnavailableView {
                Label("No Decks", systemImage: "rectangle.on.rectangle.angled")
            } description: {
                Text("Build your first deck.")
            } actions: {
                Menu {
                    Button { handleCreateTap() } label: {
                        Label("Create Manually", systemImage: "pencil")
                    }
                    Button { handleImportTap() } label: {
                        Label("Import from TCG Live", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Text("New Deck")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(bindrAccent)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
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
                Menu {
                    Button { handleCreateTap() } label: {
                        Label("Create Manually", systemImage: "pencil")
                    }
                    Button { handleImportTap() } label: {
                        Label("Import from TCG Live", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Text("New Deck")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(bindrAccent)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
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
                            .padding(14)
                            .glassCardStyle(cornerRadius: 16)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            HapticManager.impact(.light)
                        }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deckToDelete = deck
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button {
                            duplicateDeck(deck)
                        } label: {
                            Label("Duplicate Deck", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            deckToDelete = deck
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Deck", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var decksHeader: some View {
        BindrPageHeader(
            title: "Deck Builder",
            leading: {
                ChromeGlassCircleButton(accessibilityLabel: "Back") {
                    HapticManager.impact(.light)
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }
            },
            trailing: {
                Menu {
                    Button { handleCreateTap() } label: {
                        Label("Create Manually", systemImage: "pencil")
                    }
                    Button { handleImportTap() } label: {
                        Label("Import from TCG Live", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    ChromeGlassCircleButton(accessibilityLabel: "New Deck", action: {}) {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .allowsHitTesting(false) // Let the Menu handle the tap
                }
                .simultaneousGesture(newDeckMenuTouchDownHapticGesture)
            }
        )
    }

    private func duplicateDeck(_ source: Deck) {
        HapticManager.impact(.light)
        let copy = Deck(title: "\(source.title) Copy", brand: source.tcgBrand, format: source.deckFormat)
        modelContext.insert(copy)
        for card in source.cardList {
            let cardCopy = DeckCard(
                cardID: card.cardID,
                variantKey: card.variantKey,
                cardName: card.cardName,
                quantity: card.quantity,
                isBasicEnergy: card.isBasicEnergy,
                isAceSpec: card.isAceSpec,
                isRadiant: card.isRadiant,
                isBasicPokemon: card.isBasicPokemon,
                isRuleBox: card.isRuleBox,
                setKey: card.setKey,
                localId: card.localId,
                regulationMark: card.regulationMark,
                elementTypes: card.elementTypes,
                trainerType: card.trainerType,
                isEnergy: card.isEnergy,
                imageLowSrc: card.imageLowSrc,
                catalogCategory: card.catalogCategory,
                catalogSubtype: card.catalogSubtype,
                catalogStage: card.catalogStage,
                opCost: card.opCost,
                opPower: card.opPower,
                opCounter: card.opCounter
            )
            cardCopy.deck = copy
            modelContext.insert(cardCopy)
        }
    }

    private func handleCreateTap() {
        HapticManager.impact(.light)
        if !services.store.isPremium && visibleDecks.count >= 1 {
            showPaywall = true
        } else {
            showCreateSheet = true
        }
    }

    private func handleImportTap() {
        HapticManager.impact(.light)
        if !services.store.isPremium && visibleDecks.count >= 1 {
            showPaywall = true
        } else {
            showImportSheet = true
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
            .task(id: deck.previewCardID) {
                guard let cardID = deck.previewCardID else {
                    thumbnailURL = nil
                    return
                }
                if let deckCard = deck.cardList.first(where: { $0.cardID == cardID }) {
                    let localPath = deckCard.imageLowSrc.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !localPath.isEmpty {
                        thumbnailURL = AppConfiguration.imageURL(relativePath: localPath)
                        return
                    }
                }
                if let card = await services.cardData.loadCard(masterCardId: cardID) {
                    thumbnailURL = AppConfiguration.imageURL(relativePath: card.imageLowSrc)
                } else {
                    thumbnailURL = nil
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

/// Preference key used by ``DecksRootView`` to read its own translucent
/// header height back into a `safeAreaInset` so deck content reserves the
/// exact pixel-perfect amount of top space for the floating header.
private struct DecksHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 64
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
