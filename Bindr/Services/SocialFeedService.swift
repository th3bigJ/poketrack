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
        case reaction
        case comment
        case friendship
        case wishlistMatch
    }

    struct FeedContentSummary: Identifiable, Sendable {
        let id: UUID
        let ownerID: UUID
        let title: String
        let contentType: SharedContentType
    }

    struct FeedItem: Identifiable, Sendable {
        let id: String
        let type: FeedItemType
        let createdAt: Date
        let actor: SocialProfile?
        let content: FeedContentSummary?
        let reactionType: ReactionType?
        let commentBody: String?
        let friendshipID: UUID?
        let wishlistCardID: String?
    }

    struct CommentDisplay: Identifiable, Sendable {
        let id: UUID
        let comment: Comment
        let author: SocialProfile?
        let depth: Int
    }

    struct ReactionAggregate: Sendable {
        var totalCount: Int
        var byType: [ReactionType: Int]
        var myReactionType: ReactionType?
    }

    private struct APIErrorPayload: Decodable {
        let message: String?
        let hint: String?
    }

    private struct SharedContentFeedRow: Decodable {
        let id: UUID
        let ownerID: UUID
        let contentType: SharedContentType
        let title: String
        let publishedAt: Date?
        let actor: SocialProfile?

        enum CodingKeys: String, CodingKey {
            case id
            case ownerID = "owner_id"
            case contentType = "content_type"
            case title
            case publishedAt = "published_at"
            case actor
        }
    }

    private struct ReactionFeedRow: Decodable {
        let id: UUID
        let contentID: UUID
        let userID: UUID
        let reactionType: ReactionType
        let createdAt: Date?
        let actor: SocialProfile?
        let content: EmbeddedContent?

        enum CodingKeys: String, CodingKey {
            case id
            case contentID = "content_id"
            case userID = "user_id"
            case reactionType = "reaction_type"
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

        enum CodingKeys: String, CodingKey {
            case id
            case ownerID = "owner_id"
            case title
            case contentType = "content_type"
        }
    }

    private struct ReactionInsertRequest: Encodable {
        let contentID: UUID
        let userID: UUID
        let reactionType: ReactionType

        enum CodingKeys: String, CodingKey {
            case contentID = "content_id"
            case userID = "user_id"
            case reactionType = "reaction_type"
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
    private var baseURL: URL? { AppConfiguration.supabaseURL }
    private var publishableKey: String { AppConfiguration.supabasePublishableKey }

    private(set) var items: [FeedItem] = []
    private(set) var unreadCount = 0

    private var cursorDate: Date?
    private let feedSeenStorageKeyPrefix = "social.feed.seen.ids"
    private let maxLocalSeenIDs = 500

    init(authService: SocialAuthService) {
        self.authService = authService
    }

    var hasUnread: Bool {
        unreadCount > 0
    }

    func fetchFeed(refresh: Bool = true, pageSize: Int = 20) async throws -> [FeedItem] {
        if refresh {
            cursorDate = nil
        }
        let currentUserID = try signedInUserID()
        let beforeDate = refresh ? nil : cursorDate
        let blockedUserIDs = try await fetchBlockedUserIDs()
        let fetched = try await fetchCompositePage(before: beforeDate, limit: pageSize, currentUserID: currentUserID, blockedUserIDs: blockedUserIDs)

        if refresh {
            items = fetched
        } else {
            let existingIDs = Set(items.map(\.id))
            items.append(contentsOf: fetched.filter { !existingIDs.contains($0.id) })
            items.sort { $0.createdAt > $1.createdAt }
        }

        cursorDate = items.last?.createdAt
        recalculateUnread()
        return items
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

    func postReaction(type: ReactionType, to contentID: UUID) async throws {
        let payload = ReactionInsertRequest(
            contentID: contentID,
            userID: try signedInUserID(),
            reactionType: type
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

    func removeReaction(from contentID: UUID) async throws {
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

    func toggleReaction(type: ReactionType, to contentID: UUID) async throws {
        let aggregate = try await fetchReactionAggregate(for: contentID)
        if aggregate.myReactionType == type {
            try await removeReaction(from: contentID)
        } else {
            try await postReaction(type: type, to: contentID)
        }
    }

    func fetchReactionAggregate(for contentID: UUID) async throws -> ReactionAggregate {
        let rows: [Reaction] = try await execute(
            path: "/rest/v1/reactions?select=*&content_id=eq.\(contentID.uuidString)",
            method: "GET",
            accessToken: try signedInAccessToken()
        )
        let currentUserID = try signedInUserID()
        var byType: [ReactionType: Int] = [:]
        var myReaction: ReactionType?
        for row in rows {
            byType[row.reactionType, default: 0] += 1
            if row.userID == currentUserID {
                myReaction = row.reactionType
            }
        }
        return ReactionAggregate(totalCount: rows.count, byType: byType, myReactionType: myReaction)
    }

    func fetchComments(for contentID: UUID) async throws -> [CommentDisplay] {
        let blockedUserIDs = try await fetchBlockedUserIDs()
        let rows: [CommentFeedRow] = try await execute(
            path: "/rest/v1/comments?select=id,content_id,author_id,parent_id,body,created_at,author:author_id(id,username,display_name,avatar_url)&content_id=eq.\(contentID.uuidString)&order=created_at.asc",
            method: "GET",
            accessToken: try signedInAccessToken()
        )

        let filtered = rows.filter { !blockedUserIDs.contains($0.authorID) }
        let byParent = Dictionary(grouping: filtered) { $0.parentID }
        var flattened: [CommentDisplay] = []
        flattenComments(parentID: nil, depth: 0, source: byParent, output: &flattened)
        return flattened
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
        blockedUserIDs: Set<UUID>
    ) async throws -> [FeedItem] {
        async let sharedTask = fetchSharedContentRows(before: before, limit: limit)
        async let reactionTask = fetchReactionRows(before: before, limit: limit)
        async let commentTask = fetchCommentRows(before: before, limit: limit)
        async let friendshipTask = fetchFriendshipRows(before: before, limit: limit)
        async let matchTask = fetchWishlistMatchRows(before: before, limit: limit)

        var merged: [FeedItem] = []
        let sharedRows = try await sharedTask
        merged.append(contentsOf: sharedRows.compactMap { row in
            guard let timestamp = row.publishedAt else { return nil }
            guard row.ownerID != currentUserID else { return nil }
            guard !blockedUserIDs.contains(row.ownerID) else { return nil }
            let content = FeedContentSummary(id: row.id, ownerID: row.ownerID, title: row.title, contentType: row.contentType)
            return FeedItem(
                id: "shared-\(row.id.uuidString)",
                type: .sharedContent,
                createdAt: timestamp,
                actor: row.actor,
                content: content,
                reactionType: nil,
                commentBody: nil,
                friendshipID: nil,
                wishlistCardID: nil
            )
        })

        let reactionRows = try await reactionTask
        merged.append(contentsOf: reactionRows.compactMap { row in
            guard let timestamp = row.createdAt, let content = row.content else { return nil }
            guard row.userID != currentUserID else { return nil }
            guard !blockedUserIDs.contains(row.userID) else { return nil }
            let summary = FeedContentSummary(id: content.id, ownerID: content.ownerID, title: content.title, contentType: content.contentType)
            return FeedItem(
                id: "reaction-\(row.id.uuidString)",
                type: .reaction,
                createdAt: timestamp,
                actor: row.actor,
                content: summary,
                reactionType: row.reactionType,
                commentBody: nil,
                friendshipID: nil,
                wishlistCardID: nil
            )
        })

        let commentRows = try await commentTask
        merged.append(contentsOf: commentRows.compactMap { row in
            guard let timestamp = row.createdAt, let content = row.content else { return nil }
            guard row.authorID != currentUserID else { return nil }
            guard !blockedUserIDs.contains(row.authorID) else { return nil }
            let summary = FeedContentSummary(id: content.id, ownerID: content.ownerID, title: content.title, contentType: content.contentType)
            return FeedItem(
                id: "comment-\(row.id.uuidString)",
                type: .comment,
                createdAt: timestamp,
                actor: row.author,
                content: summary,
                reactionType: nil,
                commentBody: row.body,
                friendshipID: nil,
                wishlistCardID: nil
            )
        })

        let friendshipRows = try await friendshipTask
        merged.append(contentsOf: friendshipRows.compactMap { row in
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
                reactionType: nil,
                commentBody: nil,
                friendshipID: row.id,
                wishlistCardID: nil
            )
        })

        let matches = try await matchTask
        merged.append(contentsOf: matches.compactMap { row in
            guard let timestamp = row.createdAt, let content = row.content else { return nil }
            guard row.senderID != currentUserID else { return nil }
            guard !blockedUserIDs.contains(row.senderID) else { return nil }
            let summary = FeedContentSummary(id: content.id, ownerID: content.ownerID, title: content.title, contentType: content.contentType)
            return FeedItem(
                id: "wishlist-\(row.id.uuidString)",
                type: .wishlistMatch,
                createdAt: timestamp,
                actor: row.sender,
                content: summary,
                reactionType: nil,
                commentBody: nil,
                friendshipID: nil,
                wishlistCardID: row.cardID
            )
        })

        merged.sort { $0.createdAt > $1.createdAt }
        return Array(merged.prefix(limit))
    }

    private func fetchSharedContentRows(before: Date?, limit: Int) async throws -> [SharedContentFeedRow] {
        let beforeFilter = before.map { "&published_at=lt.\(iso8601String($0))" } ?? ""
        let path = "/rest/v1/shared_content?select=id,owner_id,content_type,title,published_at,actor:owner_id(id,username,display_name,avatar_url)&order=published_at.desc&limit=\(limit)\(beforeFilter)"
        return try await execute(path: path, method: "GET", accessToken: try signedInAccessToken())
    }

    private func fetchReactionRows(before: Date?, limit: Int) async throws -> [ReactionFeedRow] {
        let beforeFilter = before.map { "&created_at=lt.\(iso8601String($0))" } ?? ""
        let path = "/rest/v1/reactions?select=id,content_id,user_id,reaction_type,created_at,actor:user_id(id,username,display_name,avatar_url),content:content_id(id,owner_id,title,content_type)&order=created_at.desc&limit=\(limit)\(beforeFilter)"
        return try await execute(path: path, method: "GET", accessToken: try signedInAccessToken())
    }

    private func fetchCommentRows(before: Date?, limit: Int) async throws -> [CommentFeedRow] {
        let beforeFilter = before.map { "&created_at=lt.\(iso8601String($0))" } ?? ""
        let path = "/rest/v1/comments?select=id,content_id,author_id,parent_id,body,created_at,author:author_id(id,username,display_name,avatar_url),content:content_id(id,owner_id,title,content_type)&order=created_at.desc&limit=\(limit)\(beforeFilter)"
        return try await execute(path: path, method: "GET", accessToken: try signedInAccessToken())
    }

    private func fetchFriendshipRows(before: Date?, limit: Int) async throws -> [FriendshipFeedRow] {
        let userID = try signedInUserID()
        let beforeFilter = before.map { "&created_at=lt.\(iso8601String($0))" } ?? ""
        let path = "/rest/v1/friendships?select=id,requester_id,addressee_id,status,created_at,requester:requester_id(id,username,display_name,avatar_url),addressee:addressee_id(id,username,display_name,avatar_url)&status=eq.accepted&or=(requester_id.eq.\(userID.uuidString),addressee_id.eq.\(userID.uuidString))&order=created_at.desc&limit=\(limit)\(beforeFilter)"
        return try await execute(path: path, method: "GET", accessToken: try signedInAccessToken())
    }

    private func fetchWishlistMatchRows(before: Date?, limit: Int) async throws -> [WishlistMatchFeedRow] {
        let beforeFilter = before.map { "&created_at=lt.\(iso8601String($0))" } ?? ""
        let path = "/rest/v1/wishlist_matches?select=id,content_id,card_id,sender_id,matcher_id,created_at,sender:sender_id(id,username,display_name,avatar_url),matcher:matcher_id(id,username,display_name,avatar_url),content:content_id(id,owner_id,title,content_type)&order=created_at.desc&limit=\(limit)\(beforeFilter)"
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

        var request = URLRequest(url: url)
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
