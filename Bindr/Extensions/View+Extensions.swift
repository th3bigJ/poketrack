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

    /// Containerless — content sits directly on the page background.
    func glassCardStyle(cornerRadius: CGFloat = 16, interactive: Bool = true) -> some View {
        self
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

    /// Frosted track behind tab/segment selectors (`SlidingSegmentedPicker`, form pickers).
    /// Pass a corner radius for rounded-rect tracks; omit for capsule tracks.
    func glassSegmentedTrackStyle(cornerRadius: CGFloat? = nil) -> some View {
        modifier(GlassSegmentedTrackModifier(cornerRadius: cornerRadius))
    }

    /// Liquid Glass capsule for filter chips such as Full / Master / Grand Master set modes.
    func glassFilterChipStyle(isSelected: Bool, accentColor: Color) -> some View {
        modifier(GlassFilterChipModifier(isSelected: isSelected, accentColor: accentColor))
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

    /// Containerless — no glass panel wrapper.
    func clearGlassCardStyle(cornerRadius: CGFloat = 16, interactive: Bool = true) -> some View {
        self
    }

    /// Containerless grid tile — card art and labels on the page background.
    func gridTileGlassStyle(cornerRadius: CGFloat, colorScheme: ColorScheme) -> some View {
        self
    }

    /// Containerless — no glass panel wrapper.
    func nativeGlassPanelStyle(cornerRadius: CGFloat = 24) -> some View {
        self
    }

    /// Containerless — no glass panel wrapper.
    func nativeGlassFullscreenStyle() -> some View {
        self
    }

    /// Containerless feed post — no card wrapper around each row.
    func feedPostCardStyle(cornerRadius: CGFloat = 20) -> some View {
        self
    }

    /// Dark capsule badge for prices overlaid on card/sealed grid thumbnails.
    func cardGridPriceBadgeStyle() -> some View {
        modifier(CardGridPriceBadgeStyle())
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
    func body(content: Content) -> some View {
        content.modifier(GlassSegmentedTrackModifier(cornerRadius: nil, appliesPadding: false))
    }
}

struct GlassSegmentedTrackModifier: ViewModifier {
    /// `nil` = capsule track; otherwise rounded rect (e.g. form sheets).
    var cornerRadius: CGFloat? = nil
    /// When `false`, the caller already applied inner padding (pill toolbar chips).
    var appliesPadding: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if let cornerRadius {
            if appliesPadding {
                applyChrome(to: content.padding(2), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                applyChrome(to: content, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else if appliesPadding {
            applyChrome(to: content.padding(4), in: Capsule(style: .continuous))
        } else {
            applyChrome(to: content, in: Capsule(style: .continuous))
        }
    }

    @ViewBuilder
    private func applyChrome<V: View, S: InsettableShape>(to content: V, in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(Glass.clear.tint(nil).interactive(), in: shape)
                .overlay {
                    shape.strokeBorder(BindrGlassStyle.insetBorder(colorScheme), lineWidth: 1)
                }
        } else {
            content
                .background { shape.fill(.thinMaterial) }
                .overlay {
                    shape.strokeBorder(BindrGlassStyle.insetBorder(colorScheme), lineWidth: 1)
                }
        }
    }
}

struct GlassFilterChipModifier: ViewModifier {
    let isSelected: Bool
    let accentColor: Color

    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if isSelected {
            content
                .background {
                    Capsule(style: .continuous)
                        .bindrAccentFill(accentColor)
                        .shadow(
                            color: (services.theme.isGradientThemeSelected ? services.theme.secondaryAccentColor : accentColor).opacity(0.22),
                            radius: 4,
                            x: 0,
                            y: 2
                        )
                }
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(Glass.clear.tint(nil).interactive(), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(BindrGlassStyle.insetBorder(colorScheme), lineWidth: 1)
                }
        } else {
            content
                .background {
                    ZStack {
                        Capsule(style: .continuous)
                            .fill(.thinMaterial)
                        Capsule(style: .continuous)
                            .fill(BindrGlassStyle.chipTrackFill(colorScheme))
                    }
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(BindrGlassStyle.insetBorder(colorScheme), lineWidth: 1)
                }
        }
    }
}

struct CardGridPriceBadgeStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.72),
                                Color.black.opacity(0.58)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
            }
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            .padding(CardGridLayout.overlayInset)
    }
}
