import Combine
import SwiftUI

/// Drives hiding the top search chrome and tab bar while scrolling. Uses `ObservableObject` so `RootView` reliably re-renders when `barsVisible` changes (pure `@Observable` + `@State` can miss updates for chrome outside the scrolling view).
@MainActor
final class ChromeScrollCoordinator: ObservableObject {
    @Published private(set) var barsVisible: Bool = true

    /// Only the Cards (Browse) tab should drive hide-on-scroll. `TabView` keeps off-screen tabs alive, so `UIScrollView` KVO can still fire on Account — ignore unless this is `true`.
    private(set) var acceptsScrollChromeUpdates: Bool = true

    private var lastOffsetY: CGFloat = 0

    private let deltaThreshold: CGFloat = 8
    private let nearTopThreshold: CGFloat = 28

    /// Call from `RootView` when the selected tab changes.
    func configureForTab(_ tab: AppTab) {
        switch tab {
        case .browse:
            acceptsScrollChromeUpdates = true
            resetForTabChange()
        case .wishlist, .account:
            acceptsScrollChromeUpdates = false
            forceVisible()
        }
    }

    func reportScrollOffsetY(_ y: CGFloat) {
        guard acceptsScrollChromeUpdates else { return }
        let delta = y - lastOffsetY
        lastOffsetY = y
        apply(delta: delta, offsetY: y)
    }

    func resetForTabChange() {
        lastOffsetY = 0
        setBarsVisible(true)
    }

    func forceVisible() {
        lastOffsetY = 0
        setBarsVisible(true)
    }

    /// `offsetY` is distance scrolled **down** from the rest position at the top (0 = at top, larger = scrolled down). Matches `max(0, -anchorMinY)` from a scroll anchor or UIKit-like `contentOffset.y`.
    private func apply(delta: CGFloat, offsetY: CGFloat) {
        if offsetY <= nearTopThreshold {
            setBarsVisible(true)
            return
        }
        if delta > deltaThreshold {
            setBarsVisible(false)
        } else if delta < -deltaThreshold {
            setBarsVisible(true)
        }
    }

    private func setBarsVisible(_ visible: Bool) {
        guard barsVisible != visible else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
            barsVisible = visible
        }
    }
}

/// Hides the tab bar while scrolling; apply to each root inside a tab (e.g. `BrowseView`, `AccountView`). `TabView`-level modifiers are unreliable.
struct TabBarChromeFromScrollModifier: ViewModifier {
    @EnvironmentObject private var chromeScroll: ChromeScrollCoordinator

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.toolbarVisibility(chromeScroll.barsVisible ? .automatic : .hidden, for: .tabBar)
        } else {
            content.toolbar(chromeScroll.barsVisible ? .automatic : .hidden, for: .tabBar)
        }
    }
}

extension View {
    func tabBarChromeFromScroll() -> some View {
        modifier(TabBarChromeFromScrollModifier())
    }
}
