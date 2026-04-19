import Combine
import SwiftUI

/// Drives hiding the top search chrome and tab bar while scrolling. Uses `ObservableObject` so `RootView` reliably re-renders when `barsVisible` changes (pure `@Observable` + `@State` can miss updates for chrome outside the scrolling view).
@MainActor
final class ChromeScrollCoordinator: ObservableObject {
    @Published private(set) var barsVisible: Bool = true

    /// Only the Cards (Browse) tab should drive hide-on-scroll. `TabView` keeps off-screen tabs alive, so `UIScrollView` KVO can still fire on Account — ignore unless this is `true`.
    private(set) var acceptsScrollChromeUpdates: Bool = true

    private var lastOffsetY: CGFloat = 0
    /// While the tab bar / safe area animates, `ScrollOffsetAnchor` can report a one-frame spike; ignore updates briefly so we don’t fight the layout or flicker chrome.
    private var suppressScrollChromeUntil: Date?

    private let deltaThreshold: CGFloat = 8
    private let nearTopThreshold: CGFloat = 28
    private let layoutSettleDuration: TimeInterval = 0.2

    /// Call from `RootView` when the selected tab changes.
    func configureForTab(_ tab: AppTab) {
        switch tab {
        case .browse:
            acceptsScrollChromeUpdates = true
            resetForTabChange()
        case .dashboard, .collect, .social, .more:
            // `.more` never actually becomes the selected tab (RootView intercepts it
            // to present a sheet), but the switch must stay exhaustive.
            acceptsScrollChromeUpdates = false
            forceVisible()
        }
    }

    func reportScrollOffsetY(_ y: CGFloat) {
        guard acceptsScrollChromeUpdates else { return }
        if let until = suppressScrollChromeUntil, Date() < until {
            lastOffsetY = y
            return
        }
        suppressScrollChromeUntil = nil
        let delta = y - lastOffsetY
        lastOffsetY = y
        apply(delta: delta, offsetY: y)
    }

    func resetForTabChange() {
        lastOffsetY = 0
        suppressScrollChromeUntil = nil
        setBarsVisible(true)
    }

    func forceVisible() {
        lastOffsetY = 0
        suppressScrollChromeUntil = nil
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
        suppressScrollChromeUntil = Date().addingTimeInterval(layoutSettleDuration)
        withAnimation(.easeInOut(duration: 0.22)) {
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
