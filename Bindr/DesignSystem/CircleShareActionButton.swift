import SwiftUI

/// Circular share action matching the system share sheet row (icon in a circle, label below).
struct CircleShareActionButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let systemImage: String
    let action: () -> Void

    private let circleSize: CGFloat = 60

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))

                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(colorScheme == .dark ? .white : .primary)
                }
                .frame(width: circleSize, height: circleSize)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
