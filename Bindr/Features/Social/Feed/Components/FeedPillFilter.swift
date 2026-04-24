import SwiftUI

struct FeedPillFilter: View {
    @Binding var selectedScope: SocialFeedService.FeedScope
    var unreadScopes: Set<SocialFeedService.FeedScope> = []
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            pill(for: .following, title: "Following", icon: "person.2.fill")
            pill(for: .everyone, title: "Everyone", icon: "globe")
            pill(for: .mine, title: "Mine", icon: "person.fill")
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func pill(for scope: SocialFeedService.FeedScope, title: String, icon: String) -> some View {
        let isSelected = selectedScope == scope
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selectedScope = scope
            }
            Haptics.lightImpact()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if unreadScopes.contains(scope) && !isSelected {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "6366f1"), Color(hex: "4f46e5")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color(hex: "6366f1").opacity(0.4), radius: 8, y: 3)
                } else {
                    Capsule()
                        .fill(Color.secondary.opacity(0.1))
                }
            }
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .animation(.spring(response: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}
