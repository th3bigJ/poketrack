import CoreGraphics

/// Canonical spacing scale for Bindr.
///
/// Use these tokens for `padding`, `VStack/HStack` `spacing`, and any other
/// layout gap. Mixing raw 10 / 13 / 18 / 22 values across views is the main
/// reason rows look slightly off when placed next to each other. Pick the
/// nearest token instead of inventing a new value — if a layout truly needs a
/// non-standard gap, add a comment explaining why.
///
/// Recommended pairings:
/// - `xs (4)`  — gap between a label and its caption.
/// - `sm (8)`  — gap between glyph and label, between adjacent chips.
/// - `md (12)` — internal card padding, list-row vertical rhythm.
/// - `lg (16)` — section-level padding, screen edge insets.
/// - `xl (20)` — section separation in a stacked layout.
/// - `xxl (24)` — top-of-screen breathing room before the first card.
/// - `xxxl (32)` — empty-state breathing room.
enum BindrSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32

    /// Gap between card tiles in browse/collection grids.
    static let cardGrid: CGFloat = xs
    /// Screen-edge inset for card grids — keeps tiles large with minimal side gap.
    static let cardGridScreenInset: CGFloat = xs
}

/// Shared layout metrics for card thumbnail grids (browse, collection, wishlist, binders).
enum CardGridLayout {
    /// Gap between cells and columns — tight so cards fill the row.
    static let cellSpacing: CGFloat = BindrSpacing.xs
    /// Screen-edge inset for card grids.
    static let horizontalInset: CGFloat = BindrSpacing.xs
    /// Inset for price / badge overlays on the card image.
    static let overlayInset: CGFloat = BindrSpacing.xs
}
