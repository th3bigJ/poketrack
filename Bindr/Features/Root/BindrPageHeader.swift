import SwiftUI

/// Shared top-of-page header used by Social, Binders, and Deck Builder so
/// they all match the Dashboard's translucent floating-chrome look. Centers
/// the title, hosts a leading slot (typically Back) and a trailing slot
/// (typically the page's primary action). Only the circle buttons carry
/// glass — the bar between them stays fully transparent.
///
/// Two slots is intentional — anything more elaborate (multiple action
/// buttons, animated swap-in/swap-out groups) goes inside the trailing
/// `@ViewBuilder` so the caller controls grouping while the header itself
/// keeps a single, consistent layout. The header height is fixed by the
/// `ChromeGlassCircleButton` (48pt) plus 8pt vertical padding = 64pt, so
/// every adopting screen gets the same overlay-inset height for free.
struct BindrPageHeader<Leading: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        @ViewBuilder leading: @escaping () -> Leading = { EmptyView() },
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        // Layout mirrors `UniversalSearchBar` in its collapsed state — title
        // centered in a ZStack, leading + trailing chrome flanking it via a
        // full-width HStack — so Social/Binders/Decks headers line up
        // pixel-for-pixel with the Dashboard/Browse floating chrome bar.
        //
        // Critically: there is NO solid material on the bar itself. The
        // translucent feel comes from each `ChromeGlassCircleButton` being
        // its own glass disc; the bar between them stays transparent so
        // page content blurs underneath through the buttons, not under a
        // solid stripe — that solid stripe was the source of the "opaque
        // header" complaint.
        Group {
            contentLayout
        }
    }

    private var contentLayout: some View {
        ZStack {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 8) {
                leading()
                Spacer(minLength: 0)
                trailing()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        // Padding values match `RootChromeEnvironment` (8pt top / 10pt
        // bottom) so vertical position lines up with the Dashboard /
        // Browse floating search bar.
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

extension BindrPageHeader where Leading == EmptyView {
    init(
        title: String,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.init(title: title, leading: { EmptyView() }, trailing: trailing)
    }
}

extension BindrPageHeader where Trailing == EmptyView {
    init(
        title: String,
        @ViewBuilder leading: @escaping () -> Leading
    ) {
        self.init(title: title, leading: leading, trailing: { EmptyView() })
    }
}
