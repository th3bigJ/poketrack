import SwiftUI
import SwiftData

// MARK: - Post Type

private enum PostType: String, CaseIterable, Identifiable {
    case pull = "Card Pull"
    case want = "I Want"
    case binder = "Binder"
    case deck = "Deck"
    case folder = "Folder"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .pull:   return "sparkles"
        case .want:   return "heart"
        case .binder: return "books.vertical"
        case .deck:   return "rectangle.stack"
        case .folder: return "folder"
        }
    }

    var accentColor: Color {
        switch self {
        case .pull:   return Color(hex: "52C97C")
        case .want:   return Color(hex: "A78BFA")
        case .binder: return Color(hex: "E8B84B")
        case .deck:   return Color(hex: "5B9CF6")
        case .folder: return Color(hex: "22B8CF")
        }
    }
}

// MARK: - NewPostView

struct NewPostView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \CollectionItem.dateAcquired, order: .reverse) private var collectionItems: [CollectionItem]
    @Query(sort: \WishlistItem.dateAdded, order: .reverse) private var wishlistItems: [WishlistItem]
    @Query(sort: \Binder.createdAt, order: .reverse) private var binders: [Binder]
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]
    @Query(sort: \CardFolder.createdAt, order: .reverse) private var folders: [CardFolder]

    @State private var selectedType: PostType
    @State private var message = ""
    @State private var selectedCollectionItem: CollectionItem? = nil
    @State private var selectedWishlistItem: WishlistItem? = nil
    @State private var selectedBinder: Binder? = nil
    @State private var selectedDeck: Deck? = nil
    @State private var selectedFolder: CardFolder? = nil

    init(preselectedFolder: CardFolder? = nil, preselectedBinder: Binder? = nil, preselectedDeck: Deck? = nil) {
        if preselectedFolder != nil {
            _selectedType = State(initialValue: .folder)
            _selectedFolder = State(initialValue: preselectedFolder)
        } else if preselectedBinder != nil {
            _selectedType = State(initialValue: .binder)
            _selectedBinder = State(initialValue: preselectedBinder)
        } else if preselectedDeck != nil {
            _selectedType = State(initialValue: .deck)
            _selectedDeck = State(initialValue: preselectedDeck)
        } else {
            _selectedType = State(initialValue: .pull)
        }
    }
    @State private var cardNamesByID: [String: String] = [:]
    @State private var setCodesByID: [String: String] = [:]
    @State private var setNamesByID: [String: String] = [:]
    @State private var isBusy = false
    @State private var errorMessage: String? = nil
    @State private var showPaywall = false

    private var canPost: Bool {
        switch selectedType {
        case .pull:   return selectedCollectionItem != nil
        case .want:   return selectedWishlistItem != nil
        case .binder: return selectedBinder != nil
        case .deck:   return selectedDeck != nil
        case .folder: return selectedFolder != nil
        }
    }

    private var singleCards: [CollectionItem] {
        collectionItems.filter { $0.itemKind == ProductKind.singleCard.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider().opacity(0.15)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    typeSelector
                    contentPicker
                    messageField
                }
                .padding(16)
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .sheet(isPresented: $showPaywall) {
            PaywallSheet()
                .environment(services)
        }
        .task { await loadCardNames() }
        .onChange(of: selectedType) { _, _ in
            errorMessage = nil
        }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        ZStack {
            Text("New Post")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            HStack {
                Button("Cancel") { dismiss() }
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Task { await post() }
                } label: {
                    if isBusy {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 56, height: 28)
                    } else {
                        Text("Post")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(canPost ? selectedType.accentColor : Color.primary.opacity(0.12),
                                        in: Capsule())
                    }
                }
                .disabled(!canPost || isBusy)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Type Selector

    private var typeSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("TYPE")
            HStack(spacing: 8) {
                ForEach(PostType.allCases) { type in
                    typeChip(type)
                }
            }
        }
    }

    private func typeChip(_ type: PostType) -> some View {
        let isSelected = selectedType == type
        return Button {
            selectedType = type
        } label: {
            HStack(spacing: 5) {
                Image(systemName: type.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(type.rawValue)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isSelected ? type.accentColor : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? type.accentColor.opacity(0.12) : Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? type.accentColor.opacity(0.4) : Color.primary.opacity(0.1), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content Picker

    @ViewBuilder
    private var contentPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(contentSectionLabel)

            switch selectedType {
            case .pull:
                cardList(items: singleCards, selected: $selectedCollectionItem)
            case .want:
                wishlistList(selected: $selectedWishlistItem)
            case .binder:
                binderList(selected: $selectedBinder)
            case .deck:
                deckList(selected: $selectedDeck)
            case .folder:
                folderList(selected: $selectedFolder)
            }
        }
    }

    private var contentSectionLabel: String {
        switch selectedType {
        case .pull:   return "SELECT CARD FROM COLLECTION"
        case .want:   return "SELECT CARD FROM WISHLIST"
        case .binder: return "SELECT BINDER"
        case .deck:   return "SELECT DECK"
        case .folder: return "SELECT FOLDER"
        }
    }

    private func cardList(items: [CollectionItem], selected: Binding<CollectionItem?>) -> some View {
        Group {
            if items.isEmpty {
                emptyPicker("No cards in your collection yet.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items, id: \.cardID) { item in
                            let name = cardNamesByID[item.cardID] ?? item.cardID
                            let isSelected = selected.wrappedValue?.cardID == item.cardID &&
                                             selected.wrappedValue?.variantKey == item.variantKey
                            cardChip(
                                title: name,
                                subtitle: item.variantKey != "normal" ? item.variantKey : nil,
                                isSelected: isSelected,
                                color: PostType.pull.accentColor
                            ) {
                                selected.wrappedValue = isSelected ? nil : item
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    private func wishlistList(selected: Binding<WishlistItem?>) -> some View {
        Group {
            if wishlistItems.isEmpty {
                emptyPicker("Your wishlist is empty.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(wishlistItems, id: \.cardID) { item in
                            let name = cardNamesByID[item.cardID] ?? item.cardID
                            let isSelected = selected.wrappedValue?.cardID == item.cardID &&
                                             selected.wrappedValue?.variantKey == item.variantKey
                            cardChip(
                                title: name,
                                subtitle: item.variantKey != "normal" ? item.variantKey : nil,
                                isSelected: isSelected,
                                color: PostType.want.accentColor
                            ) {
                                selected.wrappedValue = isSelected ? nil : item
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    private func binderList(selected: Binding<Binder?>) -> some View {
        Group {
            if binders.isEmpty {
                emptyPicker("No binders yet.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(binders) { binder in
                            let isSelected = selected.wrappedValue?.id == binder.id
                            cardChip(
                                title: binder.title,
                                subtitle: "\(binder.slotList.count) cards",
                                isSelected: isSelected,
                                color: PostType.binder.accentColor
                            ) {
                                selected.wrappedValue = isSelected ? nil : binder
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    private func deckList(selected: Binding<Deck?>) -> some View {
        Group {
            if decks.isEmpty {
                emptyPicker("No decks yet.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(decks) { deck in
                            let isSelected = selected.wrappedValue?.id == deck.id
                            cardChip(
                                title: deck.title,
                                subtitle: "\(deck.totalCardCount) cards",
                                isSelected: isSelected,
                                color: PostType.deck.accentColor
                            ) {
                                selected.wrappedValue = isSelected ? nil : deck
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    private func folderList(selected: Binding<CardFolder?>) -> some View {
        Group {
            if folders.isEmpty {
                emptyPicker("No folders yet. Create a folder first.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(folders) { folder in
                            let isSelected = selected.wrappedValue?.id == folder.id
                            cardChip(
                                title: folder.title,
                                subtitle: "\((folder.items ?? []).count) cards",
                                isSelected: isSelected,
                                color: PostType.folder.accentColor
                            ) {
                                selected.wrappedValue = isSelected ? nil : folder
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    private func cardChip(title: String, subtitle: String?, isSelected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? color : Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? color.opacity(0.7) : Color.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: 160, alignment: .leading)
            .background(isSelected ? color.opacity(0.12) : Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? color.opacity(0.45) : Color.primary.opacity(0.1), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func emptyPicker(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Message Field

    private var messageField: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("MESSAGE (OPTIONAL)")
            TextField("Add a message…", text: $message, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineLimit(4, reservesSpace: true)
                .padding(12)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "E05252"))
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(Color.secondary.opacity(0.6))
    }

    // MARK: - Actions

    private func post() async {
        Haptics.rigidImpact()
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            switch selectedType {
            case .pull:
                guard let item = selectedCollectionItem else { return }
                let name = cardNamesByID[item.cardID] ?? item.cardID
                // Prefer the human-readable set name; fall back to the set code
                // only when the catalog hasn't been loaded yet.
                let resolvedSetName = setNamesByID[item.cardID] ?? setCodesByID[item.cardID]
                _ = try await services.socialShare.publishPull(
                    collectionItem: item,
                    cardName: name,
                    setName: resolvedSetName,
                    message: message,
                    visibility: .friends
                )
            case .want:
                guard let item = selectedWishlistItem else { return }
                let name = cardNamesByID[item.cardID] ?? item.cardID
                _ = try await services.socialShare.publishWant(
                    wishlistItem: item,
                    cardName: name,
                    message: message,
                    visibility: .friends
                )
            case .binder:
                guard let binder = selectedBinder else { return }
                _ = try await services.socialShare.publishBinder(
                    binder,
                    title: binder.title,
                    description: message,
                    visibility: .friends,
                    includeValue: false
                )
            case .deck:
                guard let deck = selectedDeck else { return }
                _ = try await services.socialShare.publishDeck(
                    deck,
                    title: deck.title,
                    description: message,
                    visibility: .friends,
                    includeValue: false
                )
            case .folder:
                guard let folder = selectedFolder else { return }
                _ = try await services.socialShare.publishFolder(
                    folder,
                    title: folder.title,
                    description: message,
                    visibility: .friends,
                    includeValue: false
                )
            }
            Haptics.success()
            dismiss()
        } catch {
            if case SocialShareService.SocialShareError.freeTierLimitReached = error {
                showPaywall = true
            } else if case SocialShareService.SocialShareError.deckSharingRequiresPremium = error {
                showPaywall = true
            }
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    private func loadCardNames() async {
        var ids = Set<String>()
        singleCards.forEach { ids.insert($0.cardID) }
        wishlistItems.forEach { ids.insert($0.cardID) }

        // Build a setCode -> human-readable set name map from the catalog so
        // pull posts can attribute the card to e.g. "Mega Evolution" rather
        // than the raw "me2pt5" set code.
        let setNameByCode = Dictionary(
            uniqueKeysWithValues: services.cardData.sets.map { ($0.setCode, $0.name) }
        )

        for id in ids {
            guard cardNamesByID[id] == nil else { continue }
            if let card = await services.cardData.loadCard(masterCardId: id) {
                cardNamesByID[id] = card.cardName
                setCodesByID[id] = card.setCode
                if let name = setNameByCode[card.setCode] {
                    setNamesByID[id] = name
                }
            }
        }
    }
}
