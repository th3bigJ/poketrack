import Foundation
import SwiftData

@MainActor
enum PortfolioSnapshotScheduler {
    /// Inserts a snapshot when the calendar day changed since the last snapshot (app opened after local midnight).
    static func recordSnapshotIfNeeded(
        modelContext: ModelContext,
        totalGBP: Double,
        cardCount: Int,
        sealedGBP: Double
    ) {
        let desc = FetchDescriptor<PortfolioSnapshot>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let last = try? modelContext.fetch(desc).first
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        if let last {
            let lastDay = cal.startOfDay(for: last.date)
            if lastDay == today { return }
        }
        let snap = PortfolioSnapshot(
            date: Date(),
            totalValueGBP: totalGBP,
            cardCount: cardCount,
            sealedValueGBP: sealedGBP
        )
        modelContext.insert(snap)
    }
}
