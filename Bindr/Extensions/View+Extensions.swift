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

    /// Flat white post card used in the social feed — light grey border on a
    /// white fill in light mode, grouped background in dark mode.
    func feedPostCardStyle(cornerRadius: CGFloat = 20) -> some View {
        modifier(FeedPostCardModifier(cornerRadius: cornerRadius))
    }

    /// Primary toolbar button style — semibold, neutral `.primary` colour.
    ///
    /// Use on Close / Done / Cancel buttons in sheet toolbars so they read
    /// as part of the glass chrome rather than inheriting the accent tint
    /// injected by `bindrTheme(accent:)`.
    func glassToolbarButton() -> some View {
        self
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
    }

    /// Secondary toolbar button style — medium weight, `.secondary` colour.
    ///
    /// Use on Restore / secondary actions that should sit behind the primary.
    func glassToolbarSecondaryButton() -> some View {
        self
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
    }

    /// Premium red pill badge matching the Social bell alert style.
    func bindrBadge(count: Int) -> some View {
        self.overlay(alignment: .topTrailing) {
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(BindrPalette.alertRed, in: Capsule())
                    .shadow(color: .black.opacity(0.1), radius: 2)
                    .offset(x: 8, y: -6)
            }
        }
    }
}

// Shared flag so ALL GlassCardModifier instances flip together in one render pass,
// avoiding N separate re-renders (one per card) each costing another glass-init hit.
@Observable
@MainActor
final class GlassReadySignal {
    static let shared = GlassReadySignal()
    var isReady = false
}

struct FeedPostCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color(uiColor: .secondarySystemGroupedBackground)
                            : .white
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        colorScheme == .dark
                            ? Color.primary.opacity(0.08)
                            : BindrPalette.feedCardBorder,
                        lineWidth: 1
                    )
            }
    }
}

struct GlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    let cornerRadius: CGFloat
    let interactive: Bool

    func body(content: Content) -> some View {
        let glassReady = GlassReadySignal.shared.isReady
        return content
            .background {
                if #available(iOS 26.0, *), glassReady {
                    let base = Glass.regular.tint(nil)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
                        .glassEffect(interactive ? base.interactive() : base, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.thinMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.08), lineWidth: 1)
            }
            .overlay {
                // Subtle inner top highlight
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.12 : 0.4),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .padding(0.5)
            }
    }
}
