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

    /// Pill search field chrome — Liquid Glass on iOS 26+, material fallback on earlier OS versions.
    func searchFieldCapsuleChrome(
        darkGlass: SearchFieldChromeGlass = .regularInteractive,
        forceNativeGlass: Bool = true
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

    /// Rounded inline search field chrome — Liquid Glass on iOS 26+, material fallback on earlier OS versions.
    func inlineSearchFieldChrome(
        cornerRadius: CGFloat = 14,
        darkGlass: SearchFieldChromeGlass = .regularInteractive,
        forceNativeGlass: Bool = true
    ) -> some View {
        modifier(
            SearchFieldChromeModifier(
                shape: .rounded,
                cornerRadius: cornerRadius,
                darkGlass: darkGlass,
                forceNativeGlass: forceNativeGlass
            )
        )
    }

    /// Circle chrome for search bar accessory buttons — glass on iOS 26+, material fallback otherwise.
    func searchBarCircleChrome(interactive: Bool = true, forceNativeGlass: Bool = true) -> some View {
        modifier(
            SearchBarCircleChromeModifier(
                interactive: interactive,
                forceNativeGlass: forceNativeGlass
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

    /// Social feed post container — content sits directly on the page background.
    func feedPostCardStyle(cornerRadius: CGFloat = 20) -> some View {
        self
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
            applySearchChrome(to: content, in: Capsule(style: .continuous))
        case .rounded:
            let radius = cornerRadius ?? 14
            applySearchChrome(to: content, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }

    @ViewBuilder
    private func applySearchChrome<S: InsettableShape>(to content: Content, in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(glassEffect, in: shape)
                .overlay { shape.stroke(glassBorderColor, lineWidth: 1) }
        } else {
            content
                .background { shape.fill(.thinMaterial) }
                .overlay { shape.stroke(borderColor, lineWidth: 1) }
        }
    }

    private var borderColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.12)
    }

    private var glassBorderColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.08)
    }

    @available(iOS 26.0, *)
    private var glassEffect: Glass {
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
    var forceNativeGlass: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var glassStroke: Color { Color.primary.opacity(0.1) }

    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26.0, *) {
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
    static func primarySurfaceFill(_ colorScheme: ColorScheme) -> Color {
        .clear
    }

    static func secondarySurfaceFill(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(hex: "303036").opacity(0.78)
            : Color.black.opacity(0.035)
    }

    static func surfaceBorder(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.09)
    }

    static func insetFill(_ colorScheme: ColorScheme) -> Color {
        secondarySurfaceFill(colorScheme)
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
                        .fill(Color.clear)
                        .glassEffect(interactive ? base.interactive() : base, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
    }
}
