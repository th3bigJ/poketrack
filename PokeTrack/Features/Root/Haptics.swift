import UIKit

/// Centralized haptic feedback using `UIImpactFeedbackGenerator` and `UISelectionFeedbackGenerator`
/// ([Human Interface Guidelines — Haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)).
enum Haptics {
    private static let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let selectionGenerator = UISelectionFeedbackGenerator()

    /// Buttons and icon taps in chrome (search bar controls, filter when it’s a plain button).
    static func lightImpact() {
        lightImpactGenerator.prepare()
        lightImpactGenerator.impactOccurred()
    }

    /// Tab selection and other discrete picks (matches system tab bar feel).
    static func selectionChanged() {
        selectionGenerator.prepare()
        selectionGenerator.selectionChanged()
    }
}
