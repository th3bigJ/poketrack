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

    /// Shared page backdrop used across top-level screens. Keeps native
    /// `systemBackground` as base, then adds a very subtle accent wash.
    func bindrPageBackground(ignoresSafeArea: Bool = true) -> some View {
        background {
            if ignoresSafeArea {
                BindrPageBackground()
                    .ignoresSafeArea()
            } else {
                BindrPageBackground()
            }
        }
    }
}

struct BindrPageBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)

            LinearGradient(
                colors: [
                    accent.opacity(colorScheme == .dark ? 0.075 : 0.065),
                    accent.opacity(colorScheme == .dark ? 0.035 : 0.032),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    accent.opacity(colorScheme == .dark ? 0.055 : 0.042),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 450
            )
            .offset(x: 100, y: -100)
            
            RadialGradient(
                colors: [
                    accent.opacity(colorScheme == .dark ? 0.04 : 0.03),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 300
            )
            .offset(x: -50, y: 50)
            
            // Subtle Noise/Grain Overlay (Simulated via opacity jitter)
            Color.primary.opacity(0.005)
                .blendMode(colorScheme == .dark ? .overlay : .multiply)
        }
    }
}
