import SwiftUI

struct TradeRowView: View {
    @Environment(AppServices.self) private var services

    let tradeWithItems: TradeWithItems
    let currentUserID: UUID
    let counterpartProfile: SocialProfile?

    private var trade: Trade { tradeWithItems.trade }
    private var myItems: [TradeItem] { tradeWithItems.myItems(currentUserID: currentUserID) }
    private var theirItems: [TradeItem] { tradeWithItems.theirItems(currentUserID: currentUserID) }
    private var myCash: Double { tradeWithItems.myCash(currentUserID: currentUserID) }
    private var theirCash: Double { tradeWithItems.theirCash(currentUserID: currentUserID) }
    private var statusLabel: String? {
        guard trade.status == .accepted else { return nil }
        if tradeWithItems.myCompleted(currentUserID: currentUserID) {
            return "Waiting"
        }
        if tradeWithItems.theirCompleted(currentUserID: currentUserID) {
            return "Ready"
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            if let profile = counterpartProfile {
                ProfileAvatarView(profile: profile, size: 44)
            } else {
                Circle()
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(counterpartProfile.map { $0.displayName ?? "@\($0.username)" } ?? "Loading…")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("You: \(myItems.count) card\(myItems.count == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("Them: \(theirItems.count) card\(theirItems.count == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if myCash > 0 || theirCash > 0 {
                    HStack(spacing: 4) {
                        if myCash > 0 {
                            Text("You add \(services.priceDisplay.currency.symbol)\(myCash, format: .number.precision(.fractionLength(2)))")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(hex: "52C97C"))
                        }
                        if theirCash > 0 {
                            Text("They add \(services.priceDisplay.currency.symbol)\(theirCash, format: .number.precision(.fractionLength(2)))")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(hex: "52C97C"))
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                TradeStatusBadge(status: trade.status, label: statusLabel)
                if let date = trade.updatedAt {
                    Text(date, formatter: relativeDateFormatter)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .systemBackground))
        .contentShape(Rectangle())
    }
}

private let relativeDateFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
}()
