import SwiftUI

struct TradeRowView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    let tradeWithItems: TradeWithItems
    let currentUserID: UUID
    let counterpartProfile: SocialProfile?

    private var trade: Trade { tradeWithItems.trade }
    private var myItems: [TradeItem] { tradeWithItems.myItems(currentUserID: currentUserID) }
    private var theirItems: [TradeItem] { tradeWithItems.theirItems(currentUserID: currentUserID) }
    private var myCash: Double { tradeWithItems.myCash(currentUserID: currentUserID) }
    private var theirCash: Double { tradeWithItems.theirCash(currentUserID: currentUserID) }
    private var myQuantity: Int { myItems.reduce(0) { $0 + max($1.quantity, 1) } }
    private var theirQuantity: Int { theirItems.reduce(0) { $0 + max($1.quantity, 1) } }

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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if let profile = counterpartProfile {
                    ProfileAvatarView(profile: profile, size: 46)
                } else {
                    Circle()
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .frame(width: 46, height: 46)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(counterpartProfile.map { $0.displayName ?? "@\($0.username)" } ?? "Loading...")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(nextStepText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(nextStepColor)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 5) {
                    TradeStatusBadge(status: trade.status, label: statusLabel)
                    if let date = trade.updatedAt {
                        Text(date, formatter: relativeDateFormatter)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            teaserStrip
        }
        .padding(14)
        .background(Color(uiColor: colorScheme == .dark ? .secondarySystemBackground : .systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }

    private var nextStepText: String {
        switch trade.status {
        case .pending:
            return tradeWithItems.needsResponse(from: currentUserID) ? "Waiting for you to accept, counter or decline" : "Waiting for them to respond"
        case .countered:
            return tradeWithItems.needsResponse(from: currentUserID) ? "Counter offer needs your review" : "Counter offer sent"
        case .accepted:
            if tradeWithItems.myCompleted(currentUserID: currentUserID) {
                return "You confirmed. Waiting for them"
            }
            if tradeWithItems.theirCompleted(currentUserID: currentUserID) {
                return "They confirmed. Complete your side"
            }
            return "Accepted. Confirm once exchanged"
        case .complete:
            return "Completed"
        case .cancelled:
            return "Cancelled"
        }
    }

    private var nextStepColor: Color {
        switch trade.status {
        case .pending, .countered:
            return tradeWithItems.needsResponse(from: currentUserID) ? BindrPalette.binderGold : .secondary
        case .accepted:
            return tradeWithItems.myCompleted(currentUserID: currentUserID) ? .secondary : BindrPalette.ownedGreen
        case .complete:
            return BindrPalette.ownedGreen
        case .cancelled:
            return BindrPalette.alertRed
        }
    }

    private var borderColor: Color {
        switch trade.status {
        case .pending, .countered:
            return tradeWithItems.needsResponse(from: currentUserID) ? BindrPalette.binderGold.opacity(0.30) : Color.primary.opacity(0.08)
        case .accepted:
            return BindrPalette.ownedGreen.opacity(0.28)
        case .complete:
            return BindrPalette.ownedGreen.opacity(0.18)
        case .cancelled:
            return BindrPalette.alertRed.opacity(0.20)
        }
    }

    private var teaserStrip: some View {
        HStack(spacing: 8) {
            tradePreviewSide(
                title: "You give",
                cards: myQuantity,
                cash: myCash,
                items: myItems,
                tint: BindrPalette.alertRed
            )

            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.65))

            tradePreviewSide(
                title: "You get",
                cards: theirQuantity,
                cash: theirCash,
                items: theirItems,
                tint: BindrPalette.ownedGreen
            )
        }
    }

    private func tradePreviewSide(title: String, cards: Int, cash: Double, items: [TradeItem], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.45)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(sideSummary(cards: cards, cash: cash))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }

            HStack(spacing: -7) {
                let previewItems = Array(items.prefix(cash > 0 ? 2 : 3))
                if cash > 0 {
                    TradeRowCashPreview(amount: cash, tint: tint)
                }
                ForEach(previewItems) { item in
                    TradeRowCardPreview(item: item)
                }
                let remaining = max(0, items.count - previewItems.count)
                if remaining > 0 {
                    Text("+\(remaining)")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(tint)
                        .frame(width: 34, height: 44)
                        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(tint.opacity(0.25), lineWidth: 1)
                        }
                }
                if items.isEmpty && cash == 0 {
                    Text("None")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(height: 44)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(tint.opacity(colorScheme == .dark ? 0.14 : 0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sideSummary(cards: Int, cash: Double) -> String {
        var parts: [String] = []
        if cards > 0 {
            parts.append("\(cards) card\(cards == 1 ? "" : "s")")
        }
        if cash > 0 {
            parts.append("\(services.priceDisplay.currency.symbol)\(String(format: "%.2f", cash))")
        }
        return parts.isEmpty ? "Nothing" : parts.joined(separator: " + ")
    }
}

private struct TradeRowCashPreview: View {
    let amount: Double
    let tint: Color
    @Environment(AppServices.self) private var services

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "banknote.fill")
                .font(.system(size: 12, weight: .bold))
            Text("\(services.priceDisplay.currency.symbol)\(String(format: "%.2f", amount))")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(tint)
        .frame(width: 34, height: 44)
        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        }
    }
}

private struct TradeRowCardPreview: View {
    @Environment(AppServices.self) private var services

    let item: TradeItem
    @State private var card: Card?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let imageURLString = card?.displayImageSrc {
                CachedAsyncImage(url: AppConfiguration.imageURL(relativePath: imageURLString)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: 34, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
        }
        .overlay(alignment: .bottomTrailing) {
            if item.quantity > 1 {
                Text("x\(item.quantity)")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(.black.opacity(0.72), in: Capsule())
                    .padding(2)
            }
        }
        .task {
            card = await services.cardData.loadCard(masterCardId: item.cardID)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .overlay {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
    }
}

private let relativeDateFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
}()
