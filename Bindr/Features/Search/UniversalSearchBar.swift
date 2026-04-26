import SwiftUI

// MARK: - Local haptic wrappers (keep call sites one line)

private func hapticBackThen(_ action: @escaping () -> Void) -> () -> Void {
    {
        Haptics.lightImpact()
        action()
    }
}

private func hapticFilterThen(_ action: @escaping () -> Void) -> () -> Void {
    {
        Haptics.lightImpact()
        action()
    }
}

/// Pill search field with trailing filter while collapsed. A back
/// chevron only appears while the search overlay is open; there is no burger
/// menu — the overflow menu lives in the bottom nav's **More** tab.
/// On supported OS versions uses **Liquid Glass** ([`glassEffect`](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)), [`GlassEffectContainer`](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)); otherwise falls back to system materials.
struct UniversalSearchBar: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    var title: String?

    /// When `true`, search overlay is up — the leading **back** chevron is shown so the user can dismiss it.
    var isSearchOpen: Bool
    var isFilterEnabled: Bool = true
    var isFilterActive: Bool = false
    var filterMenuContent: AnyView? = nil

    /// When set, replaces the collapsed leading camera button with a custom button.
    var collapsedLeadingButton: (symbol: String, accessibilityLabel: String, action: () -> Void)? = nil

    /// When set, replaces the filter button with a custom trailing button (symbol name + action).
    var trailingButton: (symbol: String, accessibilityLabel: String, action: () -> Void)? = nil
    /// Optional second trailing control shown before filter/trailing button.
    var extraTrailingButton: (symbol: String, accessibilityLabel: String, action: () -> Void)? = nil

    /// Called when the leading back chevron is tapped (only visible while search is open).
    var onActivateSearch: () -> Void
    var onBack: () -> Void
    var onCamera: () -> Void
    var onFilter: () -> Void

    /// `Menu` swallows `TapGesture`; use a zero-distance `DragGesture` so we get a touch-down haptic when the filter menu opens.
    @State private var filterMenuHapticSentForCurrentTouch = false

    /// Hairline on material fallback — `primary` adapts with light/dark (old fixed white stroke looked wrong on light mode).
    private var glassStroke: Color { Color.primary.opacity(0.1) }
    private var filterTint: Color { .primary }
    private var leadingSymbolName: String { "chevron.left" }

    private var leadingAccessibilityLabel: String { "Back" }

    private var filterMenuTouchDownHapticGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !filterMenuHapticSentForCurrentTouch else { return }
                filterMenuHapticSentForCurrentTouch = true
                Haptics.lightImpact()
            }
            .onEnded { _ in
                filterMenuHapticSentForCurrentTouch = false
            }
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
            Group {
                if isSearchOpen {
                            HStack(spacing: 6) {
                        Button(action: hapticBackThen(onBack)) {
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
                        .transition(.opacity.combined(with: .scale))

                        searchFieldInner
                            .padding(.leading, 14)
                            .padding(.trailing, 8)
                            .frame(height: 44)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(.regular, in: Capsule())
                            .transition(.move(edge: .leading).combined(with: .opacity))

                        cameraButtonLiquid
                    }
                } else {
                    ZStack {
                        if let title, !title.isEmpty {
                            Text(title)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }

                    HStack {
                        collapsedSearchButtonLiquid
                        Spacer(minLength: 0)
                        if let extraTrailingButton {
                            trailingButtonLiquid(
                                symbol: extraTrailingButton.symbol,
                                accessibilityLabel: extraTrailingButton.accessibilityLabel,
                                action: extraTrailingButton.action
                            )
                        }
                        if let trailingButton {
                            trailingButtonLiquid(symbol: trailingButton.symbol, accessibilityLabel: trailingButton.accessibilityLabel, action: trailingButton.action)
                        } else if let filterMenuContent, isFilterEnabled {
                            chromeMenuButton(
                                symbol: isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle",
                                tint: filterTint,
                                accessibilityLabel: "Filters",
                                content: { filterMenuContent }
                            )
                        } else {
                            filterButtonLiquid
                        }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Materials (fallback)

    private var materialFallbackBar: some View {
        Group {
            if isSearchOpen {
                            HStack(spacing: 6) {
                    Button(action: hapticBackThen(onBack)) {
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
                    .transition(.opacity.combined(with: .scale))

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
                        .transition(.move(edge: .leading).combined(with: .opacity))

                    cameraButtonFallback
                }
            } else {
                ZStack {
                    if let title, !title.isEmpty {
                        Text(title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    HStack {
                        collapsedSearchButtonFallback
                        Spacer(minLength: 0)
                        if let extraTrailingButton {
                            trailingButtonFallback(
                                symbol: extraTrailingButton.symbol,
                                accessibilityLabel: extraTrailingButton.accessibilityLabel,
                                action: extraTrailingButton.action
                            )
                        }
                        if let trailingButton {
                            trailingButtonFallback(symbol: trailingButton.symbol, accessibilityLabel: trailingButton.accessibilityLabel, action: trailingButton.action)
                        } else if let filterMenuContent, isFilterEnabled {
                            chromeMenuButton(
                                symbol: isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle",
                                tint: filterTint,
                                accessibilityLabel: "Filters",
                                content: { filterMenuContent }
                            )
                        } else {
                            filterButtonFallback
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @available(iOS 26.0, *)
    private var collapsedSearchButtonLiquid: some View {
        let symbol = collapsedLeadingButton?.symbol ?? "camera.fill"
        let accessibilityLabel = collapsedLeadingButton?.accessibilityLabel ?? "Open scanner"
        let action = collapsedLeadingButton?.action ?? onCamera
        return Button(action: {
            Haptics.lightImpact()
            action()
        }) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 48, height: 48)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var collapsedSearchButtonFallback: some View {
        let symbol = collapsedLeadingButton?.symbol ?? "camera.fill"
        let accessibilityLabel = collapsedLeadingButton?.accessibilityLabel ?? "Open scanner"
        let action = collapsedLeadingButton?.action ?? onCamera
        return Button(action: {
            Haptics.lightImpact()
            action()
        }) {
            Image(systemName: symbol)
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
        .accessibilityLabel(accessibilityLabel)
    }

    @available(iOS 26.0, *)
    private var filterButtonLiquid: some View {
        Group {
            if let filterMenuContent, isFilterEnabled {
                Menu {
                    filterMenuContent
                } label: {
                    filterGlyphLiquid
                }
                .menuActionDismissBehavior(.disabled)
                .menuOrder(.fixed)
                .menuIndicator(.hidden)
                .simultaneousGesture(filterMenuTouchDownHapticGesture)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
                .accessibilityLabel("Filters")
            } else {
                Button(action: hapticFilterThen(onFilter)) {
                    filterGlyphLiquid
                }
                .buttonStyle(.plain)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
                .accessibilityLabel("Filters")
                .disabled(!isFilterEnabled)
                .opacity(isFilterEnabled ? 1 : 0.55)
            }
        }
    }

    private var filterButtonFallback: some View {
        Group {
            if let filterMenuContent, isFilterEnabled {
                Menu {
                    filterMenuContent
                } label: {
                    filterGlyphFallback
                }
                .menuActionDismissBehavior(.disabled)
                .menuOrder(.fixed)
                .menuIndicator(.hidden)
                .simultaneousGesture(filterMenuTouchDownHapticGesture)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
                .accessibilityLabel("Filters")
            } else {
                Button(action: hapticFilterThen(onFilter)) {
                    filterGlyphFallback
                }
                .buttonStyle(.plain)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
                .accessibilityLabel("Filters")
                .disabled(!isFilterEnabled)
                .opacity(isFilterEnabled ? 1 : 0.55)
            }
        }
    }

    @available(iOS 26.0, *)
    private var filterGlyphLiquid: some View {
        Image(systemName: isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(isFilterEnabled ? AnyShapeStyle(filterTint) : AnyShapeStyle(.secondary))
            .frame(width: 44, height: 44)
            .glassEffect(.regular.interactive(), in: Circle())
            .contentShape(Circle())
    }

    private var filterGlyphFallback: some View {
        Image(systemName: isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(isFilterEnabled ? AnyShapeStyle(filterTint) : AnyShapeStyle(.secondary))
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(glassStroke, lineWidth: 0.5)
            }
            .contentShape(Circle())
    }

    private func chromeMenuButton<Content: View>(
        symbol: String,
        tint: Color,
        accessibilityLabel: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint)
                .modifier(ChromeGlassCircleGlyphModifier())
        }
        .buttonStyle(.plain)
        .menuActionDismissBehavior(.disabled)
        .menuOrder(.fixed)
        .menuIndicator(.hidden)
        .frame(width: 48, height: 48)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }

    @available(iOS 26.0, *)
    @available(iOS 26.0, *)
    private func trailingButtonLiquid(symbol: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.lightImpact(); action() }) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 48, height: 48)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }

    private func trailingButtonFallback(symbol: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.lightImpact(); action() }) {
            Image(systemName: symbol)
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
        .accessibilityLabel(accessibilityLabel)
    }

    @available(iOS 26.0, *)
    private var cameraButtonLiquid: some View {
        Button(action: {
            Haptics.lightImpact()
            onCamera()
        }) {
            Image(systemName: "camera.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 48, height: 48)
        .contentShape(Rectangle())
        .accessibilityLabel("Scan with camera")
    }

    private var cameraButtonFallback: some View {
        Button(action: {
            Haptics.lightImpact()
            onCamera()
        }) {
            Image(systemName: "camera.fill")
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
        .accessibilityLabel("Scan with camera")
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

            if !isSearchOpen {
                Button(action: {
                    Haptics.lightImpact()
                    onCamera()
                }) {
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
}

// MARK: - Shared chrome button (matches filter / leading circle controls)

/// Same circle glyph treatment as ``ChromeGlassCircleButton`` (for `Menu` labels and other non-`Button` wrappers).
struct ChromeGlassCircleGlyphModifier: ViewModifier {
    private var glassStroke: Color { Color.primary.opacity(0.1) }

    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                content
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .contentShape(Circle())
            } else {
                content
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(glassStroke, lineWidth: 0.5)
                    }
                    .contentShape(Circle())
            }
        }
    }
}

/// Same visual treatment as the filter button in ``UniversalSearchBar``: 44pt glyph, 48×48 hit area, Liquid Glass on iOS 26+ or ultra‑thin material + hairline below.
struct ChromeGlassCircleButton<Label: View>: View {
    let accessibilityLabel: String
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .modifier(ChromeGlassCircleGlyphModifier())
        }
        .buttonStyle(.plain)
        .frame(width: 48, height: 48)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }
}
