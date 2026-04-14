import SwiftUI

/// Welcome splash screen shown every time the app launches.
/// User taps GET STARTED to proceed to GameSelectionView (first launch) or MainTabView (returning user).
struct SplashView: View {
    var onGetStarted: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            // Background — pure black iOS dark / Apple light grey
            (isDark ? Color.black : Color(red: 0.961, green: 0.961, blue: 0.969))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ── "welcome to" label ──────────────────────────────
                Text("welcome to")
                    .font(.system(size: 12, weight: .regular))
                    .italic()
                    .foregroundColor(isDark
                        ? .white.opacity(0.50)
                        : .black.opacity(0.45))
                    .tracking(3)
                    .textCase(.uppercase)
                    .padding(.bottom, 8)

                // ── "bindr" wordmark ────────────────────────────────
                Text("bindr")
                    .font(.custom("BebasNeue-Regular", size: 64))
                    // Fallback if Bebas Neue not yet added:
                    // .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundColor(isDark
                        ? .white.opacity(0.95)
                        : .black.opacity(0.88))
                    .tracking(8)
                    .padding(.bottom, 18)

                // ── Divider ─────────────────────────────────────────
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                (isDark ? Color.white : Color.black).opacity(0.22),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 32, height: 1)
                    .padding(.bottom, 20)

                // ── Strapline ────────────────────────────────────────
                VStack(spacing: 0) {
                    Text("Scan Pokémon, One Piece & Lorcana cards.")
                    Text("Track prices, build your collection,")
                    Text("and join our community.")
                }
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(isDark
                    ? .white.opacity(0.65)
                    : .black.opacity(0.60))
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.horizontal, 36)

                Spacer()

                // ── GET STARTED button ───────────────────────────────
                Button(action: onGetStarted) {
                    ZStack {
                        // Glass background layer
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)

                        // Tint overlay
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                isDark
                                ? LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.12),
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing)
                                : LinearGradient(
                                    colors: [
                                        Color.black.opacity(0.08),
                                        Color.black.opacity(0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing)
                            )

                        // Border
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                isDark
                                    ? Color.white.opacity(0.20)
                                    : Color.black.opacity(0.14),
                                lineWidth: 1
                            )

                        // Specular top edge
                        VStack {
                            LinearGradient(
                                colors: [
                                    (isDark ? Color.white : Color.white).opacity(isDark ? 0.28 : 0.60),
                                    Color.clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(height: 1)
                            .padding(.horizontal, 40)
                            Spacer()
                        }

                        // Label
                        Text("GET STARTED  →")
                            .font(.custom("BebasNeue-Regular", size: 15))
                            // Fallback: .font(.system(size: 15, weight: .bold))
                            .foregroundColor(isDark
                                ? .white.opacity(0.92)
                                : .black.opacity(0.84))
                            .tracking(2.5)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 52)
            }
        }
        // Lock to system colour scheme — do not force dark
        .preferredColorScheme(nil)
    }
}

#Preview {
    SplashView(onGetStarted: {})
}
