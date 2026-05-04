import SwiftUI

// MARK: - Environment-backed theme accent
//
// Why this exists:
//
// Theming in Bindr was historically split across two sources of truth —
// `Color.accentColor` (which reads from the empty `AccentColor.colorset`
// asset, falling back to system blue on most builds) and
// `services.theme.accentColor` (the user's actual choice from `ThemesView`).
// The two diverged in 73+ call sites. Sub-sheets and trade flows lost the
// theme accent entirely because `.tint()` env-propagation through `.sheet { }`
// is inconsistent across iOS versions.
//
// `\.bindrAccent` is the single source of truth. `RootView` injects it once
// at the top of the tree, and any sheet content that needs the accent — even
// if `AppServices` isn't in scope there — can read it via:
//
//     @Environment(\.bindrAccent) private var accent
//
// Inside a sheet closure where `services` *is* available, re-inject before
// presenting nested content so descendants stay themed:
//
//     .sheet(isPresented: $showSheet) {
//         SomeChildView()
//             .bindrTheme(accent: services.theme.accentColor)
//     }
//
// The default value matches `ThemeSettings.init`'s default ("4f46e5", indigo)
// so previews and isolated harnesses render with the same accent the user
// sees on first launch.

private struct BindrAccentColorKey: EnvironmentKey {
    static let defaultValue: Color = Color(hex: "4f46e5")
}

extension EnvironmentValues {
    /// User's chosen theme accent. Prefer this over `Color.accentColor` and
    /// over reaching directly for `services.theme.accentColor` in deeply
    /// nested view code — it survives `.sheet`, `.fullScreenCover`, and
    /// `NavigationStack` boundaries the same on every iOS version.
    var bindrAccent: Color {
        get { self[BindrAccentColorKey.self] }
        set { self[BindrAccentColorKey.self] = newValue }
    }
}

extension View {
    /// Injects the user's theme accent into the environment so descendants
    /// can read `@Environment(\.bindrAccent)`. Also calls SwiftUI's `.tint()`
    /// so system controls (Buttons, Toggles, ProgressView, etc.) pick up the
    /// same color without each call site having to remember to set both.
    ///
    /// Apply once at the app root and once inside any sheet / cover content
    /// closure where the environment chain needs to be re-seeded.
    func bindrTheme(accent: Color) -> some View {
        self
            .environment(\.bindrAccent, accent)
            .tint(accent)
    }
}
