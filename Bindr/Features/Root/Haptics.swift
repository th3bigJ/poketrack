import UIKit

/// Centralized haptic feedback using `UIImpactFeedbackGenerator` and `UISelectionFeedbackGenerator`
/// ([Human Interface Guidelines — Haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)).
enum Haptics {
    private static let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let rigidImpactGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    /// Buttons and icon taps in chrome (search bar controls, filter when it’s a plain button).
    static func lightImpact() {
        lightImpactGenerator.prepare()
        lightImpactGenerator.impactOccurred()
    }

    /// State-changing actions where the user wants a deliberate confirmation —
    /// upvote/downvote, follow/unfollow, wishlist add, friend accept.
    static func mediumImpact() {
        mediumImpactGenerator.prepare()
        mediumImpactGenerator.impactOccurred()
    }

    /// Crisp tactile click for posting/sending — comments, new posts, share.
    static func rigidImpact() {
        rigidImpactGenerator.prepare()
        rigidImpactGenerator.impactOccurred()
    }

    /// Tab selection and other discrete picks (matches system tab bar feel).
    static func selectionChanged() {
        selectionGenerator.prepare()
        selectionGenerator.selectionChanged()
    }

    /// Resolved positive outcome — friend request accepted, save succeeded.
    static func success() {
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.success)
    }

    /// Action failed — vote rejected by server, save error.
    static func error() {
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.error)
    }

    /// Cautionary touch — destructive confirmations, blocked actions.
    static func warning() {
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.warning)
    }
}
