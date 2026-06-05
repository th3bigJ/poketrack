import Foundation
import Observation
import SwiftData

/// Snapshot format written to R2: `user-collections/{userID}/collection.json`
struct FriendCollectionSnapshot: Codable {
    struct CardEntry: Codable {
        let cardID: String
        let variantKey: String
        let qty: Int

        enum CodingKeys: String, CodingKey {
            case cardID = "cardID"
            case variantKey
            case qty
        }
    }

    struct WishlistEntry: Codable {
        let cardID: String
        let variantKey: String
    }

    let userID: String
    let updatedAt: String
    let collection: [CardEntry]
    let wishlist: [WishlistEntry]
}

/// Uploads the signed-in user's collection snapshot to R2 via the collection-sync
/// Cloudflare Worker, and fetches snapshots for friends when building trades.
@Observable
@MainActor
final class CollectionSyncService {
    private let authService: SocialAuthService
    private var modelContext: ModelContext?
    private var debounceTask: Task<Void, Never>?
    private let debounceDelay: Duration = .seconds(30)

    private(set) var lastUploadError: String?
    private(set) var lastUploadedAt: Date?

    init(authService: SocialAuthService) {
        self.authService = authService
    }

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Call whenever the collection or wishlist changes. Upload is debounced 30s.
    func scheduleUpload() {
        guard case .signedIn = authService.authState else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: debounceDelay)
            guard !Task.isCancelled else { return }
            await self.uploadSnapshot()
        }
    }

    /// Fetch another user's snapshot for use in trade builder.
    func fetchFriendCollection(userID: UUID) async throws -> FriendCollectionSnapshot {
        guard let url = AppConfiguration.collectionSyncGetURL(userID: userID) else {
            throw CollectionSyncError.missingConfiguration
        }
        guard let token = authService.accessToken, !token.isEmpty else {
            throw CollectionSyncError.notSignedIn
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CollectionSyncError.httpError(code)
        }
        return try JSONDecoder().decode(FriendCollectionSnapshot.self, from: data)
    }

    // MARK: - Private

    private func uploadSnapshot() async {
        guard let url = AppConfiguration.collectionSyncPutURL else {
            lastUploadError = "Worker URL not configured."
            return
        }
        guard let token = authService.accessToken, !token.isEmpty else { return }
        guard case .signedIn(let userID, _) = authService.authState else { return }
        guard let ctx = modelContext else { return }

        do {
            let snapshot = try buildSnapshot(userID: userID, modelContext: ctx)
            let data = try JSONEncoder().encode(snapshot)

            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                lastUploadError = "Upload failed with status \(code)."
                return
            }
            lastUploadError = nil
            lastUploadedAt = Date()
        } catch {
            lastUploadError = error.localizedDescription
        }
    }

    private func buildSnapshot(userID: UUID, modelContext: ModelContext) throws -> FriendCollectionSnapshot {
        let collectionItems = try modelContext.fetch(FetchDescriptor<CollectionItem>())
        let wishlistItems = try modelContext.fetch(FetchDescriptor<WishlistItem>())

        let collection: [FriendCollectionSnapshot.CardEntry] = collectionItems.compactMap { item in
            guard item.quantity > 0, !item.cardID.isEmpty else { return nil }
            return FriendCollectionSnapshot.CardEntry(
                cardID: item.cardID,
                variantKey: item.variantKey,
                qty: item.quantity
            )
        }

        let wishlist: [FriendCollectionSnapshot.WishlistEntry] = wishlistItems.compactMap { item in
            guard !item.cardID.isEmpty else { return nil }
            return FriendCollectionSnapshot.WishlistEntry(cardID: item.cardID, variantKey: item.variantKey)
        }

        let formatter = ISO8601DateFormatter()
        return FriendCollectionSnapshot(
            userID: userID.uuidString.lowercased(),
            updatedAt: formatter.string(from: Date()),
            collection: collection,
            wishlist: wishlist
        )
    }
}

enum CollectionSyncError: LocalizedError {
    case notSignedIn
    case missingConfiguration
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in to access friend collections."
        case .missingConfiguration: return "Collection sync worker URL not configured."
        case .httpError(let code): return "Collection fetch failed (HTTP \(code))."
        }
    }
}
