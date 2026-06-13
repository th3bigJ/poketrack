import Foundation
import Observation
import SwiftData

/// Uploads the signed-in user's full library snapshot to R2 via the collection-sync
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
    private(set) var lastUploadedSummary: String?
    private(set) var lastRestoreError: String?
    private(set) var lastRestoredAt: Date?
    private(set) var lastRestoredCardCount: Int = 0
    private(set) var lastRestoredSummary: String?
    private(set) var isRestoring = false
    private(set) var isUploading = false

    init(authService: SocialAuthService) {
        self.authService = authService
    }

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Call whenever library data changes. Upload is debounced 30s.
    func scheduleUpload() {
        guard case .signedIn = authService.authState else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: debounceDelay)
            guard !Task.isCancelled else { return }
            _ = await self.uploadSnapshot(force: false)
        }
    }

    /// Immediately uploads the full local library to R2.
    @discardableResult
    func backupEverythingNow() async -> Bool {
        debounceTask?.cancel()
        return await uploadSnapshot(force: true)
    }

    /// Downloads the signed-in user's own cloud backup (R2 snapshot).
    func fetchOwnSnapshot() async throws -> UserLibraryBackup? {
        guard case .signedIn(let userID, _) = authService.authState else {
            throw CollectionSyncError.notSignedIn
        }
        do {
            return try await fetchFriendCollection(userID: userID)
        } catch CollectionSyncError.httpError(404) {
            return nil
        }
    }

    /// Restores the full library from R2 when local data is empty, or when `force` is true.
    @discardableResult
    func restoreFromCloudBackupIfNeeded(force: Bool = false) async -> Bool {
        guard let ctx = modelContext else { return false }
        guard case .signedIn = authService.authState else { return false }

        let localEmpty = UserLibraryBackupCodec.localLibraryIsEmpty(ctx)
        guard force || localEmpty else {
            print("[CollectionSync] skip restore — local library already present")
            return false
        }

        isRestoring = true
        lastRestoreError = nil
        defer { isRestoring = false }

        do {
            guard let snapshot = try await fetchOwnSnapshot() else {
                print("[CollectionSync] no cloud backup found")
                return false
            }
            guard snapshot.hasAnyData else {
                print("[CollectionSync] cloud backup is empty — nothing to restore")
                return false
            }

            let restoredCards = try UserLibraryBackupCodec.apply(
                snapshot,
                modelContext: ctx,
                replaceExisting: force
            )
            lastRestoredCardCount = restoredCards
            lastRestoredAt = Date()
            lastRestoredSummary = snapshot.backupSummaryLine
            print("[CollectionSync] restored library from cloud backup — \(snapshot.backupSummaryLine)")
            return restoredCards > 0 || snapshot.hasAnyData
        } catch {
            lastRestoreError = error.localizedDescription
            print("[CollectionSync] restore failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Fetch another user's snapshot for use in trade builder.
    func fetchFriendCollection(userID: UUID) async throws -> UserLibraryBackup {
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
        return try JSONDecoder().decode(UserLibraryBackup.self, from: data)
    }

    // MARK: - Private

    @discardableResult
    private func uploadSnapshot(force: Bool) async -> Bool {
        guard let url = AppConfiguration.collectionSyncPutURL else {
            lastUploadError = "Worker URL not configured."
            return false
        }
        guard let token = authService.accessToken, !token.isEmpty else {
            lastUploadError = "Sign in to your Bindr account first."
            return false
        }
        guard case .signedIn(let userID, _) = authService.authState else { return false }
        guard let ctx = modelContext else {
            lastUploadError = "Library not ready yet."
            return false
        }

        isUploading = true
        defer { isUploading = false }

        do {
            let snapshot = try UserLibraryBackupCodec.build(userID: userID, modelContext: ctx)
            guard force || snapshot.hasAnyData else {
                print("[CollectionSync] skip upload — local library is empty")
                lastUploadError = "Nothing to back up yet."
                return false
            }
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
                return false
            }
            lastUploadError = nil
            lastUploadedAt = Date()
            lastUploadedSummary = snapshot.backupSummaryLine
            print("[CollectionSync] uploaded library backup — \(snapshot.backupSummaryLine)")
            return true
        } catch {
            lastUploadError = error.localizedDescription
            return false
        }
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
