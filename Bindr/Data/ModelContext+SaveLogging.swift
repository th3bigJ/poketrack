import Foundation
import SwiftData
import OSLog

extension ModelContext {
    private static let saveLog = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Bindr",
        category: "ModelContextSave"
    )

    /// Persists pending changes, logging failures instead of silently dropping them via `try?`.
    /// Use this for writes to user-owned library data (collection, binders, decks, value history)
    /// where a swallowed save is silent data loss. Skips work when there is nothing to persist.
    ///
    /// - Returns: `true` when the save succeeded (or there was nothing to save), `false` when it
    ///   failed. Call sites doing optimistic UI (e.g. dismissing a sheet) should check the result
    ///   and react instead of assuming success.
    @discardableResult
    func saveLogging(_ context: String = #function) -> Bool {
        guard hasChanges else { return true }
        do {
            try save()
            return true
        } catch {
            Self.saveLog.error("save failed in \(context, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
