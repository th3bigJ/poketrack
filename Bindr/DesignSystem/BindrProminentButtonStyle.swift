import SwiftUI

/// Theme-safe filled CTA. Replaces `.borderedProminent`, which uses the
/// atmosphere accent as both fill and label tint — invisible on Classic dark
/// (white-on-white) and other light accents.
struct BindrProminentButtonStyle: ButtonStyle {
    enum Size {
        case regular
        case compact
        case flexible
    }

    enum Shape {
        case roundedRect
        case capsule
    }

    var size: Size = .regular
    var shape: Shape = .roundedRect
    var disabled: Bool = false

    @Environment(\.bindrAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppServices.self) private var services

    func makeBody(configuration: Configuration) -> some View {
        let usesGradient = services.theme.isGradientThemeSelected
        let labelColor = usesGradient ? Color.white : accent.bindrLabelOnFill(in: colorScheme)

        configuration.label
            .font(font)
            .foregroundStyle(labelColor)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(height: height)
            .padding(.horizontal, horizontalPadding)
            .background {
                switch shape {
                case .roundedRect:
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .bindrAccentFill(accent, logoOpacity: 0.96)
                case .capsule:
                    Capsule(style: .continuous)
                        .bindrAccentFill(accent, logoOpacity: 0.96)
                }
            }
            .shadow(
                color: accent.opacity(colorScheme == .dark ? 0.35 : 0.18),
                radius: size == .compact ? 6 : 12,
                x: 0,
                y: size == .compact ? 3 : 6
            )
            .opacity(disabled ? 0.5 : (configuration.isPressed ? 0.90 : 1.0))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }

    private var font: Font {
        switch size {
        case .regular, .flexible:
            return .system(size: 17, weight: .semibold)
        case .compact:
            return .system(size: 15, weight: .semibold)
        }
    }

    private var height: CGFloat? {
        switch size {
        case .regular:
            return 54
        case .compact:
            return 36
        case .flexible:
            return nil
        }
    }

    private var fillsWidth: Bool {
        size == .regular || size == .flexible
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .regular, .flexible:
            return 0
        case .compact:
            return BindrSpacing.md
        }
    }

    private var cornerRadius: CGFloat {
        switch size {
        case .regular, .flexible:
            return BindrRadius.xl
        case .compact:
            return BindrRadius.lg
        }
    }
}

extension View {
    func bindrProminentButtonStyle(
        size: BindrProminentButtonStyle.Size = .regular,
        shape: BindrProminentButtonStyle.Shape = .roundedRect,
        disabled: Bool = false
    ) -> some View {
        buttonStyle(BindrProminentButtonStyle(size: size, shape: shape, disabled: disabled))
    }
}
