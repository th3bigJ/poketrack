import SwiftUI

/// Welcome splash screen shown every time the app launches.
/// User taps GET STARTED to proceed to GameSelectionView (first launch) or MainTabView (returning user).
struct SplashView: View {
    var onGetStarted: () -> Void

    @Environment(\.bindrAccent) private var accent
    @Environment(\.colorScheme) var colorScheme
    @State private var animStates: [Bool] = [false, false, false, false]
    @State private var shimmerPos: CGFloat = -1

    var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 22) {
                    brandMark
                    Divider()
                        .overlay(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    (isDark ? Color.white : Color.black).opacity(0.20),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(maxWidth: 92)
                        .scaleEffect(x: animStates[1] ? 1 : 0, y: 1)
                        .opacity(animStates[1] ? 1 : 0)
                    strapline
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 34)
                .frame(maxWidth: 360)
                .glassCardStyle(cornerRadius: 32, interactive: false)
                .padding(.horizontal, 24)

                Spacer()

                Button(action: {
                    Haptics.lightImpact()
                    onGetStarted()
                }) {
                    HStack(spacing: 10) {
                        Text("Get Started")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .tracking(0.7)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .contentShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
                }
                .buttonStyle(.plain)
                .glassCardStyle(cornerRadius: 29, interactive: true)
                .overlay(shimmerOverlay(cornerRadius: 29))
                .shadow(color: accent.opacity(isDark ? 0.18 : 0.12), radius: 18, x: 0, y: 8)
                .padding(.horizontal, 24)
                .padding(.bottom, 52)
                .scaleEffect(animStates[3] ? 1 : 0.95)
                .opacity(animStates[3] ? 1 : 0)
            }
        }
        .bindrPageBackground()
        .task {
            // Staggered entrance
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) { animStates[0] = true }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.4)) { animStates[1] = true }
            withAnimation(.easeOut(duration: 0.8).delay(0.7)) { animStates[2] = true }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(1.0)) { animStates[3] = true }
        }
        .preferredColorScheme(nil)
    }

    private var brandMark: some View {
        VStack(spacing: 14) {
            Text("welcome to")
                .font(.system(size: 12, weight: .medium))
                .italic()
                .foregroundStyle(.secondary)
                .tracking(3)
                .textCase(.uppercase)
                .offset(y: animStates[0] ? 0 : 10)
                .opacity(animStates[0] ? 1 : 0)

            BindrBrandLogoView(maxWidth: 260)
                .offset(y: animStates[1] ? 0 : 15)
                .opacity(animStates[1] ? 1 : 0)
        }
    }

    private var strapline: some View {
        VStack(spacing: 6) {
            Text("Scan Pokémon cards.")
            Text("Track prices, build your collection,")
            Text("and join the community.")
        }
        .font(.system(size: 15, weight: .regular))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .lineSpacing(4)
        .offset(y: animStates[2] ? 0 : 10)
        .opacity(animStates[2] ? 1 : 0)
    }

    private func shimmerOverlay(cornerRadius: CGFloat) -> some View {
        GeometryReader { geo in
            let size = geo.size
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(isDark ? 0.20 : 0.16), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .rotationEffect(.degrees(25))
                .offset(x: shimmerPos * size.width * 1.5)
                .onAppear {
                    withAnimation(.linear(duration: 3.8).repeatForever(autoreverses: false)) {
                        shimmerPos = 1
                    }
                }
                .allowsHitTesting(false)
        }
        .mask(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

#Preview {
    SplashView(onGetStarted: {})
}
