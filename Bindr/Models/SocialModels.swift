import Foundation

struct SocialProfile: Codable, Identifiable, Sendable {
    let id: UUID
    let appleUserID: String?
    let username: String
    let displayName: String?
    let avatarURL: String?
    let bio: String?
    let profileRoles: [String]?
    let favoritePokemonDex: Int?
    let favoritePokemonName: String?
    let favoritePokemonImageURL: String?
    let favoriteCardID: String?
    let favoriteCardName: String?
    let favoriteCardSetCode: String?
    let favoriteCardImageURL: String?
    let favoriteDeckArchetype: String?
    let pinnedCardID: String?
    let followerCount: Int?
    let isWishlistPublic: Bool?
    let wishlistCardIDs: [String]?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case appleUserID = "apple_user_id"
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case bio
        case profileRoles = "profile_roles"
        case favoritePokemonDex = "favorite_pokemon_dex"
        case favoritePokemonName = "favorite_pokemon_name"
        case favoritePokemonImageURL = "favorite_pokemon_image_url"
        case favoriteCardID = "favorite_card_id"
        case favoriteCardName = "favorite_card_name"
        case favoriteCardSetCode = "favorite_card_set_code"
        case favoriteCardImageURL = "favorite_card_image_url"
        case favoriteDeckArchetype = "favorite_deck_archetype"
        case pinnedCardID = "pinned_card_id"
        case followerCount = "follower_count"
        case isWishlistPublic = "is_wishlist_public"
        case wishlistCardIDs = "wishlist_card_ids"
        case createdAt = "created_at"
    }
}

struct NotificationPreferences: Codable, Sendable {
    let userID: UUID
    let friendRequests: Bool
    let friendAccepts: Bool
    let sharedContentPosts: Bool
    let comments: Bool
    let wishlistMatches: Bool
    let tradeUpdates: Bool
    let marketing: Bool
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case friendRequests = "friend_requests"
        case friendAccepts = "friend_accepts"
        case sharedContentPosts = "shared_content_posts"
        case comments
        case wishlistMatches = "wishlist_matches"
        case tradeUpdates = "trade_updates"
        case marketing
        case updatedAt = "updated_at"
    }
}

struct DeviceToken: Codable, Identifiable, Sendable {
    let id: UUID
    let userID: UUID
    let token: String
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case token
        case updatedAt = "updated_at"
    }
}
