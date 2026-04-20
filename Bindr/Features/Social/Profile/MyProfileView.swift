import SwiftUI
import SwiftData

struct MyProfileView: View {
    let profile: SocialProfile
    let onEditTapped: () -> Void
    let onSignOutTapped: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    @State private var cardCount: Int = 0
    @State private var binderCount: Int = 0
    @State private var totalValue: Double = 0
    @State private var favoriteCard: Card?
    @State private var favoriteCardPrice: Double?
    
    private var formattedTotalValue: String {
        let display = services.priceDisplay
        let currency = display.currency
        let symbol = currency.symbol
        let rate = currency == .usd ? 1.0 : services.pricing.usdToGbp
        
        // The snapshots are in GBP by default in CollectionValueService
        // but let's see if we can convert back if needed.
        // Actually, let's just use the GBP value and format it.
        let valueInGbp = services.collectionValue?.snapshots.last?.totalGbp ?? 0
        let valueInTarget = currency == .gbp ? valueInGbp : valueInGbp / services.pricing.usdToGbp * rate
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = symbol
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: valueInTarget)) ?? "\(symbol)0"
    }

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
        ScrollView {
            VStack(spacing: 24) {
                // 1. Hero Header
                ProfileHeroHeader(profile: profile, onEditTapped: onEditTapped)
                
                VStack(spacing: 24) {
                    // 2. Stats Row
                    ProfileStatsRow(
                        cardCount: cardCount,
                        totalValue: formattedTotalValue,
                        followerCount: profile.followerCount ?? 0,
                        binderCount: binderCount
                    )
                    
                    // 3. Profile Type Chips
                    if !roleTitles.isEmpty {
                        HStack(spacing: 10) {
                            ForEach(roleTitles, id: \.self) { title in
                                Text(title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05))
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
                                    )
                            }
                        }
                    }
                    
                    // 4. Favorites Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Favorites")
                                .font(.headline)
                            Spacer()
                            Button("Change") {
                                onEditTapped()
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.blue)
                        }
                        .padding(.horizontal, 20)
                        
                        VStack(spacing: 12) {
                            // Favorite Pokémon Tile
                            if let pokemonName = profile.favoritePokemonName {
                                favoritePokemonTile(name: pokemonName, dex: profile.favoritePokemonDex)
                            }
                            
                            // Favorite Card Tile
                            if let cardName = profile.favoriteCardName {
                                favoriteCardTile(name: cardName)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // 5. Public Wishlist Preview
                    if profile.isWishlistPublic == true, let wishlist = services.wishlist {
                        ProfileWishlistPreview(
                            cardIDs: wishlist.items.map(\.cardID),
                            onEditTapped: { /* Navigation to full wishlist */ },
                            cardLoader: { id in await services.cardData.loadCard(masterCardId: id) },
                            priceFormatter: { val in
                                let formatter = NumberFormatter()
                                formatter.numberStyle = .currency
                                formatter.currencySymbol = services.priceDisplay.currency == .gbp ? "£" : "$"
                                return formatter.string(from: NSNumber(value: val)) ?? "$0"
                            }
                        )
                    }
                    
                    // 6. Actions
                    VStack(spacing: 0) {
                        Button(action: onEditTapped) {
                            HStack {
                                Text("Edit Profile")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(colorScheme == .dark ? Color(hex: "1c1c1e") : .white)
                        }
                        
                        Divider().padding(.leading)
                        
                        Button(role: .destructive, action: onSignOutTapped) {
                            HStack {
                                Text("Sign Out")
                                Spacer()
                            }
                            .padding()
                            .background(colorScheme == .dark ? Color(hex: "1c1c1e") : .white)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .padding(.top, 20) // Space after hero header overlap
            }
        }
        .background(colorScheme == .dark ? Color.black : Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("My Profile")
                    .font(.headline)
            }
        }
        .task {
            fetchStats()
            if let cardID = profile.favoriteCardID {
                favoriteCard = await services.cardData.loadCard(masterCardId: cardID)
                if let card = favoriteCard {
                    favoriteCardPrice = await services.pricing.usdPrice(for: card, printing: "normal")
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private func favoritePokemonTile(name: String, dex: Int?) -> some View {
        HStack(spacing: 16) {
            // Icon/Sprite
            ZStack {
                Circle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                    .frame(width: 60, height: 60)
                
                if let urlString = profile.favoritePokemonImageURL, let url = URL(string: urlString) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView().scaleEffect(0.8)
                    }
                    .frame(width: 44, height: 44)
                } else {
                    Image(systemName: "hare.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(name)
                        .font(.system(size: 18, weight: .bold))
                    if let dex = dex {
                        Text("#\(String(format: "%03d", dex))")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Type Badges (Neutral Glass)
                HStack(spacing: 6) {
                    // We don't have types in the profile easily, 
                    // so we'll show "Pokémon" as a generic tag or try to derive if possible.
                    // For now, let's just show a glass tag as requested.
                    glassTag(text: "Pokémon")
                }
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05), lineWidth: 1)
                )
        )
    }
    
    private func favoriteCardTile(name: String) -> some View {
        HStack(spacing: 16) {
            // Card Thumbnail
            if let imageURL = profile.favoriteCardImageURL, let url = URL(string: imageURL) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.1)
                }
                .frame(width: 62, height: 87)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1)
                
                if let setCode = profile.favoriteCardSetCode {
                    Text(setCode)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                if let price = favoriteCardPrice {
                    Text(formattedValue(price))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.top, 2)
                }
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05), lineWidth: 1)
                )
        )
    }
    
    private func glassTag(text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05))
            )
            .overlay(
                Capsule()
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
            )
    }
    
    private func formattedValue(_ usd: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = services.priceDisplay.currency == .gbp ? "£" : "$"
        let val = services.priceDisplay.currency == .gbp ? usd * services.pricing.usdToGbp : usd
        return formatter.string(from: NSNumber(value: val)) ?? "$0"
    }

    // MARK: - Data Fetching
    
    private func fetchStats() {
        // Fetch Card Count
        let cardFetch = FetchDescriptor<CollectionItem>()
        cardCount = (try? modelContext.fetchCount(cardFetch)) ?? 0
        
        // Fetch Binder Count
        let binderFetch = FetchDescriptor<Binder>()
        binderCount = (try? modelContext.fetchCount(binderFetch)) ?? 0
        
        // Value is handled by totalValue computed property using services.collectionValue
    }
}
