import SwiftUI

/// Leading menu control, pill search field (camera inside on the right), trailing filter.
/// On supported OS versions uses **Liquid Glass** ([`glassEffect`](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)), [`GlassEffectContainer`](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)); otherwise falls back to system materials.
struct UniversalSearchBar: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool

    /// When `true`, the leading control shows an X (same style as the burger) to close the drawer.
    var isMenuOpen: Bool

    /// When `true`, search overlay is up — leading control is a **back** affordance (takes priority over the burger).
    var isSearchOpen: Bool

    var onBurgerTap: () -> Void
    var onCamera: () -> Void
    var onFilter: () -> Void

    /// Hairline edge on material fallback (Liquid Glass does not need this).
    private let glassStroke = Color.white.opacity(0.14)

    private var leadingSymbolName: String {
        if isSearchOpen { return "chevron.left" }
        if isMenuOpen { return "xmark" }
        return "line.3.horizontal"
    }

    private var leadingAccessibilityLabel: String {
        if isSearchOpen { return "Back" }
        if isMenuOpen { return "Close menu" }
        return "Open menu"
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                liquidGlassBar
            } else {
                materialFallbackBar
            }
        }
    }

    // MARK: - Liquid Glass (iOS 26+)

    @available(iOS 26.0, *)
    private var liquidGlassBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button(action: onBurgerTap) {
                    Image(systemName: leadingSymbolName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
                .accessibilityLabel(leadingAccessibilityLabel)

                searchFieldInner
                    .padding(.leading, 14)
                    .padding(.trailing, 8)
                    .frame(height: 44)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: Capsule())

                Button(action: onFilter) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
                .accessibilityLabel("Filters")
            }
        }
    }

    // MARK: - Materials (fallback)

    private var materialFallbackBar: some View {
        HStack(spacing: 10) {
            Button(action: onBurgerTap) {
                Image(systemName: leadingSymbolName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(glassStroke, lineWidth: 0.5)
                    }
                    .contentTransition(.symbolEffect(.replace))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
            .accessibilityLabel(leadingAccessibilityLabel)

            searchFieldInner
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .frame(height: 44)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(glassStroke, lineWidth: 0.5)
                }

            Button(action: onFilter) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(glassStroke, lineWidth: 0.5)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
            .accessibilityLabel("Filters")
        }
    }

    /// Shared field content (icons + text + camera) for both Liquid Glass and material layouts.
    /// Icons match the leading / trailing bar buttons (`.primary`); placeholder is slightly softer so typed text still reads as the main content.
    private var searchFieldInner: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.primary)

            TextField(
                "",
                text: $text,
                prompt: Text("Search cards, sets, Pokemon, sealed…")
                    .foregroundStyle(.primary.opacity(0.72))
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($isFocused)
            .foregroundStyle(.primary)
            .submitLabel(.search)
            .accessibilityLabel("Search cards, sets, Pokemon, sealed products")
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onCamera) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(minWidth: 36, minHeight: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scan with camera")
        }
    }
}
