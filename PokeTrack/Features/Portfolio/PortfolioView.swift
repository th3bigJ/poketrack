import Charts
import SwiftData
import SwiftUI

struct PortfolioView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Query(sort: \CollectionCard.addedAt, order: .reverse) private var collectionCards: [CollectionCard]
    @Query(sort: \PortfolioSnapshot.date, order: .forward) private var snapshots: [PortfolioSnapshot]

    @State private var totalGBP: Double = 0
    @State private var isCalculating = false

    var body: some View {
        List {
            Section("Current value") {
                if isCalculating {
                    ProgressView()
                } else {
                    Text(String(format: "£%.2f", totalGBP))
                        .font(.title.bold())
                }
            }

            if services.store.isPremium {
                Section("History") {
                    if snapshots.isEmpty {
                        Text("Open the app on a new day to record your first snapshot.")
                            .foregroundStyle(.secondary)
                    } else {
                        Chart(snapshots) { s in
                            LineMark(
                                x: .value("Date", s.date),
                                y: .value("GBP", s.totalValueGBP)
                            )
                        }
                        .frame(height: 200)
                    }
                }
            } else {
                Section {
                    Label("Portfolio history is a Premium feature.", systemImage: "lock.fill")
                }
            }
        }
        .navigationTitle("Portfolio")
        .task { await recalc() }
        .refreshable { await recalc() }
    }

    private func recalc() async {
        isCalculating = true
        defer { isCalculating = false }

        let total = await PortfolioCalculator.calculatePortfolioValueGBP(
            collectionCards: collectionCards,
            cardLookup: { mid, set in
                services.cardData.card(masterCardId: mid, setCode: set)
            },
            pricing: { card, printing in
                await services.pricing.gbpPrice(for: card, printing: printing)
            }
        )
        totalGBP = total

        if services.store.isPremium {
            PortfolioSnapshotScheduler.recordSnapshotIfNeeded(
                modelContext: modelContext,
                totalGBP: total,
                cardCount: collectionCards.count,
                sealedGBP: 0
            )
        }
    }
}
