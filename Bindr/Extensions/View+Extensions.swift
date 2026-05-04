import SwiftUI

extension View {
    /// Applies the given transform if the given condition evaluates to `true`.
    /// - Parameters:
    ///   - condition: A boolean condition to evaluate.
    ///   - transform: A closure that takes the current view and returns a modified version of it.
    /// - Returns: The original view if `condition` is `false`, or the modified view if `condition` is `true`.
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    func glassCardStyle(cornerRadius: CGFloat = 16, interactive: Bool = true) -> some View {
        self.modifier(GlassCardModifier(cornerRadius: cornerRadius, interactive: interactive))
    }
}

struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool

    func body(content: Content) -> some View {
        content
            .background {
                if #available(iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.clear)
                        .glassEffect(interactive ? .clear.tint(nil).interactive() : .clear.tint(nil), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
    }
}
