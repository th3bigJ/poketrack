import SwiftUI
import SwiftData

struct SocialProfileFormPayload: Sendable {
    let username: String
    let displayName: String
    let bio: String
    let profileRoles: [String]
    let favoritePokemonDex: Int?
    let favoritePokemonName: String?
    let favoritePokemonImageURL: String?
    let favoriteCardID: String?
    let favoriteCardName: String?
    let favoriteCardSetCode: String?
    let favoriteCardImageURL: String?
    let favoriteDeckArchetype: String
    let isWishlistPublic: Bool
    let wishlistCardIDs: [String]?
    let avatarBackgroundColor: String?
    let avatarOutlineStyle: String?
    let collectionCardCount: Int?
    let collectionBinderCount: Int?
    let collectionTotalValue: Double?
}

private struct FavoritePokemonSelection: Identifiable, Hashable {
    let dexNumber: Int
    let name: String
    let imageURL: String?

    var id: Int { dexNumber }
}

private struct FavoriteCardSelection: Identifiable, Hashable {
    let cardID: String
    let cardName: String
    let setCode: String
    let imageURL: String?

    var id: String { cardID }
}

struct EditProfileView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private enum ProfileRole: String, CaseIterable, Identifiable {
        case collector = "collector"
        case tcgPlayer = "tcg_player"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .collector: return "Collector"
            case .tcgPlayer: return "TCG Player"
            }
        }
    }

    let existingProfile: SocialProfile?
    let onSave: (SocialProfileFormPayload) async throws -> Void

    @State private var username: String
    @State private var displayName: String
    @State private var bio: String
    @State private var profileRoles: Set<ProfileRole>
    @State private var favoriteDeckArchetype: String
    @State private var favoritePokemon: FavoritePokemonSelection?
    @State private var favoriteCard: FavoriteCardSelection?
    @State private var isWishlistPublic: Bool
    @State private var showPokemonPicker = false
    @State private var showCardPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var avatarBackgroundColor: String?
    @State private var avatarOutlineStyle: String?

    init(
        existingProfile: SocialProfile?,
        onSave: @escaping (SocialProfileFormPayload) async throws -> Void
    ) {
        self.existingProfile = existingProfile
        self.onSave = onSave
        _username = State(initialValue: existingProfile?.username ?? "")
        _displayName = State(initialValue: existingProfile?.displayName ?? "")
        _bio = State(initialValue: existingProfile?.bio ?? "")
        _profileRoles = State(initialValue: Set((existingProfile?.profileRoles ?? []).compactMap(ProfileRole.init(rawValue:))))
        _favoriteDeckArchetype = State(initialValue: existingProfile?.favoriteDeckArchetype ?? "")
        _isWishlistPublic = State(initialValue: existingProfile?.isWishlistPublic ?? false)
        _avatarBackgroundColor = State(initialValue: existingProfile?.avatarBackgroundColor)
        _avatarOutlineStyle = State(initialValue: existingProfile?.avatarOutlineStyle)
        _favoritePokemon = State(initialValue: {
            guard let dex = existingProfile?.favoritePokemonDex else { return nil }
            return FavoritePokemonSelection(
                dexNumber: dex,
                name: existingProfile?.favoritePokemonName ?? "#\(dex)",
                imageURL: existingProfile?.favoritePokemonImageURL
            )
        }())
        _favoriteCard = State(initialValue: {
            guard let cardID = existingProfile?.favoriteCardID else { return nil }
            return FavoriteCardSelection(
                cardID: cardID,
                cardName: existingProfile?.favoriteCardName ?? cardID,
                setCode: existingProfile?.favoriteCardSetCode ?? "",
                imageURL: existingProfile?.favoriteCardImageURL
            )
        }())
    }

    private var isUsernameLocked: Bool {
        existingProfile != nil
    }

    private var canSave: Bool {
        if isSaving { return false }
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        if profileRoles.isEmpty { return false }
        return true
    }



    var body: some View {
        Form {
            Section {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(isUsernameLocked)

                TextField("Display name", text: $displayName)

                TextField("Bio", text: $bio, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("Profile")
            } footer: {
                Text(isUsernameLocked
                     ? "Username is locked after first save."
                     : "Choose your public username. You cannot change it later.")
            }

            Section {
                HStack {
                    Spacer()
                    ProfileAvatarView(
                        profile: SocialProfile(
                            id: existingProfile?.id ?? UUID(),
                            appleUserID: nil,
                            username: username,
                            displayName: displayName,
                            avatarURL: nil,
                            bio: bio,
                            profileRoles: [],
                            favoritePokemonDex: favoritePokemon?.dexNumber,
                            favoritePokemonName: favoritePokemon?.name,
                            favoritePokemonImageURL: favoritePokemon?.imageURL,
                            favoriteCardID: favoriteCard?.cardID,
                            favoriteCardName: favoriteCard?.cardName,
                            favoriteCardSetCode: favoriteCard?.setCode,
                            favoriteCardImageURL: favoriteCard?.imageURL,
                            favoriteDeckArchetype: favoriteDeckArchetype,
                            pinnedCardID: nil,
                            followerCount: 0,
                            isWishlistPublic: isWishlistPublic,
                            wishlistCardIDs: [],
                            avatarBackgroundColor: avatarBackgroundColor,
                            avatarOutlineStyle: avatarOutlineStyle,
                            collectionCardCount: 0,
                            collectionBinderCount: 0,
                            collectionTotalValue: 0,
                            createdAt: nil
                        ),
                        size: 100
                    )
                    Spacer()
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Avatar Background")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 12) {
                        let colors = [
                            ("Indigo", "6366f1"),
                            ("Rose", "f43f5e"),
                            ("Amber", "f59e0b"),
                            ("Emerald", "10b981"),
                            ("Purple", "a855f7"),
                            ("Cyan", "06b6d4"),
                            ("Lime", "84cc16"),
                            ("Slate", "64748b")
                        ]
                        
                        ForEach(colors, id: \.1) { name, hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 38, height: 38)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(avatarBackgroundColor == hex ? 1 : 0), lineWidth: 3)
                                        .padding(-4)
                                )
                                .onTapGesture {
                                    avatarBackgroundColor = hex
                                }
                        }
                    }
                    .padding(.vertical, 4)
                    
                    Divider().padding(.vertical, 4)
                    
                    Text("Avatar Outline Pattern")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            let styles = [
                                ("Solid", "solid"),
                                ("Thick", "thick"),
                                ("Dashed", "dashed"),
                                ("Dotted", "dotted"),
                                ("Double", "double"),
                                ("Glow", "glow")
                            ]
                            
                            ForEach(styles, id: \.1) { name, style in
                                Button {
                                    avatarOutlineStyle = style
                                } label: {
                                    Text(name)
                                        .font(.system(size: 14, weight: .medium))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(avatarOutlineStyle == style ? Color.blue : Color.gray.opacity(0.1))
                                        )
                                        .foregroundStyle(avatarOutlineStyle == style ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("Avatar Customization")
            } footer: {
                Text("Personalize your trainer profile picture with colors and patterns.")
            }

            Section {
                ForEach(ProfileRole.allCases) { role in
                    Toggle(role.title, isOn: Binding(
                        get: { profileRoles.contains(role) },
                        set: { isOn in
                            if isOn { profileRoles.insert(role) } else { profileRoles.remove(role) }
                        }
                    ))
                }
            } footer: {
                Text("You can choose both Collector and TCG Player.")
            }

            Section {
                Toggle("Show Wishlist on Profile", isOn: $isWishlistPublic)
            } header: {
                Text("Privacy")
            } footer: {
                Text("If enabled, your wishlist will be visible to other users on your profile.")
            }

            Section {
                Button {
                    showPokemonPicker = true
                } label: {
                    HStack(spacing: 12) {
                        if let favoritePokemon {
                            if let imageURL = favoritePokemon.imageURL,
                               let url = URL(string: imageURL) {
                                CachedAsyncImage(url: url) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    Color.gray.opacity(0.12)
                                }
                                .frame(width: 34, height: 34)
                            } else {
                                Image(systemName: "hare")
                                    .frame(width: 34, height: 34)
                                    .foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Favorite Pokémon")
                                    .foregroundStyle(.secondary)
                                Text(favoritePokemon.name)
                                    .foregroundStyle(.primary)
                            }
                        } else {
                            Label("Choose favorite Pokémon", systemImage: "hare")
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    showCardPicker = true
                } label: {
                    HStack(spacing: 12) {
                        if let favoriteCard {
                            if let imageURL = favoriteCard.imageURL,
                               let url = URL(string: imageURL) {
                                CachedAsyncImage(url: url) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    Color.gray.opacity(0.12)
                                }
                                .frame(width: 24, height: 34)
                            } else {
                                Image(systemName: "rectangle.stack.fill")
                                    .frame(width: 24, height: 34)
                                    .foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Favorite card")
                                    .foregroundStyle(.secondary)
                                Text(favoriteCard.cardName)
                                    .foregroundStyle(.primary)
                                if !favoriteCard.setCode.isEmpty {
                                    Text(favoriteCard.setCode)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Label("Choose favorite card", systemImage: "rectangle.stack.fill")
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                TextField("Favorite deck archetype", text: $favoriteDeckArchetype)
            } header: {
                Text("Favorites")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    save()
                } label: {
                    if isSaving {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Saving…")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("Save Profile")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(existingProfile == nil ? "Create Profile" : "Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Save Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .sheet(isPresented: $showPokemonPicker) {
            NavigationStack {
                FavoritePokemonPickerView(selection: $favoritePokemon)
                    .environment(services)
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showCardPicker) {
            NavigationStack {
                FavoriteCardPickerView(selection: $favoriteCard)
                    .environment(services)
            }
            .presentationDetents([.large])
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSaving ? "Saving..." : "Save") {
                    save()
                }
                .foregroundStyle(.primary)
                .fontWeight(.bold)
                .disabled(!canSave)
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        errorMessage = nil
        isSaving = true
        let resolvedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let roleValues = profileRoles.map(\.rawValue).sorted()
        let wishlistIDs = services.wishlist?.items.prefix(10).map(\.cardID)
        let payload = SocialProfileFormPayload(
            username: resolvedUsername,
            displayName: displayName,
            bio: bio,
            profileRoles: roleValues,
            favoritePokemonDex: favoritePokemon?.dexNumber,
            favoritePokemonName: favoritePokemon?.name,
            favoritePokemonImageURL: favoritePokemon?.imageURL,
            favoriteCardID: favoriteCard?.cardID,
            favoriteCardName: favoriteCard?.cardName,
            favoriteCardSetCode: favoriteCard?.setCode,
            favoriteCardImageURL: favoriteCard?.imageURL,
            favoriteDeckArchetype: favoriteDeckArchetype,
            isWishlistPublic: isWishlistPublic,
            wishlistCardIDs: wishlistIDs,
            avatarBackgroundColor: avatarBackgroundColor,
            avatarOutlineStyle: avatarOutlineStyle,
            collectionCardCount: (try? modelContext.fetchCount(FetchDescriptor<CollectionItem>())) ?? 0,
            collectionBinderCount: (try? modelContext.fetchCount(FetchDescriptor<Binder>())) ?? 0,
            collectionTotalValue: services.collectionValue?.snapshots.last?.totalGbp ?? 0
        )
        Task {
            do {
                print("[EditProfileView] Calling onSave…")
                try await onSave(payload)
                print("[EditProfileView] onSave succeeded")
            } catch {
                print("[EditProfileView] onSave FAILED: \(error)")
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                    isSaving = false
                }
                return
            }
            await MainActor.run {
                isSaving = false
            }
        }
    }
}

private struct FavoritePokemonPickerView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: FavoritePokemonSelection?

    @State private var rows: [NationalDexPokemon] = []
    @State private var isLoading = true
    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    private var filteredRows: [NationalDexPokemon] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return rows }
        return rows.filter {
            $0.name.lowercased().contains(trimmed)
            || $0.displayName.lowercased().contains(trimmed)
            || String($0.nationalDexNumber).contains(trimmed)
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading Pokémon…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredRows) { item in
                            Button {
                                selection = FavoritePokemonSelection(
                                    dexNumber: item.nationalDexNumber,
                                    name: item.displayName,
                                    imageURL: AppConfiguration.pokemonArtURL(imageFileName: item.imageUrl).absoluteString
                                )
                                dismiss()
                            } label: {
                                pokemonCell(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .searchable(text: $query, prompt: "Search Pokémon")
            }
        }
        .navigationTitle("Favorite Pokémon")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(.primary)
                    .fontWeight(.bold)
            }
        }
        .task {
            isLoading = true
            if services.cardData.nationalDexPokemon.isEmpty {
                await services.cardData.loadNationalDexPokemon()
            }
            rows = services.cardData.nationalDexPokemonSorted()
            isLoading = false
        }
    }

    private func pokemonCell(item: NationalDexPokemon) -> some View {
        VStack(spacing: 6) {
            CachedAsyncImage(url: AppConfiguration.pokemonArtURL(imageFileName: item.imageUrl)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Color.gray.opacity(0.12)
            }
            .frame(height: 130)
            Text(item.displayName)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
            Text("#\(item.nationalDexNumber)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.gray.opacity(0.1)))
    }
}

private struct FavoriteCardPickerView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: FavoriteCardSelection?

    @State private var cards: [Card] = []
    @State private var isLoading = true
    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    private var filteredCards: [Card] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return cards }
        return cards.filter {
            $0.cardName.lowercased().contains(trimmed)
            || $0.cardNumber.lowercased().contains(trimmed)
            || $0.setCode.lowercased().contains(trimmed)
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading cards…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredCards) { card in
                            Button {
                                selection = FavoriteCardSelection(
                                    cardID: card.masterCardId,
                                    cardName: card.cardName,
                                    setCode: card.setCode,
                                    imageURL: AppConfiguration.imageURL(relativePath: card.imageLowSrc).absoluteString
                                )
                                dismiss()
                            } label: {
                                CardGridCell(
                                    card: card,
                                    gridOptions: BrowseGridOptions()
                                )
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.gray.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .searchable(text: $query, prompt: "Search cards")
            }
        }
        .navigationTitle("Favorite Card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(.primary)
                    .fontWeight(.bold)
            }
        }
        .task {
            isLoading = true
            cards = await services.cardData.loadAllCards()
            isLoading = false
        }
    }

}
