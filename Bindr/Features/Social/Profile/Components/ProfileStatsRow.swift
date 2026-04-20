import SwiftUI

struct ProfileStatsRow: View {
    let cardCount: Int
    let totalValue: String
    let followerCount: Int
    let binderCount: Int
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 0) {
            statCell(label: "CARDS", value: "\(cardCount)")
            divider
            statCell(label: "VALUE", value: totalValue)
            divider
            statCell(label: "FOLLOWERS", value: "\(followerCount)")
            divider
            statCell(label: "BINDRS", value: "\(binderCount)")
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }
    
    private var divider: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
            .frame(width: 1, height: 24)
    }
    
    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }
}
