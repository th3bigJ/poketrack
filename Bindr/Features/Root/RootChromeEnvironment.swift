import SwiftUI

/// Extra scroll padding so the first line of content clears the **floating** search bar.
/// The bar is overlaid in a `ZStack` above `TabView` so `Material` / Liquid Glass can blur scrolling content behind it.
/// Height matches the overlaid chrome: `top + controlHeight + bottom`.
enum RootChromeEnvironment {
    static let searchBarTopInset: CGFloat = 8
    static let searchBarBottomInset: CGFloat = 10
    static let searchBarControlHeight: CGFloat = 48
    static let searchBarStackHeight: CGFloat = searchBarTopInset + searchBarControlHeight + searchBarBottomInset
    static let floatingContentTopInset: CGFloat = searchBarStackHeight
    /// Bottom scroll padding so content clears the tab bar pill and home indicator.
    /// Matches `.padding(.bottom, 120)` on More and Trades root scroll views.
    static let floatingTabBarContentInset: CGFloat = 120
    /// Vertical gap between stacked sections on the universal search overlay
    /// (category tiles, recent searches, recently viewed, result groups).
    static let searchOverlaySectionSpacing: CGFloat = 18
    /// Extra breathing room between the floating search bar and the first row.
    static let searchOverlayTopContentGap: CGFloat = 12
    /// Top inset for the search overlay title row — clears the floating bar only.
    static let searchOverlayHeaderTopInset: CGFloat = searchBarStackHeight + searchOverlayTopContentGap
    /// Legacy alias kept for any scroll views that still read this key.
    static let searchOverlayContentTopInset: CGFloat = searchOverlayHeaderTopInset
}

private struct RootFloatingChromeInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Non-zero when a top chrome row is overlaid; scroll views add this much **leading** spacer so rows aren’t hidden under the bar.
    var rootFloatingChromeInset: CGFloat {
        get { self[RootFloatingChromeInsetKey.self] }
        set { self[RootFloatingChromeInsetKey.self] = newValue }
    }
}

private struct PresentUniversalSearchKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// Opens the full-screen universal search overlay from tab chrome (e.g. Social header).
    var presentUniversalSearch: () -> Void {
        get { self[PresentUniversalSearchKey.self] }
        set { self[PresentUniversalSearchKey.self] = newValue }
    }
}
