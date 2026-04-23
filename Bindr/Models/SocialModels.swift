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
    let avatarBackgroundColor: String?
    let avatarOutlineStyle: String?
    let collectionCardCount: Int?
    let collectionBinderCount: Int?
    let collectionTotalValue: Double?
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
        case avatarBackgroundColor = "avatar_background_color"
        case avatarOutlineStyle = "avatar_outline_style"
        case collectionCardCount = "collection_card_count"
        case collectionBinderCount = "collection_binder_count"
        case collectionTotalValue = "collection_total_value"
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

enum ReactionType: String, Codable, Sendable, CaseIterable {
    case like
    case fire
    case wow

    var systemImage: String {
        switch self {
        case .like: return "hand.thumbsup.fill"
        case .fire: return "flame.fill"
        case .wow: return "sparkles"
        }
    }
}

struct Reaction: Codable, Identifiable, Sendable {
    let id: UUID
    let contentID: UUID
    let userID: UUID
    let reactionType: ReactionType
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case contentID = "content_id"
        case userID = "user_id"
        case reactionType = "reaction_type"
        case createdAt = "created_at"
    }
}

struct Comment: Codable, Identifiable, Sendable {
    let id: UUID
    let contentID: UUID
    let authorID: UUID
    let parentID: UUID?
    let body: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case contentID = "content_id"
        case authorID = "author_id"
        case parentID = "parent_id"
        case body
        case createdAt = "created_at"
    }
}

struct WishlistMatch: Codable, Identifiable, Sendable {
    let id: UUID
    let contentID: UUID
    let cardID: String
    let senderID: UUID
    let seen: Bool
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case contentID = "content_id"
        case cardID = "card_id"
        case senderID = "sender_id"
        case seen
        case createdAt = "created_at"
    }
}

enum FriendshipStatus: String, Codable, Sendable {
    case pending
    case accepted
    case blocked
}

struct Friendship: Codable, Identifiable, Sendable {
    let id: UUID
    let requesterID: UUID
    let addresseeID: UUID
    let status: FriendshipStatus
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case requesterID = "requester_id"
        case addresseeID = "addressee_id"
        case status
        case createdAt = "created_at"
    }
}

enum SharedContentType: String, Codable, Sendable, CaseIterable {
    case binder
    case wishlist
    case deck
}

enum SharedContentVisibility: String, Codable, Sendable, CaseIterable {
    case friends
    case link
}

struct SharedContent: Codable, Identifiable, Sendable {
    let id: UUID
    let ownerID: UUID
    let contentType: SharedContentType
    let title: String
    let description: String?
    let visibility: SharedContentVisibility
    let payload: [String: JSONValue]
    let includeValue: Bool
    let cardCount: Int?
    let brand: String?
    let publishedAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case contentType = "content_type"
        case title
        case description
        case visibility
        case payload
        case includeValue = "include_value"
        case cardCount = "card_count"
        case brand
        case publishedAt = "published_at"
        case updatedAt = "updated_at"
    }

    var localContentID: String? {
        payload["local_content_id"]?.stringValue
    }
}

extension JSONValue: @unchecked Sendable {}

extension JSONValue {
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}
