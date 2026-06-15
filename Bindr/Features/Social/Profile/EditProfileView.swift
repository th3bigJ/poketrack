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
    let avatarBackgroundColor: String?
    let avatarOutlineStyle: String?
    let collectionCardCount: Int?
    let collectionBinderCount: Int?
    let collectionDeckCount: Int?
    let friendCount: Int?
    let collectionTotalValue: Double?
    let premiumBadgeStyle: String?
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
        case trader = "trader"
        case binderBuilder = "binder_builder"
        case deckBuilder = "deck_builder"
        case sealedCollector = "sealed_collector"
        case wishlistHunter = "wishlist_hunter"
        case grader = "grader"
        case shopOwner = "shop_owner"
        case tradeShowVendor = "trade_show_vendor"
        case casual = "casual"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .collector: return "Collector"
            case .tcgPlayer: return "TCG Player"
            case .trader: return "Trader"
            case .binderBuilder: return "Binder Builder"
            case .deckBuilder: return "Deck Builder"
            case .sealedCollector: return "Sealed Collector"
            case .wishlistHunter: return "Wishlist Hunter"
            case .grader: return "Grader"
            case .shopOwner: return "Shop Owner"
            case .tradeShowVendor: return "Trade Show Vendor"
            case .casual: return "Casual"
            }
        }
    }

    let existingProfile: SocialProfile?
    let onSignOutTapped: () -> Void
    let onSave: (SocialProfileFormPayload) async throws -> Void

    @State private var username: String
    @State private var displayName: String
    @State private var bio: String
    @State private var profileRoles: Set<ProfileRole>
    @State private var favoriteDeckArchetype: String
    @State private var favoritePokemon: FavoritePokemonSelection?
    @State private var favoriteCard: FavoriteCardSelection?
    @State private var showPokemonPicker = false
    @State private var showCardPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var avatarBackgroundColor: String?
    @State private var avatarOutlineStyle: String?
    @State private var premiumBadgeStyle: PremiumBadgeStyle

    init(
        existingProfile: SocialProfile?,
        onSignOutTapped: @escaping () -> Void,
        onSave: @escaping (SocialProfileFormPayload) async throws -> Void
    ) {
        self.existingProfile = existingProfile
        self.onSignOutTapped = onSignOutTapped
        self.onSave = onSave
        _username = State(initialValue: existingProfile?.username ?? "")
        _displayName = State(initialValue: existingProfile?.displayName ?? "")
        _bio = State(initialValue: existingProfile?.bio ?? "")
        _profileRoles = State(initialValue: Set((existingProfile?.profileRoles ?? []).compactMap(ProfileRole.init(rawValue:))))
        _favoriteDeckArchetype = State(initialValue: existingProfile?.favoriteDeckArchetype ?? "")
        _avatarBackgroundColor = State(initialValue: existingProfile?.avatarBackgroundColor)
        _avatarOutlineStyle = State(initialValue: existingProfile?.avatarOutlineStyle)
        _premiumBadgeStyle = State(initialValue: existingProfile?.badgeStyle ?? .pokeball)
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

    private var previewProfile: SocialProfile {
        SocialProfile(
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
            friendCount: 0,
            avatarBackgroundColor: avatarBackgroundColor,
            avatarOutlineStyle: avatarOutlineStyle,
            collectionCardCount: 0,
            collectionBinderCount: 0,
            collectionDeckCount: 0,
            collectionTotalValue: 0,
            createdAt: nil,
            isPremium: nil,
            premiumBadgeStyle: premiumBadgeStyle.rawValue
        )
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
                HStack(spacing: 14) {
                    ProfileAvatarView(profile: previewProfile, size: 72)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Profile preview" : displayName)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Choose a username below" : "@\(username)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("Updates as you customise your avatar.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Avatar Background")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6),
                        spacing: 10
                    ) {
                        ForEach(ThemeSettings.presetColors, id: \.self) { hex in
                            let isSelected = avatarBackgroundColor == hex
                            Button {
                                avatarBackgroundColor = hex
                                Haptics.lightImpact()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 36, height: 36)

                                    if isSelected {
                                        Circle()
                                            .stroke(Color.primary.opacity(0.92), lineWidth: 2)
                                            .frame(width: 36, height: 36)
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(.white)
                                            .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
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
                                    Haptics.lightImpact()
                                } label: {
                                    Text(name)
                                        .font(.system(size: 14, weight: .medium))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(avatarOutlineStyle == style ? services.theme.accentColor : Color.gray.opacity(0.1))
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

            // MARK: - Premium Badge Picker
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Profile Badge")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        ForEach(PremiumBadgeStyle.allCases, id: \.self) { style in
                            Button {
                                premiumBadgeStyle = style
                                Haptics.lightImpact()
                            } label: {
                                HStack(spacing: 8) {
                                    PokeballEmblemView(size: 22)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(style.displayName)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(style.gameHint)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if premiumBadgeStyle == style {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(services.theme.accentColor)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(premiumBadgeStyle == style
                                              ? services.theme.accentColor.opacity(0.12)
                                              : Color.gray.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(premiumBadgeStyle == style ? services.theme.accentColor : Color.clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("Premium Badge")
            } footer: {
                // Temp: visible to all for testing. Production: guard on isPremium.
                Text("Choose the badge that appears next to your name in the feed and on your profile.")
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
                Text("Choose the tags that best describe how you collect, trade, and play.")
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

            if existingProfile != nil {
                Section {
                    Button("Sign Out", role: .destructive) {
                        onSignOutTapped()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } footer: {
                    Text("Signing out will close this profile screen.")
                }
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
        let collectionCardCount = modelContext.collectionTotalCardQuantity()
        let collectionBinderCount = (try? modelContext.fetchCount(FetchDescriptor<Binder>())) ?? 0
        let collectionDeckCount = (try? modelContext.fetchCount(FetchDescriptor<Deck>())) ?? 0
        let collectionTotalValue = services.collectionValue?.snapshots.last?.totalGbp ?? 0
        let capturedUsername = resolvedUsername
        let capturedDisplayName = displayName
        let capturedBio = bio
        let capturedRoleValues = roleValues
        let capturedFavoritePokemon = favoritePokemon
        let capturedFavoriteCard = favoriteCard
        let capturedFavoriteDeckArchetype = favoriteDeckArchetype
        let capturedAvatarBg = avatarBackgroundColor
        let capturedAvatarOutline = avatarOutlineStyle
        let capturedBadgeStyle = premiumBadgeStyle.rawValue
        Task {
            do {
                let friendCount = try? await services.socialFriend.fetchFriends().count
                let payload = SocialProfileFormPayload(
                    username: capturedUsername,
                    displayName: capturedDisplayName,
                    bio: capturedBio,
                    profileRoles: capturedRoleValues,
                    favoritePokemonDex: capturedFavoritePokemon?.dexNumber,
                    favoritePokemonName: capturedFavoritePokemon?.name,
                    favoritePokemonImageURL: capturedFavoritePokemon?.imageURL,
                    favoriteCardID: capturedFavoriteCard?.cardID,
                    favoriteCardName: capturedFavoriteCard?.cardName,
                    favoriteCardSetCode: capturedFavoriteCard?.setCode,
                    favoriteCardImageURL: capturedFavoriteCard?.imageURL,
                    favoriteDeckArchetype: capturedFavoriteDeckArchetype,
                    avatarBackgroundColor: capturedAvatarBg,
                    avatarOutlineStyle: capturedAvatarOutline,
                    collectionCardCount: collectionCardCount,
                    collectionBinderCount: collectionBinderCount,
                    collectionDeckCount: collectionDeckCount,
                    friendCount: friendCount,
                    collectionTotalValue: collectionTotalValue,
                    premiumBadgeStyle: capturedBadgeStyle
                )
                try await onSave(payload)
            } catch {
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
    @Environment(\.colorScheme) private var colorScheme
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
                                    imageURL: AppConfiguration.imageURL(relativePath: card.displayImageSrc).absoluteString
                                )
                                dismiss()
                            } label: {
                                CardGridCell(
                                    card: card,
                                    services: services,
                                    colorScheme: colorScheme,
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
