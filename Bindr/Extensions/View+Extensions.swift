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

    /// Secondary inset surface inside a glass card — fact rows, attack blocks, list rows.
    func glassInsetStyle(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassInsetModifier(cornerRadius: cornerRadius))
    }

    /// Small circular inset control, e.g. icon buttons inside a glass card.
    func glassInsetCircleStyle() -> some View {
        modifier(GlassInsetCircleModifier())
    }

    /// Capsule track for segmented controls and chip pickers inside glass cards.
    func glassPillTrackStyle() -> some View {
        modifier(GlassPillTrackModifier())
    }

    /// Pill search field chrome — white fill in light mode, glass/material in dark.
    func searchFieldCapsuleChrome(
        darkGlass: SearchFieldChromeGlass = .regularInteractive,
        forceNativeGlass: Bool = false
    ) -> some View {
        modifier(
            SearchFieldChromeModifier(
                shape: .capsule,
                cornerRadius: nil,
                darkGlass: darkGlass,
                forceNativeGlass: forceNativeGlass
            )
        )
    }

    /// Rounded inline search field chrome — white fill in light mode, glass/material in dark.
    func inlineSearchFieldChrome(cornerRadius: CGFloat = 14, darkGlass: SearchFieldChromeGlass = .regularInteractive) -> some View {
        modifier(
            SearchFieldChromeModifier(
                shape: .rounded,
                cornerRadius: cornerRadius,
                darkGlass: darkGlass,
                forceNativeGlass: false
            )
        )
    }

    /// Circle chrome for floating header / search accessory buttons — translucent material in light mode, clear glass in dark.
    func searchBarCircleChrome(interactive: Bool = true) -> some View {
        modifier(
            SearchBarCircleChromeModifier(
                interactive: interactive
            )
        )
    }

    /// Unfilled iOS 26 Liquid Glass surface for content nested inside a larger glass panel.
    func clearGlassCardStyle(cornerRadius: CGFloat = 16, interactive: Bool = true) -> some View {
        modifier(ClearGlassCardModifier(cornerRadius: cornerRadius, interactive: interactive))
    }

    /// Full regular Liquid Glass panel without an opaque or tinted base fill.
    func nativeGlassPanelStyle(cornerRadius: CGFloat = 24) -> some View {
        modifier(NativeGlassPanelModifier(cornerRadius: cornerRadius))
    }

    /// Edge-to-edge regular Liquid Glass clipped to the app window's display shape.
    func nativeGlassFullscreenStyle() -> some View {
        modifier(NativeGlassFullscreenModifier())
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

enum SearchFieldChromeGlass {
    case regularInteractive
    case clearInteractive
    case clear
}

enum SearchFieldChromeShape {
    case capsule
    case rounded
}

struct SearchFieldChromeModifier: ViewModifier {
    let shape: SearchFieldChromeShape
    let cornerRadius: CGFloat?
    let darkGlass: SearchFieldChromeGlass
    let forceNativeGlass: Bool

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        switch shape {
        case .capsule:
            if #available(iOS 26.0, *), forceNativeGlass {
                content
                    .glassEffect(darkGlassEffect, in: Capsule(style: .continuous))
                    .overlay { Capsule(style: .continuous).stroke(glassBorderColor, lineWidth: 1) }
            } else if colorScheme == .light {
                content
                    .background { Capsule(style: .continuous).fill(.white) }
                    .overlay { Capsule(style: .continuous).stroke(borderColor, lineWidth: 1) }
            } else if #available(iOS 26.0, *) {
                content
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    }
                    .glassEffect(darkGlassEffect, in: Capsule(style: .continuous))
                    .overlay { Capsule(style: .continuous).stroke(borderColor, lineWidth: 1) }
            } else {
                content
                    .background { Capsule(style: .continuous).fill(.thinMaterial) }
                    .overlay { Capsule(style: .continuous).stroke(borderColor, lineWidth: 1) }
            }
        case .rounded:
            let radius = cornerRadius ?? 14
            let rect = RoundedRectangle(cornerRadius: radius, style: .continuous)
            if #available(iOS 26.0, *), forceNativeGlass {
                content
                    .glassEffect(darkGlassEffect, in: rect)
                    .overlay { rect.stroke(glassBorderColor, lineWidth: 1) }
            } else if colorScheme == .light {
                content
                    .background { rect.fill(.white) }
                    .overlay { rect.stroke(borderColor, lineWidth: 1) }
            } else if #available(iOS 26.0, *) {
                content
                    .background { rect.fill(Color.primary.opacity(0.06)) }
                    .glassEffect(darkGlassEffect, in: rect)
                    .overlay { rect.stroke(borderColor, lineWidth: 1) }
            } else {
                content
                    .background { rect.fill(.thinMaterial) }
                    .overlay { rect.stroke(borderColor, lineWidth: 1) }
            }
        }
    }

    private var borderColor: Color {
        if colorScheme == .light {
            return BindrPalette.feedCardBorder
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.12)
    }

    private var glassBorderColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.08)
    }

    @available(iOS 26.0, *)
    private var darkGlassEffect: Glass {
        switch darkGlass {
        case .regularInteractive:
            return Glass.regular.tint(nil).interactive()
        case .clearInteractive:
            return Glass.clear.tint(nil).interactive()
        case .clear:
            return Glass.clear.tint(nil)
        }
    }
}

struct SearchBarCircleChromeModifier: ViewModifier {
    var interactive: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    private var glassStroke: Color { Color.primary.opacity(0.1) }

    func body(content: Content) -> some View {
        Group {
            if colorScheme == .light {
                content
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(BindrGlassStyle.insetBorder(colorScheme), lineWidth: 0.5)
                    }
                    .contentShape(Circle())
            } else if #available(iOS 26.0, *) {
                content
                    .frame(width: 44, height: 44)
                    .glassEffect(
                        interactive ? Glass.clear.tint(nil).interactive() : Glass.clear.tint(nil),
                        in: Circle()
                    )
                    .contentShape(Circle())
            } else {
                content
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(glassStroke, lineWidth: 0.5)
                    }
                    .contentShape(Circle())
            }
        }
    }
}

private struct ClearGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let interactive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if #available(iOS 26.0, *) {
                content
                    .glassEffect(
                        interactive ? Glass.clear.tint(nil).interactive() : Glass.clear.tint(nil),
                        in: shape
                    )
                    .overlay {
                        shape.stroke(BindrGlassStyle.insetBorder(colorScheme), lineWidth: 1)
                    }
            } else {
                content
                    .background(.thinMaterial, in: shape)
                    .overlay {
                        shape.stroke(BindrGlassStyle.insetBorder(colorScheme), lineWidth: 1)
                    }
            }
        }
    }
}

private struct NativeGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 12) {
                    content
                        .glassEffect(Glass.regular.tint(nil), in: shape)
                }
            } else {
                content.background(.thinMaterial, in: shape)
            }
        }
    }
}

private struct NativeGlassFullscreenModifier: ViewModifier {
    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 12) {
                    content
                        .glassEffect(Glass.regular.tint(nil), in: ContainerRelativeShape())
                }
            } else {
                content.background(.thinMaterial, in: ContainerRelativeShape())
            }
        }
    }
}

enum BindrGlassStyle {
    static func insetFill(_ colorScheme: ColorScheme) -> Color {
        Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04)
    }

    static func insetBorder(_ colorScheme: ColorScheme) -> Color {
        Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.08)
    }

    static func chipTrackFill(_ colorScheme: ColorScheme) -> Color {
        Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06)
    }
}

struct GlassInsetModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(BindrGlassStyle.insetFill(colorScheme))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(BindrGlassStyle.insetBorder(colorScheme), lineWidth: 1)
            }
    }
}

struct GlassInsetCircleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                Circle()
                    .fill(BindrGlassStyle.insetFill(colorScheme))
            }
            .overlay {
                Circle()
                    .stroke(BindrGlassStyle.insetBorder(colorScheme), lineWidth: 1)
            }
    }
}

struct GlassPillTrackModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                Capsule(style: .continuous)
                    .fill(BindrGlassStyle.chipTrackFill(colorScheme))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(BindrGlassStyle.insetBorder(colorScheme), lineWidth: 1)
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
                        .fill(BindrGlassStyle.insetFill(colorScheme))
                        .glassEffect(interactive ? base.interactive() : base, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.thinMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(BindrGlassStyle.insetBorder(colorScheme), lineWidth: 1)
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
