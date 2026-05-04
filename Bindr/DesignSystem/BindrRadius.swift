import CoreGraphics

/// Canonical corner-radius scale for Bindr.
///
/// Adopted to replace the previous patchwork of 6 / 8 / 10 / 12 / 14 / 16 / 20
/// / 24 literals scattered across 50+ files. Use the *semantic* token, not the
/// raw value, so future global tweaks (e.g. tightening every card) only touch
/// this file.
///
/// Recommended pairings:
/// - `xs (6)`  — inline chips / small badges.
/// - `sm (8)`  — list-row inset images, small buttons.
/// - `md (12)` — sheet-internal cards, secondary tiles.
/// - `lg (14)` — **canonical card radius**. Use this for the standard
///   feed/friends/transactions card unless you have a specific reason not to.
/// - `xl (16)` — large cards, hero tiles, full-screen modals.
/// - `xxl (20)` — feature cards, stage banners.
/// - `xxxl (24)` — full-bleed hero surfaces.
///
/// All consumers should construct `RoundedRectangle` with `style: .continuous`
/// — squircle geometry matches iOS 26 Liquid Glass and the system tab bar.
enum BindrRadius {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 14
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 20
    static let xxxl: CGFloat = 24
}
