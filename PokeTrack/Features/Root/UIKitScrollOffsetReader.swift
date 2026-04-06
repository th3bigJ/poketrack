import SwiftUI

/// Tracks scroll offset by placing a zero-height anchor inside a `ScrollView`
/// that has `.coordinateSpace(name: "scroll")` applied.
/// This avoids mutating `UIScrollView` internals (insets, contentInsetAdjustmentBehavior)
/// which causes jumpy/jittery scrolling.
struct ScrollOffsetAnchor: View {
    var onOffsetChange: (CGFloat) -> Void

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .preference(
                    key: ScrollOffsetPreferenceKey.self,
                    value: -geo.frame(in: .named("scroll")).minY
                )
        }
        .frame(height: 0)
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            onOffsetChange(max(0, value))
        }
    }
}
