import Foundation
import Observation

@Observable
@MainActor
final class SocialFriendService {
    enum SocialFriendError: LocalizedError {
        case notSignedIn
        case missingConfiguration
        case invalidResponse
        case invalidRequest
        case freeTierLimitReached
        case blocked
        case alreadyFriends
        case requestAlreadyPending
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "Sign in first to use friends."
            case .missingConfiguration:
                return "Supabase social config is missing from Info.plist."
            case .invalidResponse:
                return "Could not parse friend data from Supabase."
            case .invalidRequest:
                return "This friend action is not allowed."
            case .freeTierLimitReached:
                return "Free tier allows one total pending or accepted friend. Upgrade to Premium for unlimited friends."
            case .blocked:
                return "This user is blocked, so friend requests are disabled."
            case .alreadyFriends:
                return "You are already friends with this user."
            case .requestAlreadyPending:
                return "A friend request is already pending."
            case .requestFailed(let message):
                return message
            }
        }
    }

    struct FriendSearchResult: Identifiable, Sendable {
        let profile: SocialProfile
        let relationship: RelationshipState

        var id: UUID { profile.id }
    }

    struct IncomingFriendRequest: Identifiable, Sendable {
        let friendship: Friendship
        let requester: SocialProfile

        var id: UUID { friendship.id }
    }

    struct OutgoingFriendRequest: Identifiable, Sendable {
        let friendship: Friendship
        let addressee: SocialProfile

        var id: UUID { friendship.id }
    }

    enum RelationshipState: Hashable, Sendable {
        case none
        case pendingIncoming(friendshipID: UUID)
        case pendingOutgoing(friendshipID: UUID)
        case friends
        case blocked
    }

    private struct FriendshipWithProfiles: Decodable {
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

    private struct InsertFriendshipRequest: Encodable {
        let requesterID: UUID
        let addresseeID: UUID
        let status: FriendshipStatus

        enum CodingKeys: String, CodingKey {
            case requesterID = "requester_id"
            case addresseeID = "addressee_id"
            case status
        }
    }

    private struct PatchFriendshipStatusRequest: Encodable {
        let status: FriendshipStatus
    }

    private struct APIErrorPayload: Decodable {
        let message: String?
        let hint: String?
    }

    private let authService: SocialAuthService
    private let storeService: StoreKitService
    private var baseURL: URL? { AppConfiguration.supabaseURL }
    private var publishableKey: String { AppConfiguration.supabasePublishableKey }

    private(set) var queuedProfileUsername: String?

    init(authService: SocialAuthService, storeService: StoreKitService) {
        self.authService = authService
        self.storeService = storeService
    }

    func fetchFriends() async throws -> [SocialProfile] {
        let currentUserID = try signedInUserID()
        let rows: [FriendshipWithProfiles] = try await execute(
            path: "/rest/v1/friendships?select=id,requester_id,addressee_id,status,created_at,requester:requester_id(id,username,display_name,avatar_url,favorite_pokemon_dex,favorite_pokemon_image_url),addressee:addressee_id(id,username,display_name,avatar_url,favorite_pokemon_dex,favorite_pokemon_image_url)&status=eq.accepted&or=(requester_id.eq.\(currentUserID.uuidString),addressee_id.eq.\(currentUserID.uuidString))&order=created_at.desc",
            method: "GET",
            accessToken: try signedInAccessToken()
        )

        return rows.compactMap { row in
            if row.requesterID == currentUserID {
                return row.addressee
            }
            return row.requester
        }
    }

    func fetchPendingRequests() async throws -> [IncomingFriendRequest] {
        let currentUserID = try signedInUserID()
        let rows: [FriendshipWithProfiles] = try await execute(
            path: "/rest/v1/friendships?select=id,requester_id,addressee_id,status,created_at,requester:requester_id(id,username,display_name,avatar_url,favorite_pokemon_dex,favorite_pokemon_image_url),addressee:addressee_id(id,username,display_name,avatar_url,favorite_pokemon_dex,favorite_pokemon_image_url)&status=eq.pending&addressee_id=eq.\(currentUserID.uuidString)&order=created_at.desc",
            method: "GET",
            accessToken: try signedInAccessToken()
        )

        return rows.compactMap { row in
            guard let requester = row.requester else { return nil }
            let friendship = Friendship(
                id: row.id,
                requesterID: row.requesterID,
                addresseeID: row.addresseeID,
                status: row.status,
                createdAt: row.createdAt
            )
            return IncomingFriendRequest(friendship: friendship, requester: requester)
        }
    }

    func fetchOutgoingPendingRequests() async throws -> [OutgoingFriendRequest] {
        let currentUserID = try signedInUserID()
        let rows: [FriendshipWithProfiles] = try await execute(
            path: "/rest/v1/friendships?select=id,requester_id,addressee_id,status,created_at,requester:requester_id(id,username,display_name,avatar_url,favorite_pokemon_dex,favorite_pokemon_image_url),addressee:addressee_id(id,username,display_name,avatar_url,favorite_pokemon_dex,favorite_pokemon_image_url)&status=eq.pending&requester_id=eq.\(currentUserID.uuidString)&order=created_at.desc",
            method: "GET",
            accessToken: try signedInAccessToken()
        )

        return rows.compactMap { row in
            guard let addressee = row.addressee else { return nil }
            let friendship = Friendship(
                id: row.id,
                requesterID: row.requesterID,
                addresseeID: row.addresseeID,
                status: row.status,
                createdAt: row.createdAt
            )
            return OutgoingFriendRequest(friendship: friendship, addressee: addressee)
        }
    }

    func searchUsers(query: String) async throws -> [FriendSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let currentUserID = try signedInUserID()
        let accessToken = try signedInAccessToken()
        let encodedQuery = encodedQueryValue(trimmed.replacingOccurrences(of: ",", with: ""))
        let queryPattern = "%\(encodedQuery)%"
        let profiles: [SocialProfile] = try await execute(
            path: "/rest/v1/profiles?select=*&username=ilike.\(queryPattern)&order=username.asc&limit=25",
            method: "GET",
            accessToken: accessToken
        )

        let relationships = try await fetchAllMyRelationships()
        let relationshipByUser = relationships.reduce(into: [UUID: RelationshipState]()) { partialResult, row in
            let otherUserID = row.requesterID == currentUserID ? row.addresseeID : row.requesterID
            partialResult[otherUserID] = mapRelationship(row, currentUserID: currentUserID)
        }

        return profiles.compactMap { profile in
            guard profile.id != currentUserID else { return nil }
            let relationship = relationshipByUser[profile.id] ?? .none
            guard relationship != .blocked else { return nil }
            return FriendSearchResult(profile: profile, relationship: relationship)
        }
    }

    func fetchProfile(username: String) async throws -> SocialProfile? {
        let accessToken = try signedInAccessToken()
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let encodedUsername = encodedQueryValue(trimmed)

        // Prefer exact equality first, then fall back to case-insensitive lookup.
        let exactProfiles: [SocialProfile] = try await execute(
            path: "/rest/v1/profiles?select=*&username=eq.\(encodedUsername)&limit=1",
            method: "GET",
            accessToken: accessToken
        )
        if let first = exactProfiles.first {
            return first
        }

        let ilikeProfiles: [SocialProfile] = try await execute(
            path: "/rest/v1/profiles?select=*&username=ilike.\(encodedUsername)&limit=1",
            method: "GET",
            accessToken: accessToken
        )
        return ilikeProfiles.first
    }

    func fetchRelationshipState(for userID: UUID) async throws -> RelationshipState {
        let currentUserID = try signedInUserID()
        let relationships = try await fetchMutualRelationships(with: userID, currentUserID: currentUserID)
        guard let first = relationships.first else { return .none }
        return mapRelationship(first, currentUserID: currentUserID)
    }

    func sendRequest(to userID: UUID) async throws {
        let currentUserID = try signedInUserID()
        guard userID != currentUserID else { throw SocialFriendError.invalidRequest }

        let accessToken = try signedInAccessToken()
        let existing = try await fetchMutualRelationships(with: userID, currentUserID: currentUserID)
        if let row = existing.first {
            switch mapRelationship(row, currentUserID: currentUserID) {
            case .blocked:
                throw SocialFriendError.blocked
            case .friends:
                throw SocialFriendError.alreadyFriends
            case .pendingOutgoing:
                throw SocialFriendError.requestAlreadyPending
            case .pendingIncoming(let friendshipID):
                try await respond(to: friendshipID, accepted: true)
                return
            case .none:
                break
            }
        }

        try await enforceFreeTierLimitIfNeeded(accessToken: accessToken, currentUserID: currentUserID)

        let payload = InsertFriendshipRequest(
            requesterID: currentUserID,
            addresseeID: userID,
            status: .pending
        )
        _ = try await execute(
            path: "/rest/v1/friendships",
            method: "POST",
            accessToken: accessToken,
            body: payload,
            extraHeaders: [
                "Prefer": "return=minimal"
            ]
        ) as EmptyResponse
    }

    func respond(to friendshipID: UUID, accepted: Bool) async throws {
        let currentUserID = try signedInUserID()
        let accessToken = try signedInAccessToken()

        if accepted {
            let payload = PatchFriendshipStatusRequest(status: .accepted)
            _ = try await execute(
                path: "/rest/v1/friendships?id=eq.\(friendshipID.uuidString)&addressee_id=eq.\(currentUserID.uuidString)&status=eq.pending",
                method: "PATCH",
                accessToken: accessToken,
                body: payload,
                extraHeaders: [
                    "Prefer": "return=minimal"
                ]
            ) as EmptyResponse
        } else {
            _ = try await execute(
                path: "/rest/v1/friendships?id=eq.\(friendshipID.uuidString)&addressee_id=eq.\(currentUserID.uuidString)&status=eq.pending",
                method: "DELETE",
                accessToken: accessToken,
                extraHeaders: [
                    "Prefer": "return=minimal"
                ]
            ) as EmptyResponse
        }
    }

    func block(userID: UUID) async throws {
        let currentUserID = try signedInUserID()
        guard currentUserID != userID else { throw SocialFriendError.invalidRequest }

        let accessToken = try signedInAccessToken()
        let existing = try await fetchMutualRelationships(with: userID, currentUserID: currentUserID)

        for row in existing where row.requesterID == currentUserID {
            _ = try await execute(
                path: "/rest/v1/friendships?id=eq.\(row.id.uuidString)&requester_id=eq.\(currentUserID.uuidString)",
                method: "DELETE",
                accessToken: accessToken,
                extraHeaders: [
                    "Prefer": "return=minimal"
                ]
            ) as EmptyResponse
        }

        for row in existing where row.addresseeID == currentUserID {
            let payload = PatchFriendshipStatusRequest(status: .blocked)
            _ = try await execute(
                path: "/rest/v1/friendships?id=eq.\(row.id.uuidString)&addressee_id=eq.\(currentUserID.uuidString)",
                method: "PATCH",
                accessToken: accessToken,
                body: payload,
                extraHeaders: [
                    "Prefer": "return=minimal"
                ]
            ) as EmptyResponse
        }

        let blockPayload = InsertFriendshipRequest(
            requesterID: currentUserID,
            addresseeID: userID,
            status: .blocked
        )
        _ = try await execute(
            path: "/rest/v1/friendships?on_conflict=requester_id,addressee_id",
            method: "POST",
            accessToken: accessToken,
            body: blockPayload,
            extraHeaders: [
                "Prefer": "resolution=merge-duplicates,return=minimal"
            ]
        ) as EmptyResponse
    }

    func queueProfileDeepLink(from url: URL) -> Bool {
        guard let username = Self.parseProfileUsername(from: url) else { return false }
        queuedProfileUsername = username
        return true
    }

    func consumeQueuedProfileUsername() -> String? {
        defer { queuedProfileUsername = nil }
        return queuedProfileUsername
    }

    static func parseProfileUsername(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "bindr" else { return nil }
        guard url.host?.lowercased() == "profile" else { return nil }

        let rawPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard rawPath.hasPrefix("@") else { return nil }
        let candidate = String(rawPath.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !candidate.isEmpty else { return nil }
        return candidate
    }

    private func enforceFreeTierLimitIfNeeded(accessToken: String, currentUserID: UUID) async throws {
        guard !storeService.isPremium else { return }

        let requesterSide: [Friendship] = try await execute(
            path: "/rest/v1/friendships?select=id,requester_id,addressee_id,status,created_at&requester_id=eq.\(currentUserID.uuidString)&status=in.(pending,accepted)",
            method: "GET",
            accessToken: accessToken
        )
        let addresseeSide: [Friendship] = try await execute(
            path: "/rest/v1/friendships?select=id,requester_id,addressee_id,status,created_at&addressee_id=eq.\(currentUserID.uuidString)&status=in.(pending,accepted)",
            method: "GET",
            accessToken: accessToken
        )
        if requesterSide.count + addresseeSide.count >= 1 {
            throw SocialFriendError.freeTierLimitReached
        }
    }

    private func fetchAllMyRelationships() async throws -> [FriendshipWithProfiles] {
        let currentUserID = try signedInUserID()
        let path = "/rest/v1/friendships?select=id,requester_id,addressee_id,status,created_at&or=(requester_id.eq.\(currentUserID.uuidString),addressee_id.eq.\(currentUserID.uuidString))"
        let rows: [FriendshipWithProfiles] = try await execute(
            path: path,
            method: "GET",
            accessToken: try signedInAccessToken()
        )
        return rows
    }

    private func fetchMutualRelationships(with userID: UUID, currentUserID: UUID) async throws -> [FriendshipWithProfiles] {
        let path = "/rest/v1/friendships?select=id,requester_id,addressee_id,status,created_at&or=(and(requester_id.eq.\(currentUserID.uuidString),addressee_id.eq.\(userID.uuidString)),and(requester_id.eq.\(userID.uuidString),addressee_id.eq.\(currentUserID.uuidString)))"
        let rows: [FriendshipWithProfiles] = try await execute(
            path: path,
            method: "GET",
            accessToken: try signedInAccessToken()
        )
        return rows
    }

    private func mapRelationship(_ row: FriendshipWithProfiles, currentUserID: UUID) -> RelationshipState {
        switch row.status {
        case .accepted:
            return .friends
        case .blocked:
            return .blocked
        case .pending:
            if row.addresseeID == currentUserID {
                return .pendingIncoming(friendshipID: row.id)
            }
            return .pendingOutgoing(friendshipID: row.id)
        }
    }

    private func signedInUserID() throws -> UUID {
        switch authService.authState {
        case .signedOut:
            throw SocialFriendError.notSignedIn
        case .signedIn(let userID, _):
            return userID
        }
    }

    private func signedInAccessToken() throws -> String {
        guard let token = authService.accessToken, !token.isEmpty else {
            throw SocialFriendError.notSignedIn
        }
        return token
    }

    private func encodedQueryValue(_ value: String) -> String {
        let disallowed = CharacterSet(charactersIn: "&=?#+,")
        let allowed = CharacterSet.urlQueryAllowed.subtracting(disallowed)
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
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
            throw SocialFriendError.missingConfiguration
        }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw SocialFriendError.invalidResponse
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
            throw SocialFriendError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let payload = try? JSONDecoder.socialJSON.decode(APIErrorPayload.self, from: data) {
                throw SocialFriendError.requestFailed(payload.message ?? payload.hint ?? "Supabase request failed with status \(http.statusCode).")
            }
            throw SocialFriendError.requestFailed("Supabase request failed with status \(http.statusCode).")
        }

        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }

        if data.isEmpty {
            throw SocialFriendError.invalidResponse
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
