import SwiftUI

/// Extra scroll padding so the first line of content clears the **floating** search bar.
/// The bar is overlaid in a `ZStack` above `TabView` so `Material` / Liquid Glass can blur scrolling content behind it.
/// Height matches the overlaid chrome: ≈ 8 + 48 + 10.
enum RootChromeEnvironment {
    static let searchBarStackHeight: CGFloat = 66
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
