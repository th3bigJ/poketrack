import SwiftUI

/// Grouped menu card with a section title, matching the More tab layout.
struct BindrMenuSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.sm) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, BindrSpacing.md)

            VStack(spacing: 0) {
                content
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

/// Shared row label for More and Settings menus — colorful glyph backdrop and trailing chevron.
struct BindrMenuRowLabel: View {
    let title: String
    let systemImage: String
    let color: Color
    var trailingSymbol: String = "chevron.right"

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Image(systemName: trailingSymbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.45))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

/// Navigation row for settings-style menus opened from the More tab.
struct BindrMenuNavigationRow<Destination: View>: View {
    let title: String
    let systemImage: String
    let color: Color
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            BindrMenuRowLabel(title: title, systemImage: systemImage, color: color)
        }
        .buttonStyle(.plain)
    }
}
