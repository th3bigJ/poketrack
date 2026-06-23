import SwiftUI

/// Semantic brand colors used across Bindr to identify *content types*.
///
/// These are intentionally **independent of the user's chosen theme accent**:
/// they're brand identifiers (gold = binder / wishlist, blue = deck, violet =
/// wishlist-in-feed, etc.) the same way Twitter blue or Twitch purple are
/// identity colors. The user's theme accent — read via
/// `@Environment(\.bindrAccent)` or `services.theme.accentColor` — is reserved
/// for selection chrome, emphasis, and interactive controls (see
/// `BindrTheme.swift`).
///
/// All values here are static sRGB and resolve identically in dark and light
/// mode. If a token needs to differ per appearance, prefer reading
/// `@Environment(\.colorScheme)` at the call site rather than baking variants
/// into the palette — keeps this file the single source of truth for
/// "what color is X content type".
///
/// **Migration note:** these were previously duplicated as raw `Color(hex:)`
/// literals in 50+ places across Social, Decks, Bindrs, and Friends. Always
/// reach for `BindrPalette.X` instead of repeating the hex.
enum BindrPalette {
    /// Binders, wishlist gold tier, "starred" social affordances.
    /// (Replaces hardcoded `Color(hex: "E8B84B")`.)
    static let binderGold = Color(hex: "E8B84B")

    /// Wishlist content surfaced in the social feed and friend rows. Sits
    /// alongside `binderGold` without competing for the eye.
    /// (Replaces hardcoded `Color(hex: "A78BFA")`.)
    static let wishlistViolet = Color(hex: "A78BFA")

    /// Deck-related rows in the social feed and dashboard quick-access tiles.
    /// (Replaces hardcoded `Color(hex: "5B9CF6")`.)
    static let deckBlue = Color(hex: "5B9CF6")

    /// Owned / positive / successful state — also used for "new pull" sparkle
    /// moments in the feed since both signals read as a green "win".
    /// (Replaces hardcoded `Color(hex: "52C97C")`.)
    static let ownedGreen = Color(hex: "52C97C")

    /// Errors, destructive confirmation, alert badges, friend-removal CTA.
    /// (Replaces hardcoded `Color(hex: "E05252")`.)
    static let alertRed = Color(hex: "E05252")

    /// Social feed canvas — cool light grey behind white post cards.
    static let feedSurface = Color(hex: "F5F5F7")

    /// Hairline border around feed post cards in light mode.
    static let feedCardBorder = Color(hex: "E5E5EA")

    /// Hashtag pill background on feed posts.
    static let feedTagBackground = Color(hex: "EFEFF4")

    /// Deck badge + card-count chip in the social feed.
    static let feedDeckPurple = Color(hex: "8B5CF6")

    /// Pull-type label on feed posts (bright mint green).
    static let feedPullGreen = Color(hex: "4ADE80")

    /// Binder-type label on feed posts (warm orange).
    static let feedBinderOrange = Color(hex: "FB923C")

    /// Hashtag text on feed posts.
    static let feedHashtagPurple = Color(hex: "A388EE")

    /// Username / timestamp meta line on feed posts (dark mode).
    static let feedMetaText = Color(hex: "9DA1C2")

    /// Hairline divider between flat feed rows (dark mode).
    static let feedRowDivider = Color(hex: "1E1E3A")
}
