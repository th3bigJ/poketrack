import SwiftUI

struct MyProfileView: View {
    let profile: SocialProfile
    let onEditTapped: () -> Void
    let onSignOutTapped: () -> Void

    private var roleTitles: [String] {
        (profile.profileRoles ?? []).map { role in
            switch role {
            case "collector": return "Collector"
            case "tcg_player": return "TCG Player"
            default: return role.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("@\(profile.username)")
                        .font(.headline)
                    if let displayName = profile.displayName, !displayName.isEmpty {
                        Text(displayName)
                            .font(.title3.weight(.semibold))
                    }
                    if let bio = profile.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("Your Social Profile")
            }

            if !roleTitles.isEmpty {
                Section("Profile type") {
                    HStack(spacing: 8) {
                        ForEach(roleTitles, id: \.self) { title in
                            Text(title)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(uiColor: .tertiarySystemFill))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Favorites") {
                if let pokemonName = profile.favoritePokemonName, !pokemonName.isEmpty {
                    HStack(spacing: 10) {
                        if let imageURL = profile.favoritePokemonImageURL,
                           let url = URL(string: imageURL) {
                            CachedAsyncImage(url: url) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                Color.gray.opacity(0.12)
                            }
                            .frame(width: 38, height: 38)
                        } else {
                            Image(systemName: "hare")
                                .foregroundStyle(.secondary)
                                .frame(width: 38, height: 38)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Favorite Pokémon")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            let dexLabel = profile.favoritePokemonDex.map { " #\($0)" } ?? ""
                            Text("\(pokemonName)\(dexLabel)")
                        }
                    }
                }

                if let cardName = profile.favoriteCardName, !cardName.isEmpty {
                    HStack(spacing: 10) {
                        if let imageURL = profile.favoriteCardImageURL,
                           let url = URL(string: imageURL) {
                            CachedAsyncImage(url: url) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                Color.gray.opacity(0.12)
                            }
                            .frame(width: 28, height: 40)
                        } else {
                            Image(systemName: "rectangle.stack.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 40)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Favorite Card")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(cardName)
                            if let setCode = profile.favoriteCardSetCode, !setCode.isEmpty {
                                Text(setCode)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let archetype = profile.favoriteDeckArchetype, !archetype.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.horizontal.circle")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Favorite Deck Archetype")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(archetype)
                        }
                    }
                }

                if profile.favoritePokemonName == nil,
                   profile.favoriteCardName == nil,
                   (profile.favoriteDeckArchetype ?? "").isEmpty {
                    Text("No favorites set yet.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Edit Profile") {
                    onEditTapped()
                }
                Button("Sign Out", role: .destructive) {
                    onSignOutTapped()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("My Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}
