import Foundation
import Observation

@Observable
@MainActor
final class SocialFeedService {
    enum SocialFeedError: LocalizedError {
        case notSignedIn
        case missingConfiguration
        case invalidResponse
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "Sign in first to use the social feed."
            case .missingConfiguration:
                return "Supabase social config is missing from Info.plist."
            case .invalidResponse:
                return "Could not parse feed data from Supabase."
            case .requestFailed(let message):
                return message
            }
        }
    }

    enum FeedItemType: String, Sendable {
        case sharedContent
        case vote
        case comment
        case friendship
        case wishlistMatch
        case pull
        case dailyDigest = "daily_digest"
    }

    enum FeedScope: String, Sendable {
        case following
        case everyone
        case mine
    }

    struct FeedContentSummary: Identifiable, Sendable {
        let id: UUID
        let ownerID: UUID
        let title: String
        let contentType: SharedContentType
        let description: String?
        let cardCount: Int?
        let brand: String?
    }

    struct FeedItem: Identifiable, Sendable {
        let id: String
        let type: FeedItemType
        let createdAt: Date
        let actor: SocialProfile?
        let content: FeedContentSummary?
        let voteType: ReactionType?
        let commentBody: String?
        let friendshipID: UUID?
        let wishlistCardID: String?

        // Pull metadata
        let pullCardID: String?
        let pullCardName: String?
        let pullSetName: String?
        let pullValue: Double?
        let pullRarity: String?

        // Daily Digest metadata
        let digestCollectionCount: Int?
        let digestWishlistCount: Int?
        let digestThumbnails: [String]?

        // Binder styling (from shared_content payload)
        let binderColour: String?
        let binderTexture: String?
        let binderSeed: Int?
    }

    struct CommentDisplay: Identifiable, Sendable {
        let id: UUID
        let comment: Comment
        let author: SocialProfile?
        let depth: Int
    }

    struct VoteAggregate: Sendable {
        var upvoteCount: Int
        var downvoteCount: Int
        var myVoteType: ReactionType?

        var score: Int { upvoteCount - downvoteCount }
    }

    private struct APIErrorPayload: Decodable {
        let message: String?
        let hint: String?
    }

    private struct ContentReferenceRow: Decodable {
        let contentID: UUID

        enum CodingKeys: String, CodingKey {
            case contentID = "content_id"
        }
    }

    private struct SharedContentFeedRow: Decodable {
        let id: UUID
        let ownerID: UUID
        let contentType: SharedContentType
        let title: String
        let description: String?
        let payload: [String: JSONValue]?
        let cardCount: Int?
        let brand: String?
        let publishedAt: Date?
        let actor: SocialProfile?

        enum CodingKeys: String, CodingKey {
            case id
            case ownerID = "owner_id"
            case contentType = "content_type"
            case title
            case description
            case payload
            case cardCount = "card_count"
            case brand
            case publishedAt = "published_at"
            case actor
        }
    }

    private struct VoteFeedRow: Decodable {
        let id: UUID
        let contentID: UUID
        let userID: UUID
        let voteType: ReactionType
        let createdAt: Date?
        let actor: SocialProfile?
        let content: EmbeddedContent?

        enum CodingKeys: String, CodingKey {
            case id
            case contentID = "content_id"
            case userID = "user_id"
            case voteType = "reaction_type"
            case createdAt = "created_at"
            case actor
            case content
        }
    }

    private struct CommentFeedRow: Decodable {
        let id: UUID
        let contentID: UUID
        let authorID: UUID
        let parentID: UUID?
        let body: String
        let createdAt: Date?
        let author: SocialProfile?
        let content: EmbeddedContent?

        enum CodingKeys: String, CodingKey {
            case id
            case contentID = "content_id"
            case authorID = "author_id"
            case parentID = "parent_id"
            case body
            case createdAt = "created_at"
            case author
            case content
        }
    }

    private struct FriendshipFeedRow: Decodable {
        let id: UUID
        let requesterID: UUID
        let addresseeID: UUID
        let status: FriendshipStatus
        let createdAt: Date?
        let requester: SocialProfile?
        let addressee: SocialProfile?

        enum CodingKeys: String, CodingKey {
            case id
            case requesterID = "requester_id"
            case addresseeID = "addressee_id"
            case status
            case createdAt = "created_at"
            case requester
            case addressee
        }
    }

    private struct WishlistMatchFeedRow: Decodable {
        let id: UUID
        let contentID: UUID
        let cardID: String
        let senderID: UUID
        let createdAt: Date?
        let sender: SocialProfile?
        let content: EmbeddedContent?

        enum CodingKeys: String, CodingKey {
            case id
            case contentID = "content_id"
            case cardID = "card_id"
            case senderID = "sender_id"
            case matcherID = "matcher_id"
            case createdAt = "created_at"
            case sender
            case matcher
            case content
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            contentID = try container.decode(UUID.self, forKey: .contentID)
            cardID = try container.decode(String.self, forKey: .cardID)
            if let senderID = try? container.decode(UUID.self, forKey: .senderID) {
                self.senderID = senderID
            } else {
                self.senderID = try container.decode(UUID.self, forKey: .matcherID)
            }
            createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
            content = try container.decodeIfPresent(EmbeddedContent.self, forKey: .content)
            sender = (try? container.decodeIfPresent(SocialProfile.self, forKey: .sender))
                ?? (try? container.decodeIfPresent(SocialProfile.self, forKey: .matcher))
        }
    }

    private struct EmbeddedContent: Decodable {
        let id: UUID
        let ownerID: UUID
        let title: String
        let contentType: SharedContentType
        let description: String?
        let cardCount: Int?
        let brand: String?

        enum CodingKeys: String, CodingKey {
            case id
            case ownerID = "owner_id"
            case title
            case contentType = "content_type"
            case description
            case cardCount = "card_count"
            case brand
        }
    }

    private struct VoteInsertRequest: Encodable {
        let contentID: UUID
        let userID: UUID
        let voteType: ReactionType

        enum CodingKeys: String, CodingKey {
            case contentID = "content_id"
            case userID = "user_id"
            case voteType = "reaction_type"
        }
    }

    private struct CommentInsertRequest: Encodable {
        let contentID: UUID
        let authorID: UUID
        let parentID: UUID?
        let body: String

        enum CodingKeys: String, CodingKey {
            case contentID = "content_id"
            case authorID = "author_id"
            case parentID = "parent_id"
            case body
        }
    }

    private let authService: SocialAuthService
    private let friendService: SocialFriendService
    private var baseURL: URL? { AppConfiguration.supabaseURL }
    private var publishableKey: String { AppConfiguration.supabasePublishableKey }

    private(set) var items: [FeedItem] = []
    private(set) var unreadCount = 0

    private var cursorDate: Date?
    private let feedSeenStorageKeyPrefix = "social.feed.seen.ids"
    private let maxLocalSeenIDs = 500

    init(authService: SocialAuthService, friendService: SocialFriendService) {
        self.authService = authService
        self.friendService = friendService
    }

    var hasUnread: Bool {
        unreadCount > 0
    }

    func fetchFeed(refresh: Bool = true, pageSize: Int = 20, scope: FeedScope = .following) async throws -> [FeedItem] {
        if refresh {
            cursorDate = nil
        }
        let currentUserID = try signedInUserID()
        let beforeDate = refresh ? nil : cursorDate
        let blockedUserIDs = try await fetchBlockedUserIDs()
        let fetched = try await fetchCompositePage(
            before: beforeDate,
            limit: pageSize,
            currentUserID: currentUserID,
            blockedUserIDs: blockedUserIDs,
            scope: scope,
            includeActivityRows: false
        )
        
        // Filter out "notification" style items from the main Everyone feed
        let filtered = fetched.filter { item in
            switch item.type {
            case .vote, .comment, .friendship, .wishlistMatch:
                return false
            default:
                return true
            }
        }

        if refresh {
            items = filtered
        } else {
            let existingIDs = Set(items.map(\.id))
            items.append(contentsOf: filtered.filter { !existingIDs.contains($0.id) })
            items.sort { $0.createdAt > $1.createdAt }
        }

        cursorDate = items.last?.createdAt
        recalculateUnread()
        return items
    }

    /// Fetches activity for a specific user (defaults to current user) without updating the main feed's state.
    func fetchUserActivity(limit: Int = 20) async throws -> [FeedItem] {
        let currentUserID = try signedInUserID()
        let blockedUserIDs = try await fetchBlockedUserIDs()
        return try await fetchCompositePage(
            before: nil,
            limit: limit,
            currentUserID: currentUserID,
            blockedUserIDs: blockedUserIDs,
            scope: .mine,
            includeActivityRows: true
        )
    }

    func fetchActivityForUser(userID: UUID, limit: Int = 20) async throws -> [FeedItem] {
        let currentUserID = try signedInUserID()
        let path = "/rest/v1/shared_content?select=id,owner_id,content_type,title,description,card_count,brand,payload,published_at,actor:owner_id(id,username,display_name,avatar_url,avatar_background_color,avatar_outline_style,favorite_pokemon_dex,favorite_pokemon_image_url)&order=published_at.desc&limit=\(limit)&owner_id=eq.\(userID.uuidString)"
        let rows: [SharedContentFeedRow] = try await execute(path: path, method: "GET", accessToken: try signedInAccessToken())
        let blockedUserIDs = try await fetchBlockedUserIDs()
        return rows.compactMap { row -> FeedItem? in
            guard let createdAt = row.publishedAt else { return nil }
            guard !blockedUserIDs.contains(row.ownerID) else { return nil }
            let content = FeedContentSummary(
                id: row.id,
                ownerID: row.ownerID,
                title: row.title,
                contentType: row.contentType,
                description: row.description,
                cardCount: row.cardCount,
                brand: row.brand
            )
            let type: FeedItemType = {
                switch row.contentType {
                case .pull: return .pull
                case .dailyDigest: return .dailyDigest
                default: return .sharedContent
                }
            }()
            return FeedItem(
                id: row.id.uuidString,
                type: type,
                createdAt: createdAt,
                actor: row.actor,
                content: content,
                voteType: nil,
                commentBody: nil,
                friendshipID: nil,
                wishlistCardID: nil,
                pullCardID: row.payload?["card_id"]?.stringValue,
                pullCardName: row.payload?["card_name"]?.stringValue,
                pullSetName: row.payload?["set_name"]?.stringValue,
                pullValue: nil,
                pullRarity: nil,
                digestCollectionCount: nil,
                digestWishlistCount: nil,
                digestThumbnails: nil,
                binderColour: nil,
                binderTexture: nil,
                binderSeed: nil
            )
        }
    }

    func loadMore(pageSize: Int = 20) async throws -> [FeedItem] {
        try await fetchFeed(refresh: false, pageSize: pageSize)
    }

    func clearUnreadState() {
        let existing = seenIDs()
        let merged = (existing + items.map(\.id)).suffix(maxLocalSeenIDs)
        UserDefaults.standard.set(Array(merged), forKey: seenStorageKey())
        recalculateUnread()
    }

    func postVote(type: ReactionType, to contentID: UUID) async throws {
        let payload = VoteInsertRequest(
            contentID: contentID,
            userID: try signedInUserID(),
            voteType: type
        )
        _ = try await execute(
            path: "/rest/v1/reactions?on_conflict=content_id,user_id",
            method: "POST",
            accessToken: try signedInAccessToken(),
            body: payload,
            extraHeaders: [
                "Prefer": "resolution=merge-duplicates,return=minimal"
            ]
        ) as EmptyResponse
    }

    func removeVote(from contentID: UUID) async throws {
        let userID = try signedInUserID()
        _ = try await execute(
            path: "/rest/v1/reactions?content_id=eq.\(contentID.uuidString)&user_id=eq.\(userID.uuidString)",
            method: "DELETE",
            accessToken: try signedInAccessToken(),
            extraHeaders: [
                "Prefer": "return=minimal"
            ]
        ) as EmptyResponse
    }

    func toggleVote(type: ReactionType, to contentID: UUID) async throws {
        let aggregate = try await fetchVoteAggregate(for: contentID)
        if aggregate.myVoteType == type {
            try await removeVote(from: contentID)
        } else {
            try await postVote(type: type, to: contentID)
        }
    }

    func fetchVoteAggregate(for contentID: UUID) async throws -> VoteAggregate {
        let rows: [Vote] = try await execute(
            path: "/rest/v1/reactions?select=*&content_id=eq.\(contentID.uuidString)",
            method: "GET",
            accessToken: try signedInAccessToken()
        )
        let currentUserID = try signedInUserID()
        var upvotes = 0
        var downvotes = 0
        var myVote: ReactionType?
        for row in rows {
            switch row.voteType {
            case .upvote:
                upvotes += 1
            case .downvote:
                downvotes += 1
            }
            if row.userID == currentUserID {
                myVote = row.voteType
            }
        }
        return VoteAggregate(upvoteCount: upvotes, downvoteCount: downvotes, myVoteType: myVote)
    }

    func fetchComments(for contentID: UUID) async throws -> [CommentDisplay] {
        let blockedUserIDs = try await fetchBlockedUserIDs()
        let rows: [CommentFeedRow] = try await execute(
            path: "/rest/v1/comments?select=id,content_id,author_id,parent_id,body,created_at,author:author_id(id,username,display_name,avatar_url,avatar_background_color,avatar_outline_style,favorite_pokemon_dex,favorite_pokemon_image_url)&content_id=eq.\(contentID.uuidString)&order=created_at.asc",
            method: "GET",
            accessToken: try signedInAccessToken()
        )
        let filtered = rows.filter { !blockedUserIDs.contains($0.authorID) }
        let byParent = Dictionary(grouping: filtered) { $0.parentID }
        var flattened: [CommentDisplay] = []
        flattenComments(parentID: nil, depth: 0, source: byParent, output: &flattened)
        return flattened
    }

    func fetchVotes(for contentID: UUID) async throws -> [FeedItem] {
        let rows: [VoteFeedRow] = try await execute(
            path: "/rest/v1/reactions?select=id,content_id,user_id,reaction_type,created_at,actor:user_id(id,username,display_name,avatar_url,avatar_background_color,avatar_outline_style,favorite_pokemon_dex,favorite_pokemon_image_url)&content_id=eq.\(contentID.uuidString)&order=created_at.desc",
            method: "GET",
            accessToken: try signedInAccessToken()
        )
        return rows.compactMap { row in
            guard let timestamp = row.createdAt else { return nil }
            return FeedItem(
                id: "vote-\(row.id.uuidString)",
                type: .vote,
                createdAt: timestamp,
                actor: row.actor,
                content: nil,
                voteType: row.voteType,
                commentBody: nil,
                friendshipID: nil,
                wishlistCardID: nil,
                pullCardID: nil,
                pullCardName: nil,
                pullSetName: nil,
                pullValue: nil,
                pullRarity: nil,
                digestCollectionCount: nil,
                digestWishlistCount: nil,
                digestThumbnails: nil,
                binderColour: nil,
                binderTexture: nil,
                binderSeed: nil
            )
        }
    }

    func fetchCommentCount(for contentID: UUID) async throws -> Int {
        let path = "/rest/v1/comments?select=id&content_id=eq.\(contentID.uuidString)"
        let rows: [[String: UUID]] = try await execute(
            path: path,
            method: "GET",
            accessToken: try signedInAccessToken()
        )
        return rows.count
    }

    func fetchContentID(forCommentID commentID: UUID) async throws -> UUID? {
        let path = "/rest/v1/comments?select=content_id&id=eq.\(commentID.uuidString)&limit=1"
        let rows: [ContentReferenceRow] = try await execute(
            path: path,
            method: "GET",
            accessToken: try signedInAccessToken()
        )
        return rows.first?.contentID
    }

    func fetchContentID(forWishlistMatchID matchID: UUID) async throws -> UUID? {
        let path = "/rest/v1/wishlist_matches?select=content_id&id=eq.\(matchID.uuidString)&limit=1"
        let rows: [ContentReferenceRow] = try await execute(
            path: path,
            method: "GET",
            accessToken: try signedInAccessToken()
        )
        return rows.first?.contentID
    }

    func postComment(body: String, parentID: UUID?, to contentID: UUID) async throws {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let payload = CommentInsertRequest(
            contentID: contentID,
            authorID: try signedInUserID(),
            parentID: parentID,
            body: trimmed
        )
        _ = try await execute(
            path: "/rest/v1/comments",
            method: "POST",
            accessToken: try signedInAccessToken(),
            body: payload,
            extraHeaders: [
                "Prefer": "return=minimal"
            ]
        ) as EmptyResponse
    }

    private func flattenComments(
        parentID: UUID?,
        depth: Int,
        source: [UUID?: [CommentFeedRow]],
        output: inout [CommentDisplay]
    ) {
        guard let rows = source[parentID] else { return }
        for row in rows {
            let comment = Comment(
                id: row.id,
                contentID: row.contentID,
                authorID: row.authorID,
                parentID: row.parentID,
                body: row.body,
                createdAt: row.createdAt
            )
            output.append(CommentDisplay(id: row.id, comment: comment, author: row.author, depth: min(depth, 2)))
            flattenComments(parentID: row.id, depth: depth + 1, source: source, output: &output)
        }
    }

    private func fetchCompositePage(
        before: Date?,
        limit: Int,
        currentUserID: UUID,
        blockedUserIDs: Set<UUID>,
        scope: FeedScope,
        includeActivityRows: Bool
    ) async throws -> [FeedItem] {
        let friends = try? await friendService.fetchFriends()
        let friendIDs = Set(friends?.map(\.id) ?? [])
        
        var merged: [FeedItem] = []
        let sharedRows = try await fetchSharedContentRows(before: before, limit: limit, scope: scope)
        merged.append(contentsOf: sharedRows.compactMap { row in
            guard let timestamp = row.publishedAt else { return nil }
            
            switch scope {
            case .following:
                guard friendIDs.contains(row.ownerID) else { return nil }
            case .everyone:
                break
            case .mine:
                guard row.ownerID == currentUserID else { return nil }
            }
            
            guard !blockedUserIDs.contains(row.ownerID) else { return nil }
            let content = FeedContentSummary(
                id: row.id,
                ownerID: row.ownerID,
                title: row.title,
                contentType: row.contentType,
                description: row.description,
                cardCount: row.cardCount,
                brand: row.brand
            )
            let type: FeedItemType = {
                switch row.contentType {
                case .pull: return .pull
                case .dailyDigest: return .dailyDigest
                default: return .sharedContent
                }
            }()
            
            return FeedItem(
                id: "shared-\(row.id.uuidString)",
                type: type,
                createdAt: timestamp,
                actor: row.actor,
                content: content,
                voteType: nil,
                commentBody: nil,
                friendshipID: nil,
                wishlistCardID: nil,
                pullCardID: row.payload?["card_id"]?.stringValue,
                pullCardName: row.payload?["card_name"]?.stringValue,
                pullSetName: row.payload?["set_name"]?.stringValue,
                pullValue: row.payload?["card_value"]?.doubleValue,
                pullRarity: row.payload?["rarity"]?.stringValue,
                digestCollectionCount: row.payload?["collection_count"]?.intValue,
                digestWishlistCount: row.payload?["wishlist_count"]?.intValue,
                digestThumbnails: row.payload?["thumbnails"]?.arrayValue?.compactMap { $0.stringValue },
                binderColour: row.payload?["colour"]?.stringValue,
                binderTexture: row.payload?["texture"]?.stringValue,
                binderSeed: row.payload?["seed"]?.intValue
            )
        })

        guard includeActivityRows else {
            merged.sort { $0.createdAt > $1.createdAt }
            return Array(merged.prefix(limit))
        }

        async let voteTask = fetchVoteRows(before: before, limit: limit, scope: scope)
        async let commentTask = fetchCommentRows(before: before, limit: limit, scope: scope)
        async let friendshipTask = fetchFriendshipRows(before: before, limit: limit, scope: scope, currentUserID: currentUserID)
        async let matchTask = fetchWishlistMatchRows(before: before, limit: limit, scope: scope)

        let voteRows = try await voteTask
        merged.append(contentsOf: voteRows.compactMap { (row) -> FeedItem? in
            guard let timestamp = row.createdAt, let content = row.content else { return nil }
            switch scope {
            case .following:
                guard friendIDs.contains(row.userID) else { return nil }
            case .everyone:
                break
            case .mine:
                guard row.userID == currentUserID else { return nil }
            }
            guard !blockedUserIDs.contains(row.userID) else { return nil }
            let summary = FeedContentSummary(
                id: content.id,
                ownerID: content.ownerID,
                title: content.title,
                contentType: content.contentType,
                description: content.description,
                cardCount: content.cardCount,
                brand: content.brand
            )
            return FeedItem(
                id: "vote-\(row.id.uuidString)",
                type: .vote,
                createdAt: timestamp,
                actor: row.actor,
                content: summary,
                voteType: row.voteType,
                commentBody: nil,
                friendshipID: nil,
                wishlistCardID: nil,
                pullCardID: nil,
                pullCardName: nil,
                pullSetName: nil,
                pullValue: nil,
                pullRarity: nil,
                digestCollectionCount: nil,
                digestWishlistCount: nil,
                digestThumbnails: nil,
                binderColour: nil,
                binderTexture: nil,
                binderSeed: nil
            )
        })


        let friendshipRows = try await friendshipTask
        merged.append(contentsOf: friendshipRows.compactMap { (row) -> FeedItem? in
            guard let timestamp = row.createdAt, row.status == .accepted else { return nil }
            let actor = row.requesterID == currentUserID ? row.addressee : row.requester
            let actorID = row.requesterID == currentUserID ? row.addresseeID : row.requesterID
            guard !blockedUserIDs.contains(actorID) else { return nil }
            return FeedItem(
                id: "friendship-\(row.id.uuidString)",
                type: .friendship,
                createdAt: timestamp,
                actor: actor,
                content: nil,
                voteType: nil,
                commentBody: nil,
                friendshipID: row.id,
                wishlistCardID: nil,
                pullCardID: nil,
                pullCardName: nil,
                pullSetName: nil,
                pullValue: nil,
                pullRarity: nil,
                digestCollectionCount: nil,
                digestWishlistCount: nil,
                digestThumbnails: nil,
                binderColour: nil,
                binderTexture: nil,
                binderSeed: nil
            )
        })

        let commentRows = try await commentTask
        merged.append(contentsOf: commentRows.compactMap { (row) -> FeedItem? in
            guard let timestamp = row.createdAt, let content = row.content else { return nil }
            switch scope {
            case .following:
                guard friendIDs.contains(row.authorID) else { return nil }
            case .everyone:
                break
            case .mine:
                guard row.authorID == currentUserID else { return nil }
            }
            guard !blockedUserIDs.contains(row.authorID) else { return nil }
            let summary = FeedContentSummary(
                id: content.id,
                ownerID: content.ownerID,
                title: content.title,
                contentType: content.contentType,
                description: content.description,
                cardCount: content.cardCount,
                brand: content.brand
            )
            return FeedItem(
                id: "comment-\(row.id.uuidString)",
                type: .comment,
                createdAt: timestamp,
                actor: row.author,
                content: summary,
                voteType: nil,
                commentBody: row.body,
                friendshipID: nil,
                wishlistCardID: nil,
                pullCardID: nil,
                pullCardName: nil,
                pullSetName: nil,
                pullValue: nil,
                pullRarity: nil,
                digestCollectionCount: nil,
                digestWishlistCount: nil,
                digestThumbnails: nil,
                binderColour: nil,
                binderTexture: nil,
                binderSeed: nil
            )
        })

        let matches = try await matchTask
        merged.append(contentsOf: matches.compactMap { (row) -> FeedItem? in
            guard let timestamp = row.createdAt, let content = row.content else { return nil }
            switch scope {
            case .following:
                guard friendIDs.contains(row.senderID) else { return nil }
            case .everyone:
                break
            case .mine:
                guard row.senderID == currentUserID else { return nil }
            }
            
            guard !blockedUserIDs.contains(row.senderID) else { return nil }
            let summary = FeedContentSummary(
                id: content.id,
                ownerID: content.ownerID,
                title: content.title,
                contentType: content.contentType,
                description: content.description,
                cardCount: content.cardCount,
                brand: content.brand
            )
            return FeedItem(
                id: "wishlist-\(row.id.uuidString)",
                type: .wishlistMatch,
                createdAt: timestamp,
                actor: row.sender,
                content: summary,
                voteType: nil,
                commentBody: nil,
                friendshipID: nil,
                wishlistCardID: row.cardID,
                pullCardID: nil,
                pullCardName: nil,
                pullSetName: nil,
                pullValue: nil,
                pullRarity: nil,
                digestCollectionCount: nil,
                digestWishlistCount: nil,
                digestThumbnails: nil,
                binderColour: nil,
                binderTexture: nil,
                binderSeed: nil
            )
        })

        merged.sort { $0.createdAt > $1.createdAt }
        return Array(merged.prefix(limit))
    }

    private func fetchSharedContentRows(before: Date?, limit: Int, scope: FeedScope) async throws -> [SharedContentFeedRow] {
        let beforeFilter = before.map { "&published_at=lt.\(iso8601String($0))" } ?? ""
        var path = "/rest/v1/shared_content?select=id,owner_id,content_type,title,description,card_count,brand,payload,published_at,actor:owner_id(id,username,display_name,avatar_url,avatar_background_color,avatar_outline_style,favorite_pokemon_dex,favorite_pokemon_image_url)&order=published_at.desc&limit=\(limit)\(beforeFilter)"
        
        if scope == .mine {
            let userID = try signedInUserID()
            path += "&owner_id=eq.\(userID.uuidString)"
        }
        
        return try await execute(path: path, method: "GET", accessToken: try signedInAccessToken())
    }

    private func fetchVoteRows(before: Date?, limit: Int, scope: FeedScope) async throws -> [VoteFeedRow] {
        let beforeFilter = before.map { "&created_at=lt.\(iso8601String($0))" } ?? ""
        var path = "/rest/v1/reactions?select=id,content_id,user_id,reaction_type,created_at,actor:user_id(id,username,display_name,avatar_url,avatar_background_color,avatar_outline_style,favorite_pokemon_dex,favorite_pokemon_image_url),content:content_id(id,owner_id,title,content_type,description,card_count,brand)&order=created_at.desc&limit=\(limit)\(beforeFilter)"
        
        if scope == .mine {
            let userID = try signedInUserID()
            path += "&user_id=eq.\(userID.uuidString)"
        }
        
        return try await execute(path: path, method: "GET", accessToken: try signedInAccessToken())
    }

    private func fetchCommentRows(before: Date?, limit: Int, scope: FeedScope) async throws -> [CommentFeedRow] {
        let beforeFilter = before.map { "&created_at=lt.\(iso8601String($0))" } ?? ""
        var path = "/rest/v1/comments?select=id,content_id,author_id,parent_id,body,created_at,author:author_id(id,username,display_name,avatar_url,avatar_background_color,avatar_outline_style,favorite_pokemon_dex,favorite_pokemon_image_url),content:content_id(id,owner_id,title,content_type,description,card_count,brand)&order=created_at.desc&limit=\(limit)\(beforeFilter)"
        
        if scope == .mine {
            let userID = try signedInUserID()
            path += "&author_id=eq.\(userID.uuidString)"
        }
        
        return try await execute(path: path, method: "GET", accessToken: try signedInAccessToken())
    }

    private func fetchFriendshipRows(before: Date?, limit: Int, scope: FeedScope, currentUserID: UUID) async throws -> [FriendshipFeedRow] {
        if scope == .mine { return [] } // Friendship events are mutual, usually not shown in "Mine"
        let beforeFilter = before.map { "&created_at=lt.\(iso8601String($0))" } ?? ""
        let path = "/rest/v1/friendships?select=id,requester_id,addressee_id,status,created_at,requester:requester_id(id,username,display_name,avatar_url,avatar_background_color,avatar_outline_style,favorite_pokemon_dex,favorite_pokemon_image_url),addressee:addressee_id(id,username,display_name,avatar_url,avatar_background_color,avatar_outline_style,favorite_pokemon_dex,favorite_pokemon_image_url)&status=eq.accepted&or=(requester_id.eq.\(currentUserID.uuidString),addressee_id.eq.\(currentUserID.uuidString))&order=created_at.desc&limit=\(limit)\(beforeFilter)"
        return try await execute(path: path, method: "GET", accessToken: try signedInAccessToken())
    }

    private func fetchWishlistMatchRows(before: Date?, limit: Int, scope: FeedScope) async throws -> [WishlistMatchFeedRow] {
        let beforeFilter = before.map { "&created_at=lt.\(iso8601String($0))" } ?? ""
        var path = "/rest/v1/wishlist_matches?select=id,content_id,card_id,sender_id,matcher_id,created_at,sender:sender_id(id,username,display_name,avatar_url,avatar_background_color,avatar_outline_style,favorite_pokemon_dex,favorite_pokemon_image_url),matcher:matcher_id(id,username,display_name,avatar_url,avatar_background_color,avatar_outline_style,favorite_pokemon_dex,favorite_pokemon_image_url),content:content_id(id,owner_id,title,content_type,description,card_count,brand)&order=created_at.desc&limit=\(limit)\(beforeFilter)"
        
        if scope == .mine {
            let userID = try signedInUserID()
            path += "&sender_id=eq.\(userID.uuidString)"
        }
        
        return try await execute(path: path, method: "GET", accessToken: try signedInAccessToken())
    }

    private func fetchBlockedUserIDs() async throws -> Set<UUID> {
        let myID = try signedInUserID()
        let path = "/rest/v1/friendships?select=requester_id,addressee_id,status&status=eq.blocked&or=(requester_id.eq.\(myID.uuidString),addressee_id.eq.\(myID.uuidString))"
        let rows: [Friendship] = try await execute(path: path, method: "GET", accessToken: try signedInAccessToken())
        var blocked = Set<UUID>()
        for row in rows where row.status == .blocked {
            if row.requesterID == myID {
                blocked.insert(row.addresseeID)
            } else if row.addresseeID == myID {
                blocked.insert(row.requesterID)
            }
        }
        return blocked
    }

    private func recalculateUnread() {
        let seen = seenIDs()
        unreadCount = items.filter { !seen.contains($0.id) }.count
    }

    private func seenIDs() -> Set<String> {
        let values = UserDefaults.standard.stringArray(forKey: seenStorageKey()) ?? []
        return Set(values)
    }

    private func seenStorageKey() -> String {
        let userID = (try? signedInUserID().uuidString) ?? "signed-out"
        return "\(feedSeenStorageKeyPrefix).\(userID)"
    }

    private func signedInUserID() throws -> UUID {
        switch authService.authState {
        case .signedOut:
            throw SocialFeedError.notSignedIn
        case .signedIn(let userID, _):
            return userID
        }
    }

    private func signedInAccessToken() throws -> String {
        guard let token = authService.accessToken, !token.isEmpty else {
            throw SocialFeedError.notSignedIn
        }
        return token
    }

    private func iso8601String(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func execute<T: Decodable>(
        path: String,
        method: String,
        accessToken: String,
        extraHeaders: [String: String] = [:]
    ) async throws -> T {
        try await execute(path: path, method: method, accessToken: accessToken, body: Optional<String>.none, extraHeaders: extraHeaders)
    }

    private func execute<T: Decodable, Body: Encodable>(
        path: String,
        method: String,
        accessToken: String,
        body: Body?,
        extraHeaders: [String: String] = [:]
    ) async throws -> T {
        guard let baseURL, !publishableKey.isEmpty else {
            throw SocialFeedError.missingConfiguration
        }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw SocialFeedError.invalidResponse
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        for (header, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }
        if let body {
            request.httpBody = try JSONEncoder.socialJSON.encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SocialFeedError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let payload = try? JSONDecoder.socialJSON.decode(APIErrorPayload.self, from: data) {
                throw SocialFeedError.requestFailed(payload.message ?? payload.hint ?? "Supabase request failed with status \(http.statusCode).")
            }
            throw SocialFeedError.requestFailed("Supabase request failed with status \(http.statusCode).")
        }

        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }
        if data.isEmpty {
            throw SocialFeedError.invalidResponse
        }
        return try JSONDecoder.socialJSON.decode(T.self, from: data)
    }

    static func shortRelativeDate(_ date: Date) -> String {
        let now = Date()
        let diff = now.timeIntervalSince(date)
        
        if diff < 60 {
            return "Just now"
        } else if diff < 3600 {
            let mins = Int(diff / 60)
            return "\(mins)m"
        } else if diff < 86400 {
            let hours = Int(diff / 3600)
            return "\(hours)h"
        } else if diff < 604800 {
            let days = Int(diff / 86400)
            return "\(days)d"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}

private struct EmptyResponse: Decodable {}

private extension JSONDecoder {
    static var socialJSON: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var socialJSON: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
