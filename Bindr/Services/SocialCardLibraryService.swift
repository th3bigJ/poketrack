import Foundation
import Observation

@Observable
@MainActor
final class SocialCardLibraryService {
    enum SocialCardLibraryError: LocalizedError {
        case notSignedIn
        case missingConfiguration
        case invalidResponse
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "Sign in first to sync social collection and wishlist."
            case .missingConfiguration:
                return "Supabase social config is missing from Info.plist."
            case .invalidResponse:
                return "Could not parse social card library data from Supabase."
            case .requestFailed(let message):
                return message
            }
        }
    }

    private struct APIErrorPayload: Decodable {
        let message: String?
        let hint: String?
    }

    private struct WishlistItemUpsertRequest: Encodable {
        let userID: UUID
        let cardID: String
        let variantKey: String
        let notes: String?
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case cardID = "card_id"
            case variantKey = "variant_key"
            case notes
            case updatedAt = "updated_at"
        }
    }

    private struct CollectionItemUpsertRequest: Encodable {
        let userID: UUID
        let cardID: String
        let variantKey: String
        let quantity: Int
        let notes: String?
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case cardID = "card_id"
            case variantKey = "variant_key"
            case quantity
            case notes
            case updatedAt = "updated_at"
        }
    }

    private struct WishlistItemRow: Decodable {
        let userID: UUID
        let cardID: String
        let variantKey: String

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case cardID = "card_id"
            case variantKey = "variant_key"
        }
    }

    private struct CollectionItemRow: Decodable {
        let userID: UUID
        let cardID: String
        let variantKey: String
        let quantity: Int

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case cardID = "card_id"
            case variantKey = "variant_key"
            case quantity
        }
    }

    private enum SyncKey: Hashable {
        case wishlist
        case collection
    }

    private struct WishlistItemSnapshot: Sendable, Equatable {
        let cardID: String
        let variantKey: String
        let notes: String?
    }

    private struct CollectionItemSnapshot: Sendable, Equatable {
        let cardID: String
        let variantKey: String
        let quantity: Int
        let notes: String?
    }

    private let authService: SocialAuthService
    private var baseURL: URL? { AppConfiguration.supabaseURL }
    private var publishableKey: String { AppConfiguration.supabasePublishableKey }
    private var pendingSyncTasks: [SyncKey: Task<Void, Never>] = [:]
    private var pendingWishlistSnapshots: [WishlistItemSnapshot] = []
    private var pendingCollectionSnapshots: [CollectionItemSnapshot] = []
    private let queryDateFormatter = ISO8601DateFormatter()
    private(set) var lastSyncError: String?
    private let maxUpsertBatchSize = 250

    init(authService: SocialAuthService) {
        self.authService = authService
        queryDateFormatter.formatOptions = [.withInternetDateTime]
    }

    func scheduleAutoSyncWishlist(items: [WishlistItem]) {
        pendingWishlistSnapshots = items.map {
            WishlistItemSnapshot(
                cardID: $0.cardID,
                variantKey: $0.variantKey,
                notes: cleanedNotes($0.notes)
            )
        }
        scheduleSync(for: .wishlist)
    }

    func scheduleAutoSyncCollection(items: [CollectionItem]) {
        pendingCollectionSnapshots = items.map {
            CollectionItemSnapshot(
                cardID: $0.cardID,
                variantKey: $0.variantKey,
                quantity: max($0.quantity, 1),
                notes: cleanedNotes($0.notes)
            )
        }
        scheduleSync(for: .collection)
    }

    func fetchWishlistCardIDs(for userID: UUID) async throws -> [String] {
        let rows: [WishlistItemRow] = try await execute(
            path: "/rest/v1/social_wishlist_items?select=user_id,card_id,variant_key&user_id=eq.\(userID.uuidString)&order=updated_at.desc",
            method: "GET",
            accessToken: try signedInAccessToken()
        )
        return dedupeCardIDs(rows.map(\.cardID))
    }

    func fetchCollectionCardIDs(for userID: UUID) async throws -> [String] {
        let rows: [CollectionItemRow] = try await execute(
            path: "/rest/v1/social_collection_items?select=user_id,card_id,variant_key,quantity&user_id=eq.\(userID.uuidString)&order=updated_at.desc",
            method: "GET",
            accessToken: try signedInAccessToken()
        )
        return dedupeCardIDs(rows.map(\.cardID))
    }

    func fetchWishlistCardIDsByUser(for userIDs: [UUID]) async throws -> [UUID: [String]] {
        guard !userIDs.isEmpty else { return [:] }
        let inList = userIDs.map(\.uuidString).joined(separator: ",")
        let rows: [WishlistItemRow] = try await execute(
            path: "/rest/v1/social_wishlist_items?select=user_id,card_id,variant_key&user_id=in.(\(inList))&order=updated_at.desc",
            method: "GET",
            accessToken: try signedInAccessToken()
        )
        var grouped: [UUID: [String]] = [:]
        for row in rows where !row.cardID.isEmpty {
            grouped[row.userID, default: []].append(row.cardID)
        }
        return grouped.mapValues { dedupeCardIDs($0) }
    }

    private func replaceMyWishlist(with snapshots: [WishlistItemSnapshot]) async throws {
        let userID = try signedInUserID()
        let token = try signedInAccessToken()
        let syncStartedAt = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))

        if !snapshots.isEmpty {
            let payload = snapshots.map {
                WishlistItemUpsertRequest(
                    userID: userID,
                    cardID: $0.cardID,
                    variantKey: $0.variantKey,
                    notes: $0.notes,
                    updatedAt: syncStartedAt
                )
            }
            for batch in payload.chunked(into: maxUpsertBatchSize) {
                _ = try await execute(
                    path: "/rest/v1/social_wishlist_items?on_conflict=user_id,card_id,variant_key",
                    method: "POST",
                    accessToken: token,
                    body: batch,
                    extraHeaders: ["Prefer": "resolution=merge-duplicates,return=minimal"]
                ) as EmptyResponse
            }
        }

        let encodedCutoff = encodedQueryValue(queryDateFormatter.string(from: syncStartedAt))
        _ = try await execute(
            path: "/rest/v1/social_wishlist_items?user_id=eq.\(userID.uuidString)&updated_at=lt.\(encodedCutoff)",
            method: "DELETE",
            accessToken: token,
            extraHeaders: ["Prefer": "return=minimal"]
        ) as EmptyResponse
    }

    private func replaceMyCollection(with snapshots: [CollectionItemSnapshot]) async throws {
        let userID = try signedInUserID()
        let token = try signedInAccessToken()
        let syncStartedAt = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))

        if !snapshots.isEmpty {
            let payload = snapshots.map {
                CollectionItemUpsertRequest(
                    userID: userID,
                    cardID: $0.cardID,
                    variantKey: $0.variantKey,
                    quantity: max($0.quantity, 1),
                    notes: $0.notes,
                    updatedAt: syncStartedAt
                )
            }
            for batch in payload.chunked(into: maxUpsertBatchSize) {
                _ = try await execute(
                    path: "/rest/v1/social_collection_items?on_conflict=user_id,card_id,variant_key",
                    method: "POST",
                    accessToken: token,
                    body: batch,
                    extraHeaders: ["Prefer": "resolution=merge-duplicates,return=minimal"]
                ) as EmptyResponse
            }
        }

        let encodedCutoff = encodedQueryValue(queryDateFormatter.string(from: syncStartedAt))
        _ = try await execute(
            path: "/rest/v1/social_collection_items?user_id=eq.\(userID.uuidString)&updated_at=lt.\(encodedCutoff)",
            method: "DELETE",
            accessToken: token,
            extraHeaders: ["Prefer": "return=minimal"]
        ) as EmptyResponse
    }

    private func scheduleSync(for key: SyncKey) {
        guard pendingSyncTasks[key] == nil else { return }
        pendingSyncTasks[key] = Task { [weak self] in
            guard let self else { return }
            defer {
                self.pendingSyncTasks[key] = nil
                if self.hasPendingWork(for: key) {
                    self.scheduleSync(for: key)
                }
            }
            do {
                switch key {
                case .wishlist:
                    let snapshots = pendingWishlistSnapshots
                    try await replaceMyWishlist(with: snapshots)
                    pendingWishlistSnapshots = snapshots == pendingWishlistSnapshots ? [] : pendingWishlistSnapshots
                case .collection:
                    let snapshots = pendingCollectionSnapshots
                    try await replaceMyCollection(with: snapshots)
                    pendingCollectionSnapshots = snapshots == pendingCollectionSnapshots ? [] : pendingCollectionSnapshots
                }
                lastSyncError = nil
            } catch is CancellationError {
                // Benign when app lifecycle cancels tasks.
            } catch {
                // Non-fatal; next local change (or auth recovery) will schedule another sync.
                lastSyncError = error.localizedDescription
                print("[SocialCardLibrary] Sync failed: \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func hasPendingWork(for key: SyncKey) -> Bool {
        switch key {
        case .wishlist:
            return !pendingWishlistSnapshots.isEmpty
        case .collection:
            return !pendingCollectionSnapshots.isEmpty
        }
    }

    private func dedupeCardIDs(_ ids: [String]) -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []
        for id in ids where !id.isEmpty {
            if seen.insert(id).inserted {
                ordered.append(id)
            }
        }
        return ordered
    }

    private func cleanedNotes(_ notes: String) -> String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func encodedQueryValue(_ value: String) -> String {
        let disallowed = CharacterSet(charactersIn: "&=?#+,")
        let allowed = CharacterSet.urlQueryAllowed.subtracting(disallowed)
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func signedInUserID() throws -> UUID {
        switch authService.authState {
        case .signedOut:
            throw SocialCardLibraryError.notSignedIn
        case .signedIn(let userID, _):
            return userID
        }
    }

    private func signedInAccessToken() throws -> String {
        guard let token = authService.accessToken, !token.isEmpty else {
            throw SocialCardLibraryError.notSignedIn
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
            throw SocialCardLibraryError.missingConfiguration
        }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw SocialCardLibraryError.invalidResponse
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
            let data = try JSONEncoder.socialJSON.encode(body)
            request.httpBody = data
            if let json = String(data: data, encoding: .utf8) {
                print("--- SOCIAL LIB REQUEST \(method) \(path) ---")
                print(json)
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SocialCardLibraryError.invalidResponse
        }
        print("--- SOCIAL LIB RESPONSE \(http.statusCode) ---")
        if let json = String(data: data, encoding: .utf8), !json.isEmpty {
            print(json)
        }
        guard (200..<300).contains(http.statusCode) else {
            if let payload = try? JSONDecoder.socialJSON.decode(APIErrorPayload.self, from: data) {
                throw SocialCardLibraryError.requestFailed(payload.message ?? payload.hint ?? "Supabase request failed with status \(http.statusCode).")
            }
            throw SocialCardLibraryError.requestFailed("Supabase request failed with status \(http.statusCode).")
        }

        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }
        if data.isEmpty {
            throw SocialCardLibraryError.invalidResponse
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

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var chunks: [[Element]] = []
        chunks.reserveCapacity((count + size - 1) / size)
        var index = 0
        while index < count {
            let end = Swift.min(index + size, count)
            chunks.append(Array(self[index..<end]))
            index = end
        }
        return chunks
    }
}
