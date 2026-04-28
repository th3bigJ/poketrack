import SwiftUI

/// Compact horizontal row that appears under a binder's title in
/// ``BinderDetailView``. Shows three pieces of social/value context:
///
///   1. **Share state** — a lock icon ("Private") when the binder hasn't been
///      published, or a people icon + "Shared" label + count when it has.
///   2. **Likers** — overlapping avatar bubbles for up to four upvoters with a
///      "+N" overflow chip when there are more.
///   3. **Weekly value change** — a green/red pill showing the binder's USD
///      gain or loss over the past 7 days, formatted in the user's display
///      currency. Hidden when no trend data is available yet.
///
/// All three sections degrade independently — if there are no likers we just
/// hide the avatar stack; if pricing trends haven't loaded the change pill
/// stays out of the way. The row is purely presentational; it accepts
/// pre-computed data so the parent view stays the source of truth for
/// publishing state and pricing math.
struct BinderSocialRow: View {
    /// Whether the binder has a `SharedContent` record on the server.
    let isPublished: Bool
    /// People who have upvoted (ordered by recency). Empty when not
    /// published or before the fetch completes.
    let likers: [SocialProfile]
    /// Total upvote count for the binder. May exceed `likers.count` when only
    /// a partial page of voters has been fetched.
    let totalLikeCount: Int
    /// Net USD change over the past 7 days, summed across all slots. `nil`
    /// when trends haven't been resolved yet.
    let weeklyUSDChange: Double?
    /// User-selected currency + USD→GBP rate, used to format the change pill.
    let currencySymbol: String
    let usdToGbp: Double
    let displayInGBP: Bool
    /// Tap handler for the share section — opens the existing share sheet.
    var onShareTap: () -> Void = {}
    /// Tap handler for the likers row — drills into a "people who upvoted"
    /// list. Optional; pass `nil` to make the avatars non-interactive.
    var onLikersTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            shareSection
            if !likers.isEmpty {
                likersSection
            }
            Spacer(minLength: 0)
            if let weeklyUSDChange {
                weeklyChangePill(usd: weeklyUSDChange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Share state

    private var shareSection: some View {
        Button(action: onShareTap) {
            HStack(spacing: 6) {
                Image(systemName: isPublished ? "person.2.fill" : "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isPublished ? Color.green : Color.secondary)
                Text(isPublished ? "Shared" : "Private")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPublished ? "Shared binder, tap to manage" : "Private binder, tap to share")
    }

    // MARK: - Likers row

    @ViewBuilder
    private var likersSection: some View {
        if let onLikersTap {
            Button(action: onLikersTap) { likersStack }
                .buttonStyle(.plain)
        } else {
            likersStack
        }
    }

    private var likersStack: some View {
        let visible = Array(likers.prefix(4))
        let extra = max(0, totalLikeCount - visible.count)

        return HStack(spacing: -8) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, profile in
                ProfileAvatarView(profile: profile, size: 22)
                    .overlay(
                        Circle()
                            .stroke(Color(uiColor: .systemBackground), lineWidth: 1.5)
                    )
                    .zIndex(Double(visible.count - index))
            }

            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 22, minHeight: 22)
                    .padding(.horizontal, 4)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.18))
                            .overlay(
                                Capsule()
                                    .stroke(Color(uiColor: .systemBackground), lineWidth: 1.5)
                            )
                    )
                    .zIndex(0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(totalLikeCount) \(totalLikeCount == 1 ? "person likes" : "people like") this binder")
    }

    // MARK: - Weekly change

    @ViewBuilder
    private func weeklyChangePill(usd: Double) -> some View {
        // Treat near-zero as flat — avoids showing "↑ £0" when prices barely moved.
        let absUSD = abs(usd)
        if absUSD < 0.5 {
            EmptyView()
        } else {
            let amount = displayInGBP ? absUSD * usdToGbp : absUSD
            let isUp = usd >= 0
            let tint: Color = isUp ? .green : .red
            HStack(spacing: 4) {
                Image(systemName: isUp ? "arrow.up" : "arrow.down")
                    .font(.system(size: 10, weight: .bold))
                Text(formatChange(amount: amount))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Text("this week")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
            )
            .accessibilityLabel("\(isUp ? "Up" : "Down") \(formatChange(amount: amount)) this week")
        }
    }

    private func formatChange(amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if amount >= 1000 {
            formatter.maximumFractionDigits = 0
            formatter.minimumFractionDigits = 0
        } else {
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
        }
        let pretty = formatter.string(from: NSNumber(value: amount)) ?? "0"
        return "\(currencySymbol)\(pretty)"
    }
}
