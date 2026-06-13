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

// MARK: - Offline image context

/// Injected at the root so image components can serve from the local offline pack without
/// needing to reach AppServices directly (which is not available inside loader classes).
/// Captures offline state as plain values so it is safe to use from background tasks.
struct OfflineImageContext: Sendable {
    /// Whether the offline pack is enabled for the active brand (snapshot at inject time).
    let isOfflineEnabled: Bool
    let brand: TCGBrand?
    /// Bumped by `OfflineImageDownloadService` when a pack write completes; including this in
    /// image view task IDs ensures visible cells reload from disk once download finishes.
    let packDataRevision: Int

    /// Returns the on-disk file URL for a remote image URL when offline mode is active.
    func localURL(for remoteURL: URL) -> URL? {
        guard let brand else { return nil }
        let key = AppConfiguration.offlineImageKey(for: remoteURL)

        // Essential assets (set logos, symbols, pokémon art) are always available from disk
        // regardless of whether the user has enabled the offline pack.
        let essential = EssentialImageStore.shared
        if let key, let local = essential.localFileURL(relativePath: key, brand: brand) {
            return local
        }
        if let local = essential.localFileURL(relativePath: remoteURL.absoluteString, brand: brand) {
            return local
        }

        guard isOfflineEnabled else { return nil }

        let pack = OfflineImageStore.shared
        if let key, let local = pack.localFileURL(relativePath: key, brand: brand) {
            return local
        }
        return pack.localFileURL(relativePath: remoteURL.absoluteString, brand: brand)
    }
}

private struct OfflineImageContextKey: EnvironmentKey {
    static let defaultValue: OfflineImageContext? = nil
}

extension EnvironmentValues {
    /// Provides offline image resolution to `CachedAsyncImage` and `ProgressiveAsyncImage`.
    var offlineImageContext: OfflineImageContext? {
        get { self[OfflineImageContextKey.self] }
        set { self[OfflineImageContextKey.self] = newValue }
    }
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

struct BindrAccentShapeFill<S: Shape>: View {
    let shape: S
    let fallback: Color
    let usesLogoGradient: Bool
    let logoOpacity: Double

    @Environment(AppServices.self) private var services: AppServices?

    var body: some View {
        if usesLogoGradient && services?.theme.isLogoThemeSelected == true {
            shape.fill(ThemeSettings.logoThemeGradient)
                .opacity(logoOpacity)
        } else {
            shape.fill(fallback)
        }
    }
}

struct BindrAccentForeground: ViewModifier {
    let fallback: Color

    @Environment(AppServices.self) private var services: AppServices?

    func body(content: Content) -> some View {
        if services?.theme.isLogoThemeSelected == true {
            content.foregroundStyle(ThemeSettings.logoThemeGradient)
        } else {
            content.foregroundStyle(fallback)
        }
    }
}

extension View {
    func bindrAccentForeground(_ fallback: Color) -> some View {
        modifier(BindrAccentForeground(fallback: fallback))
    }
}

extension Shape {
    func bindrAccentFill(_ fallback: Color, usesLogoGradient: Bool = true, logoOpacity: Double = 1) -> some View {
        BindrAccentShapeFill(
            shape: self,
            fallback: fallback,
            usesLogoGradient: usesLogoGradient,
            logoOpacity: logoOpacity
        )
    }
}

struct BindrSuccessSparkModifier<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger

    @Environment(AppServices.self) private var services: AppServices?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShowing = false
    @State private var isExpanded = false
    @State private var burstID = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                if isShowing && services?.theme.isLogoThemeSelected == true {
                    BindrSuccessSparkBurst(isExpanded: isExpanded, reduceMotion: reduceMotion)
                        .id(burstID)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .onChange(of: trigger) { oldValue, newValue in
                guard oldValue != newValue else { return }
                play()
            }
    }

    private func play() {
        guard services?.theme.isLogoThemeSelected == true else { return }
        let nextBurstID = burstID + 1
        burstID = nextBurstID
        isExpanded = false
        isShowing = true

        if reduceMotion {
            withAnimation(.easeOut(duration: 0.24)) {
                isExpanded = true
            }
        } else {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
                isExpanded = true
            }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 280 : 680))
            guard burstID == nextBurstID else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                isShowing = false
            }
        }
    }
}

extension View {
    func bindrSuccessSpark<Trigger: Equatable>(trigger: Trigger) -> some View {
        modifier(BindrSuccessSparkModifier(trigger: trigger))
    }
}

private struct BindrSuccessSparkBurst: View {
    let isExpanded: Bool
    let reduceMotion: Bool

    private var particles: [BindrSparkParticle] {
        let colors = ThemeSettings.logoThemeColors
        return [
            BindrSparkParticle(symbol: "sparkle", color: colors[0], x: -34, y: -28, size: 13, rotation: -18, endScale: 0.95),
            BindrSparkParticle(symbol: "star.fill", color: colors[3], x: 32, y: -26, size: 11, rotation: 20, endScale: 0.86),
            BindrSparkParticle(symbol: "circle.fill", color: colors[1], x: -28, y: 24, size: 7, rotation: 0, endScale: 0.72),
            BindrSparkParticle(symbol: "sparkle", color: colors[2], x: 34, y: 22, size: 10, rotation: 24, endScale: 0.82),
            BindrSparkParticle(symbol: "circle.fill", color: colors[3], x: 0, y: -38, size: 6, rotation: 0, endScale: 0.74)
        ]
    }

    var body: some View {
        ZStack {
            if reduceMotion {
                Circle()
                    .stroke(ThemeSettings.logoThemeGradient, lineWidth: 2)
                    .frame(width: isExpanded ? 62 : 38, height: isExpanded ? 62 : 38)
                    .opacity(isExpanded ? 0 : 0.42)
                    .blur(radius: 0.5)
            } else {
                Circle()
                    .stroke(ThemeSettings.logoThemeGradient, lineWidth: 2)
                    .frame(width: isExpanded ? 76 : 24, height: isExpanded ? 76 : 24)
                    .opacity(isExpanded ? 0 : 0.36)

                ForEach(particles) { particle in
                    Image(systemName: particle.symbol)
                        .font(.system(size: particle.size, weight: .bold))
                        .foregroundStyle(particle.color)
                        .scaleEffect(isExpanded ? particle.endScale : 0.24)
                        .rotationEffect(.degrees(isExpanded ? particle.rotation : 0))
                        .offset(x: isExpanded ? particle.x : 0, y: isExpanded ? particle.y : 0)
                        .opacity(isExpanded ? 0 : 1)
                }
            }
        }
        .frame(width: 110, height: 110)
        .compositingGroup()
    }
}

private struct BindrSparkParticle: Identifiable {
    let id = UUID()
    let symbol: String
    let color: Color
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let rotation: Double
    let endScale: CGFloat
}

struct BindrPageBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent
    @Environment(AppServices.self) private var services: AppServices?

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)

            if services?.theme.backgroundGlowEnabled ?? true {
                if services?.theme.isLogoThemeSelected == true {
                    logoThemeGlow
                } else {
                    standardAccentGlow
                }
            }

            // Subtle Noise/Grain Overlay (Simulated via opacity jitter)
            Color.primary.opacity(0.005)
                .blendMode(colorScheme == .dark ? .overlay : .multiply)
        }
    }

    @ViewBuilder
    private var standardAccentGlow: some View {
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
    }

    @ViewBuilder
    private var logoThemeGlow: some View {
        let cyan = ThemeSettings.logoThemeColors[0]
        let blue = ThemeSettings.logoThemeColors[1]
        let violet = ThemeSettings.logoThemeColors[2]
        let pink = ThemeSettings.logoThemeColors[3]

        LinearGradient(
            colors: [
                cyan.opacity(colorScheme == .dark ? 0.105 : 0.090),
                violet.opacity(colorScheme == .dark ? 0.080 : 0.066),
                pink.opacity(colorScheme == .dark ? 0.074 : 0.058),
                .clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        RadialGradient(
            colors: [
                cyan.opacity(colorScheme == .dark ? 0.105 : 0.080),
                blue.opacity(colorScheme == .dark ? 0.050 : 0.040),
                .clear
            ],
            center: .topLeading,
            startRadius: 0,
            endRadius: 430
        )
        .offset(x: -90, y: -100)

        RadialGradient(
            colors: [
                pink.opacity(colorScheme == .dark ? 0.110 : 0.082),
                violet.opacity(colorScheme == .dark ? 0.052 : 0.038),
                .clear
            ],
            center: .topTrailing,
            startRadius: 10,
            endRadius: 470
        )
        .offset(x: 110, y: -110)
    }
}
