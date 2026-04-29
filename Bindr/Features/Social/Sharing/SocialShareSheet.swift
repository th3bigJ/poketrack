import SwiftUI
import SwiftData

// MARK: - Share Item

enum SocialShareItem {
    case folder(CardFolder)
    case binder(Binder)
    case deck(Deck)
    case card
}

// MARK: - Post Tag

private enum PostTag: String, CaseIterable, Identifiable {
    case pull    = "Card Pull"
    case bought  = "Bought"
    case trade   = "Trade"
    case want    = "I Want"
    case binder  = "Binder"
    case deck    = "Deck"
    case folder  = "Folder"

    var id: String { rawValue }

    var showsCardPicker: Bool {
        switch self {
        case .pull, .bought, .trade, .want: return true
        case .binder, .deck, .folder:       return false
        }
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        y += rowHeight
        return CGSize(width: width, height: y)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Glass Capsule Button Modifier

private struct GlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                content
                    .glassEffect(.regular.interactive(), in: Capsule())
            } else {
                content
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
            }
        }
    }
}

// MARK: - SocialShareSheet

struct SocialShareSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let item: SocialShareItem

    @Query(sort: \CollectionItem.dateAcquired, order: .reverse) private var collectionItems: [CollectionItem]
    @Query(sort: \WishlistItem.dateAdded, order: .reverse)      private var wishlistItems: [WishlistItem]
    @Query(sort: \Binder.createdAt, order: .reverse)            private var binders: [Binder]
    @Query(sort: \Deck.createdAt, order: .reverse)              private var decks: [Deck]
    @Query(sort: \CardFolder.createdAt, order: .reverse)        private var folders: [CardFolder]

    @State private var selectedTag: PostTag
    @State private var postText = ""
    @State private var selectedCollectionItem: CollectionItem? = nil
    @State private var selectedWishlistItem: WishlistItem? = nil
    @State private var selectedBinder: Binder? = nil
    @State private var selectedDeck: Deck? = nil
    @State private var selectedFolder: CardFolder? = nil
    @State private var visibility: SharedContentVisibility = .friends
    @State private var cardsByID: [String: Card] = [:]
    @State private var setCodesByID: [String: String] = [:]
    @State private var setNamesByID: [String: String] = [:]
    @State private var isBusy = false
    @State private var errorMessage: String? = nil
    @State private var showPaywall = false

    init(item: SocialShareItem) {
        self.item = item
        switch item {
        case .folder(let f):
            _selectedTag    = State(initialValue: .folder)
            _selectedFolder = State(initialValue: f)
        case .binder(let b):
            _selectedTag    = State(initialValue: .binder)
            _selectedBinder = State(initialValue: b)
        case .deck(let d):
            _selectedTag  = State(initialValue: .deck)
            _selectedDeck = State(initialValue: d)
        case .card:
            _selectedTag = State(initialValue: .pull)
        }
    }

    private var accent: Color { services.theme.accentColor }
    private var headerButtonColor: Color { colorScheme == .dark ? .white : .black }

    private var canPost: Bool {
        switch selectedTag {
        case .pull, .bought, .trade: return selectedCollectionItem != nil
        case .want:                  return selectedWishlistItem != nil
        case .binder:                return selectedBinder != nil
        case .deck:                  return selectedDeck != nil
        case .folder:                return selectedFolder != nil
        }
    }

    private var singleCards: [CollectionItem] {
        collectionItems.filter { $0.itemKind == ProductKind.singleCard.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
            header
            Divider().opacity(0.15)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    tagSection
                    if selectedTag.showsCardPicker {
                        cardImagePicker
                    } else {
                        nonCardPicker
                    }
                    postTextField
                    visibilityPicker
                }
                .padding(16)
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .sheet(isPresented: $showPaywall) {
            PaywallSheet().environment(services)
        }
        .task { await loadCards() }
        .onChange(of: selectedTag) { _, _ in errorMessage = nil }
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color.primary.opacity(0.2))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text("New Post")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            HStack {
                Button { dismiss() } label: {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(headerButtonColor)
                        .frame(height: 44)
                        .padding(.horizontal, 14)
                        .modifier(GlassCapsuleModifier())
                }
                .buttonStyle(.plain)
                .frame(height: 48)
                .contentShape(Rectangle())

                Spacer()

                Button { Task { await post() } } label: {
                    if isBusy {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 60, height: 44)
                            .modifier(GlassCapsuleModifier())
                    } else {
                        Text("Post")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(headerButtonColor)
                            .frame(height: 44)
                            .padding(.horizontal, 14)
                            .modifier(GlassCapsuleModifier())
                            .opacity(canPost ? 1 : 0.4)
                    }
                }
                .buttonStyle(.plain)
                .frame(height: 48)
                .contentShape(Rectangle())
                .disabled(!canPost || isBusy)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Tags

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("TYPE")
            FlowLayout(spacing: 8) {
                ForEach(PostTag.allCases) { tag in
                    tagChip(tag)
                }
            }
        }
    }

    private func tagChip(_ tag: PostTag) -> some View {
        let isSelected = selectedTag == tag
        return Button { selectedTag = tag } label: {
            Text(tag.rawValue)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? .primary : Color.primary.opacity(0.45))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    isSelected ? accent.opacity(0.12) : Color.primary.opacity(0.05),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(isSelected ? accent : Color.primary.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card Image Picker

    private var cardImagePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(selectedTag == .want ? "SELECT FROM WISHLIST" : "SELECT FROM COLLECTION")
            if selectedTag == .want {
                wishlistImagePicker
            } else {
                collectionImagePicker
            }
        }
    }

    private var collectionImagePicker: some View {
        Group {
            if singleCards.isEmpty {
                emptyPicker("No cards in your collection yet.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(singleCards, id: \.cardID) { item in
                            let isSelected = selectedCollectionItem?.cardID == item.cardID
                                          && selectedCollectionItem?.variantKey == item.variantKey
                            cardImageCell(cardID: item.cardID, variantKey: item.variantKey, isSelected: isSelected) {
                                selectedCollectionItem = isSelected ? nil : item
                            }
                        }
                    }
                    .padding(.horizontal, 1).padding(.vertical, 4)
                }
            }
        }
    }

    private var wishlistImagePicker: some View {
        Group {
            if wishlistItems.isEmpty {
                emptyPicker("Your wishlist is empty.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(wishlistItems, id: \.cardID) { item in
                            let isSelected = selectedWishlistItem?.cardID == item.cardID
                                          && selectedWishlistItem?.variantKey == item.variantKey
                            cardImageCell(cardID: item.cardID, variantKey: item.variantKey, isSelected: isSelected) {
                                selectedWishlistItem = isSelected ? nil : item
                            }
                        }
                    }
                    .padding(.horizontal, 1).padding(.vertical, 4)
                }
            }
        }
    }

    private func cardImageCell(cardID: String, variantKey: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let imageURL = cardsByID[cardID].map { AppConfiguration.imageURL(relativePath: $0.imageLowSrc) }
        return Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    CachedCardThumbnailImage(url: imageURL)
                        .frame(width: 80, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(isSelected ? accent : Color.primary.opacity(0.12), lineWidth: isSelected ? 2.5 : 1)
                        }
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white, accent)
                            .offset(x: 6, y: -6)
                    }
                }
            }
            .frame(width: 80)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Non-card pickers (binder / deck / folder)

    @ViewBuilder
    private var nonCardPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch selectedTag {
            case .binder:
                sectionLabel("SELECT BINDER")
                chipPicker(items: binders, id: { $0.id }, title: { $0.title }, subtitle: { "\($0.slotList.count) cards" },
                           selected: Binding(get: { selectedBinder?.id }, set: { id in selectedBinder = binders.first { $0.id == id } }))
            case .deck:
                sectionLabel("SELECT DECK")
                chipPicker(items: decks, id: { $0.id }, title: { $0.title }, subtitle: { "\($0.totalCardCount) cards" },
                           selected: Binding(get: { selectedDeck?.id }, set: { id in selectedDeck = decks.first { $0.id == id } }))
            case .folder:
                sectionLabel("SELECT FOLDER")
                chipPicker(items: folders, id: { $0.id }, title: { $0.title }, subtitle: { "\(($0.items ?? []).count) cards" },
                           selected: Binding(get: { selectedFolder?.id }, set: { id in selectedFolder = folders.first { $0.id == id } }))
            default:
                EmptyView()
            }
        }
    }

    private func chipPicker<T, ID: Equatable>(
        items: [T],
        id: @escaping (T) -> ID,
        title: @escaping (T) -> String,
        subtitle: @escaping (T) -> String,
        selected: Binding<ID?>
    ) -> some View {
        Group {
            if items.isEmpty {
                emptyPicker("Nothing here yet.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            let isSelected = selected.wrappedValue == id(item)
                            Button {
                                selected.wrappedValue = isSelected ? nil : id(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(title(item))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2).multilineTextAlignment(.leading)
                                    Text(subtitle(item))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .frame(maxWidth: 160, alignment: .leading)
                                .background(isSelected ? accent.opacity(0.12) : Color.primary.opacity(0.05),
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(isSelected ? accent : Color.primary.opacity(0.1), lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    // MARK: - Post Text

    private var postTextField: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("POST")
            TextField("Write something…", text: $postText, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineLimit(5, reservesSpace: true)
                .padding(12)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                }
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "E05252"))
            }
        }
    }

    // MARK: - Visibility

    private var visibilityPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("SHARE WITH")
            HStack(spacing: 10) {
                visibilityOption(.friends, label: "Friends", icon: "person.2.fill")
                visibilityOption(.link,    label: "Public",  icon: "globe")
            }
        }
    }

    private func visibilityOption(_ option: SharedContentVisibility, label: String, icon: String) -> some View {
        let isSelected = visibility == option
        return Button { visibility = option } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                Text(label).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(isSelected ? .primary : Color.primary.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(isSelected ? accent.opacity(0.18) : Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? accent : Color.primary.opacity(0.1), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(Color.primary.opacity(0.3))
    }

    private func emptyPicker(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color.primary.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Actions

    private func post() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            switch selectedTag {
            case .pull, .bought, .trade:
                guard let item = selectedCollectionItem else { return }
                let name = cardsByID[item.cardID]?.cardName ?? item.cardID
                let taggedMessage = tagPrefix + (postText.isEmpty ? "" : " \(postText)")
                // Prefer human-readable set name; fall back to set code only
                // if the catalog hasn't loaded yet.
                let resolvedSetName = setNamesByID[item.cardID] ?? setCodesByID[item.cardID]
                _ = try await services.socialShare.publishPull(
                    collectionItem: item, cardName: name, setName: resolvedSetName,
                    message: taggedMessage, visibility: visibility
                )
            case .want:
                guard let item = selectedWishlistItem else { return }
                let name = cardsByID[item.cardID]?.cardName ?? item.cardID
                _ = try await services.socialShare.publishWant(
                    wishlistItem: item, cardName: name, message: postText, visibility: visibility
                )
            case .binder:
                guard let binder = selectedBinder else { return }
                _ = try await services.socialShare.publishBinder(
                    binder, title: binder.title, description: postText, visibility: visibility, includeValue: false
                )
            case .deck:
                guard let deck = selectedDeck else { return }
                _ = try await services.socialShare.publishDeck(
                    deck, title: deck.title, description: postText, visibility: visibility, includeValue: false
                )
            case .folder:
                guard let folder = selectedFolder else { return }
                _ = try await services.socialShare.publishFolder(
                    folder, title: folder.title, description: postText, visibility: visibility, includeValue: false
                )
            }
            dismiss()
        } catch {
            if case SocialShareService.SocialShareError.freeTierLimitReached = error { showPaywall = true }
            else if case SocialShareService.SocialShareError.deckSharingRequiresPremium = error { showPaywall = true }
            errorMessage = error.localizedDescription
        }
    }

    private var tagPrefix: String {
        switch selectedTag {
        case .bought: return "#bought"
        case .trade:  return "#trade"
        default:      return ""
        }
    }

    private func loadCards() async {
        var ids = Set<String>()
        singleCards.forEach { ids.insert($0.cardID) }
        wishlistItems.forEach { ids.insert($0.cardID) }
        // Build a setCode -> human-readable set name map from the catalog so
        // pull posts attribute the card to e.g. "Mega Evolution" rather than
        // the raw "me2pt5" set code.
        let setNameByCode = Dictionary(
            uniqueKeysWithValues: services.cardData.sets.map { ($0.setCode, $0.name) }
        )
        for id in ids {
            guard cardsByID[id] == nil else { continue }
            if let card = await services.cardData.loadCard(masterCardId: id) {
                cardsByID[id] = card
                setCodesByID[id] = card.setCode
                if let name = setNameByCode[card.setCode] {
                    setNamesByID[id] = name
                }
            }
        }
    }
}
