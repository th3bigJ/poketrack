import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset

    @Query(sort: \LedgerLine.occurredAt, order: .reverse) private var allLedgerLines: [LedgerLine]
    @Query private var collectionItems: [CollectionItem]

    @State private var totalMarketValue: Double? = nil
    @State private var totalCostBasis: Double = 0
    @State private var isLoadingValue = false

    private var recentLines: [LedgerLine] {
        Array(allLedgerLines.prefix(10))
    }

    private var gainLoss: Double? {
        guard let market = totalMarketValue else { return nil }
        return market - totalCostBasis
    }

    private var gainLossPct: Double? {
        guard let gl = gainLoss, totalCostBasis > 0 else { return nil }
        return (gl / totalCostBasis) * 100
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                collectionValueCard
                recentActivityCard
            }
            .padding(16)
        }
        .safeAreaPadding(.top, rootFloatingChromeInset)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: collectionItems.count) {
            await computeValueAndBasis()
        }
    }

    // MARK: - Section Cards

    private var collectionValueCard: some View {
        DashboardCard(title: "Collection Value") {
            if isLoadingValue {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    if let market = totalMarketValue {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatCurrency(market))
                                .font(.title.bold())
                            Text("Market value")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            if let gl = gainLoss {
                                Text((gl >= 0 ? "+" : "") + formatCurrency(gl))
                                    .font(.headline)
                                    .foregroundStyle(gl >= 0 ? .green : .red)
                            }
                            if let pct = gainLossPct {
                                Text(String(format: "%.1f%%", pct))
                                    .font(.caption)
                                    .foregroundStyle(pct >= 0 ? .green : .red)
                            }
                        }
                    } else {
                        Text("No pricing data yet")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var recentActivityCard: some View {
        DashboardCard(title: "Recent Activity") {
            if recentLines.isEmpty {
                Text("No transactions yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(recentLines) { line in
                        HStack(spacing: 10) {
                            Image(systemName: directionIcon(for: line))
                                .font(.caption)
                                .foregroundStyle(directionColor(for: line))
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(line.lineDescription)
                                    .font(.caption)
                                    .lineLimit(1)
                                Text(line.occurredAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("×\(line.quantity)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                        if line.id != recentLines.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func computeValueAndBasis() async {
        isLoadingValue = true
        defer { isLoadingValue = false }

        var totalValue = 0.0
        var totalCost = 0.0

        for item in collectionItems {
            if let card = await services.cardData.loadCard(masterCardId: item.cardID) {
                if let usd = await services.pricing.usdPriceForVariant(for: card, variantKey: item.variantKey) {
                    totalValue += usd * Double(item.quantity) * services.pricing.usdToGbp
                }
            }
            totalCost += (item.purchasePrice ?? 0) * Double(item.quantity)
        }

        totalMarketValue = totalValue > 0 ? totalValue : nil
        totalCostBasis = totalCost
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "GBP"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "£\(String(format: "%.2f", value))"
    }

    private func directionIcon(for line: LedgerLine) -> String {
        guard let dir = LedgerDirection(rawValue: line.direction) else { return "circle" }
        switch dir {
        case .bought:        return "cart.fill"
        case .packed:        return "shippingbox.fill"
        case .sold:          return "dollarsign.circle.fill"
        case .tradedIn:      return "arrow.left.arrow.right.circle.fill"
        case .tradedOut:     return "arrow.left.arrow.right.circle"
        case .giftedIn:      return "gift.fill"
        case .giftedOut:     return "gift"
        case .adjustmentIn:  return "plus.circle.fill"
        case .adjustmentOut: return "minus.circle.fill"
        }
    }

    private func directionColor(for line: LedgerLine) -> Color {
        guard let dir = LedgerDirection(rawValue: line.direction) else { return .secondary }
        switch dir {
        case .bought, .packed, .tradedIn, .giftedIn, .adjustmentIn:
            return .green
        case .sold, .tradedOut, .giftedOut, .adjustmentOut:
            return .red
        }
    }
}

private struct DashboardCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
