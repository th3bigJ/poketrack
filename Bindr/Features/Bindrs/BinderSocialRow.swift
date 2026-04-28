import SwiftUI

/// Compact horizontal row that appears under a binder's title in
/// ``BinderDetailView``. Shows social context:
///
///   1. **Share state** — only shown when published ("Shared").
///   2. **Likers** — overlapping avatar bubbles for up to four upvoters with a
///      "+N" overflow chip when there are more.
///
/// Sections degrade independently — if there are no likers we hide the avatar
/// stack. The row is purely presentational; it accepts pre-computed data so
/// the parent view stays the source of truth for publishing state.
struct BinderSocialRow: View {
    /// Whether the binder has a `SharedContent` record on the server.
    let isPublished: Bool
    /// People who have upvoted (ordered by recency). Empty when not
    /// published or before the fetch completes.
    let likers: [SocialProfile]
    /// Total upvote count for the binder. May exceed `likers.count` when only
    /// a partial page of voters has been fetched.
    let totalLikeCount: Int
    /// Tap handler for the share section — opens the existing share sheet.
    var onShareTap: () -> Void = {}
    /// Tap handler for the likers row — drills into a "people who upvoted"
    /// list. Optional; pass `nil` to make the avatars non-interactive.
    var onLikersTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if isPublished {
                shareSection
            }
            if !likers.isEmpty {
                likersSection
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Share state

    private var shareSection: some View {
        Button(action: onShareTap) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.green)
                Text("Shared")
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
        .accessibilityLabel("Shared binder, tap to manage")
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

}
