import Foundation

enum FreemiumGate {
    /// Free tier allows up to 10 collection **rows** (matches build.md gate on count).
    static func canAddCollectionRow(currentRowCount: Int, isPremium: Bool) -> Bool {
        isPremium || currentRowCount < 10
    }
}
