import Foundation
import Observation

@Observable
@MainActor
final class SocialProfileService {
    enum SocialProfileError: LocalizedError {
        case notSignedIn
        case missingConfiguration
        case invalidResponse
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "Sign in first to access your social profile."
            case .missingConfiguration:
                return "Supabase social config is missing from Info.plist."
            case .invalidResponse:
                return "Could not parse profile data from Supabase."
            case .requestFailed(let message):
                return message
            }
        }
    }

    private struct UpsertProfileRequest: Encodable {
        let id: UUID
        let appleUserID: String
        let username: String
        let displayName: String?
        let bio: String?
        let avatarURL: String?
        let profileRoles: [String]
        let favoritePokemonDex: Int?
        let favoritePokemonName: String?
        let favoritePokemonImageURL: String?
        let favoriteCardID: String?
        let favoriteCardName: String?
        let favoriteCardSetCode: String?
        let favoriteCardImageURL: String?
        let favoriteDeckArchetype: String?
        let isWishlistPublic: Bool?
        let wishlistCardIDs: [String]?
        let avatarBackgroundColor: String?
        let avatarOutlineStyle: String?

        enum CodingKeys: String, CodingKey {
            case id
            case appleUserID = "apple_user_id"
            case username
            case displayName = "display_name"
            case bio
            case avatarURL = "avatar_url"
            case profileRoles = "profile_roles"
            case favoritePokemonDex = "favorite_pokemon_dex"
            case favoritePokemonName = "favorite_pokemon_name"
            case favoritePokemonImageURL = "favorite_pokemon_image_url"
            case favoriteCardID = "favorite_card_id"
            case favoriteCardName = "favorite_card_name"
            case favoriteCardSetCode = "favorite_card_set_code"
            case favoriteCardImageURL = "favorite_card_image_url"
            case favoriteDeckArchetype = "favorite_deck_archetype"
            case isWishlistPublic = "is_wishlist_public"
            case wishlistCardIDs = "wishlist_card_ids"
            case avatarBackgroundColor = "avatar_background_color"
            case avatarOutlineStyle = "avatar_outline_style"
        }
    }

    private struct NotificationPreferencesInsert: Encodable {
        let userID: UUID

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
        }
    }

    private struct UpdateNotificationPreferencesRequest: Encodable {
        let friendRequests: Bool
        let friendAccepts: Bool
        let sharedContentPosts: Bool
        let comments: Bool
        let wishlistMatches: Bool
        let tradeUpdates: Bool
        let marketing: Bool
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
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

    private struct DeviceTokenUpsertRequest: Encodable {
        let userID: UUID
        let token: String
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case token
            case updatedAt = "updated_at"
        }
    }

    private struct UpdateProfileRequest: Encodable {
        let displayName: String?
        let bio: String?
        let profileRoles: [String]
        let favoritePokemonDex: Int?
        let favoritePokemonName: String?
        let favoritePokemonImageURL: String?
        let favoriteCardID: String?
        let favoriteCardName: String?
        let favoriteCardSetCode: String?
        let favoriteCardImageURL: String?
        let favoriteDeckArchetype: String?
        let isWishlistPublic: Bool?
        let wishlistCardIDs: [String]?
        let avatarBackgroundColor: String?
        let avatarOutlineStyle: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
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
            case isWishlistPublic = "is_wishlist_public"
            case wishlistCardIDs = "wishlist_card_ids"
            case avatarBackgroundColor = "avatar_background_color"
            case avatarOutlineStyle = "avatar_outline_style"
        }
    }

    private struct APIErrorPayload: Decodable {
        let message: String?
        let hint: String?
    }

    private let authService: SocialAuthService
    private var baseURL: URL? { AppConfiguration.supabaseURL }
    private var publishableKey: String { AppConfiguration.supabasePublishableKey }

    init(authService: SocialAuthService) {
        self.authService = authService
    }

    func fetchMyProfile() async throws -> SocialProfile? {
        let userID = try signedInUserID()
        let rows: [SocialProfile] = try await execute(
            path: "/rest/v1/profiles?select=*&id=eq.\(userID.uuidString)",
            method: "GET",
            accessToken: try signedInAccessToken()
        )
        return rows.first
    }

    func saveProfile(
        username: String,
        displayName: String?,
        bio: String?,
        profileRoles: [String],
        favoritePokemonDex: Int?,
        favoritePokemonName: String?,
        favoritePokemonImageURL: String?,
        favoriteCardID: String?,
        favoriteCardName: String?,
        favoriteCardSetCode: String?,
        favoriteCardImageURL: String?,
        favoriteDeckArchetype: String?,
        isWishlistPublic: Bool?,
        wishlistCardIDs: [String]?,
        avatarBackgroundColor: String?,
        avatarOutlineStyle: String?
    ) async throws -> SocialProfile {
        let userID = try signedInUserID()
        let appleUserID = KeychainStorage.readAppleUserIdentifier() ?? "apple-\(userID.uuidString)"
        let payload = UpsertProfileRequest(
            id: userID,
            appleUserID: appleUserID,
            username: username,
            displayName: displayName?.trimmedNilIfEmpty,
            bio: bio?.trimmedNilIfEmpty,
            avatarURL: nil,
            profileRoles: profileRoles,
            favoritePokemonDex: favoritePokemonDex,
            favoritePokemonName: favoritePokemonName?.trimmedNilIfEmpty,
            favoritePokemonImageURL: favoritePokemonImageURL?.trimmedNilIfEmpty,
            favoriteCardID: favoriteCardID?.trimmedNilIfEmpty,
            favoriteCardName: favoriteCardName?.trimmedNilIfEmpty,
            favoriteCardSetCode: favoriteCardSetCode?.trimmedNilIfEmpty,
            favoriteCardImageURL: favoriteCardImageURL?.trimmedNilIfEmpty,
            favoriteDeckArchetype: favoriteDeckArchetype?.trimmedNilIfEmpty,
            isWishlistPublic: isWishlistPublic,
            wishlistCardIDs: wishlistCardIDs,
            avatarBackgroundColor: avatarBackgroundColor?.trimmedNilIfEmpty,
            avatarOutlineStyle: avatarOutlineStyle?.trimmedNilIfEmpty
        )
        let profiles: [SocialProfile] = try await execute(
            path: "/rest/v1/profiles?on_conflict=id&select=*",
            method: "POST",
            accessToken: try signedInAccessToken(),
            body: payload,
            extraHeaders: [
                "Prefer": "resolution=merge-duplicates,return=representation"
            ]
        )
        let profile = try profiles.first.unwrapOrThrow(SocialProfileError.invalidResponse)
        try await ensureNotificationPreferences(userID: userID)
        return profile
    }

    func updateProfile(
        displayName: String?,
        bio: String?,
        profileRoles: [String],
        favoritePokemonDex: Int?,
        favoritePokemonName: String?,
        favoritePokemonImageURL: String?,
        favoriteCardID: String?,
        favoriteCardName: String?,
        favoriteCardSetCode: String?,
        favoriteCardImageURL: String?,
        favoriteDeckArchetype: String?,
        isWishlistPublic: Bool?,
        wishlistCardIDs: [String]?,
        avatarBackgroundColor: String?,
        avatarOutlineStyle: String?
    ) async throws -> SocialProfile {
        let userID = try signedInUserID()
        let payload = UpdateProfileRequest(
            displayName: displayName?.trimmedNilIfEmpty,
            bio: bio?.trimmedNilIfEmpty,
            profileRoles: profileRoles,
            favoritePokemonDex: favoritePokemonDex,
            favoritePokemonName: favoritePokemonName?.trimmedNilIfEmpty,
            favoritePokemonImageURL: favoritePokemonImageURL?.trimmedNilIfEmpty,
            favoriteCardID: favoriteCardID?.trimmedNilIfEmpty,
            favoriteCardName: favoriteCardName?.trimmedNilIfEmpty,
            favoriteCardSetCode: favoriteCardSetCode?.trimmedNilIfEmpty,
            favoriteCardImageURL: favoriteCardImageURL?.trimmedNilIfEmpty,
            favoriteDeckArchetype: favoriteDeckArchetype?.trimmedNilIfEmpty,
            isWishlistPublic: isWishlistPublic,
            wishlistCardIDs: wishlistCardIDs,
            avatarBackgroundColor: avatarBackgroundColor?.trimmedNilIfEmpty,
            avatarOutlineStyle: avatarOutlineStyle?.trimmedNilIfEmpty
        )
        let profiles: [SocialProfile] = try await execute(
            path: "/rest/v1/profiles?id=eq.\(userID.uuidString)&select=*",
            method: "PATCH",
            accessToken: try signedInAccessToken(),
            body: payload,
            extraHeaders: [
                "Prefer": "return=representation"
            ]
        )
        return try profiles.first.unwrapOrThrow(SocialProfileError.invalidResponse)
    }

    func fetchNotificationPreferences() async throws -> NotificationPreferences {
        let userID = try signedInUserID()
        let rows: [NotificationPreferences] = try await execute(
            path: "/rest/v1/notification_preferences?select=*&user_id=eq.\(userID.uuidString)&limit=1",
            method: "GET",
            accessToken: try signedInAccessToken()
        )
        if let first = rows.first {
            return first
        }
        try await ensureNotificationPreferences(userID: userID)
        let seededRows: [NotificationPreferences] = try await execute(
            path: "/rest/v1/notification_preferences?select=*&user_id=eq.\(userID.uuidString)&limit=1",
            method: "GET",
            accessToken: try signedInAccessToken()
        )
        return try seededRows.first.unwrapOrThrow(SocialProfileError.invalidResponse)
    }

    func updateNotificationPreferences(
        friendRequests: Bool,
        friendAccepts: Bool,
        sharedContentPosts: Bool,
        comments: Bool,
        wishlistMatches: Bool,
        tradeUpdates: Bool,
        marketing: Bool
    ) async throws -> NotificationPreferences {
        let userID = try signedInUserID()
        let payload = UpdateNotificationPreferencesRequest(
            friendRequests: friendRequests,
            friendAccepts: friendAccepts,
            sharedContentPosts: sharedContentPosts,
            comments: comments,
            wishlistMatches: wishlistMatches,
            tradeUpdates: tradeUpdates,
            marketing: marketing,
            updatedAt: Date()
        )
        let rows: [NotificationPreferences] = try await execute(
            path: "/rest/v1/notification_preferences?user_id=eq.\(userID.uuidString)&select=*",
            method: "PATCH",
            accessToken: try signedInAccessToken(),
            body: payload,
            extraHeaders: [
                "Prefer": "return=representation"
            ]
        )
        return try rows.first.unwrapOrThrow(SocialProfileError.invalidResponse)
    }

    func registerDeviceToken(_ token: String) async throws {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else { return }
        let userID = try signedInUserID()
        let payload = DeviceTokenUpsertRequest(
            userID: userID,
            token: normalizedToken,
            updatedAt: Date()
        )
        _ = try await execute(
            path: "/rest/v1/device_tokens?on_conflict=user_id,token",
            method: "POST",
            accessToken: try signedInAccessToken(),
            body: payload,
            extraHeaders: [
                "Prefer": "resolution=merge-duplicates,return=minimal"
            ]
        ) as EmptyResponse
    }

    private func ensureNotificationPreferences(userID: UUID) async throws {
        let payload = NotificationPreferencesInsert(userID: userID)
        _ = try await execute(
            path: "/rest/v1/notification_preferences?on_conflict=user_id",
            method: "POST",
            accessToken: try signedInAccessToken(),
            body: payload,
            extraHeaders: [
                "Prefer": "resolution=ignore-duplicates,return=minimal"
            ]
        ) as EmptyResponse
    }

    private func signedInUserID() throws -> UUID {
        switch authService.authState {
        case .signedOut:
            throw SocialProfileError.notSignedIn
        case .signedIn(let userID, _):
            return userID
        }
    }

    private func signedInAccessToken() throws -> String {
        guard let token = authService.accessToken, !token.isEmpty else {
            throw SocialProfileError.notSignedIn
        }
        return token
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
            throw SocialProfileError.missingConfiguration
        }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw SocialProfileError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        for (header, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }
        if let body {
            let encoder = JSONEncoder.socialJSON
            let data = try encoder.encode(body)
            request.httpBody = data
            if let json = String(data: data, encoding: .utf8) {
                print("--- SOCIAL REQUEST \(method) \(path) ---")
                print(json)
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SocialProfileError.invalidResponse
        }
        
        print("--- SOCIAL RESPONSE \(http.statusCode) ---")
        if let json = String(data: data, encoding: .utf8) {
            print(json)
        }
        guard (200..<300).contains(http.statusCode) else {
            if let payload = try? JSONDecoder.socialJSON.decode(APIErrorPayload.self, from: data) {
                throw SocialProfileError.requestFailed(payload.message ?? payload.hint ?? "Supabase request failed with status \(http.statusCode).")
            }
            throw SocialProfileError.requestFailed("Supabase request failed with status \(http.statusCode).")
        }

        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
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

private extension Optional {
    func unwrapOrThrow(_ error: Error) throws -> Wrapped {
        guard let value = self else { throw error }
        return value
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
