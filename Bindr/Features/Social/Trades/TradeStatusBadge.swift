import SwiftUI

struct TradeStatusBadge: View {
    let status: TradeStatus

    var body: some View {
        Text(status.displayName)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.3)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }

    var color: Color {
        switch status {
        case .pending: return Color(hex: "E8B84B")
        case .countered: return Color(hex: "E8934B")
        case .accepted: return Color(hex: "52C97C")
        case .complete: return Color(hex: "52C97C").opacity(0.7)
        case .cancelled: return Color(hex: "E05252")
        }
    }
}
