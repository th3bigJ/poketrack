import SwiftUI

// MARK: - OnboardingSocialDiscoveryView
//
// Step 3 of `BindrOnboardingFlow`. Acts as the bridge between the
// catalog-only experience (steps 1–2) and the new social tab. The
// hero combines the same `FloatingCardStack` + `LiveActivityTicker`
// pieces used on `SocialLandingView` so users see the surface they're
// being teleported toward.
//
// Outcome: tapping "Enter Bindr" closes the flow and the Social tab is
// just one tap away in the bottom tab bar. We deliberately don't auto-
// route the user into Social so first-launch users still land on the
// dashboard / catalog they signed up for.

struct OnboardingSocialDiscoveryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent

    let onFinish: () -> Void

    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: BindrSpacing.xl) {
                    headline
                    heroVisual
                    featurePeeks
                    tickerBlock
                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, BindrSpacing.lg)
                .padding(.top, BindrSpacing.xl)
            }
            .scrollIndicators(.hidden)

            ctaRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) {
                hasAppeared = true
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.sm) {
            SocialSectionEyebrow(title: "STEP 3 OF 3")
            Text("The community\nis already moving.")
                .font(.system(size: 34, weight: .heavy))
                .lineSpacing(-2)
            Text("Trade, hype, hunt grails, and watch friends pull live. Bindr is best with people in it.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var heroVisual: some View {
        ZStack {
            RadialGradient(
                colors: [accent.opacity(colorScheme == .dark ? 0.30 : 0.18), .clear],
                center: .center,
                startRadius: 10,
                endRadius: 240
            )
            .blur(radius: 26)

            FloatingCardStack()
                .frame(height: 260)
                .scaleEffect(hasAppeared ? 1.0 : 0.9)
                .opacity(hasAppeared ? 1 : 0)
        }
        .frame(height: 280)
        .frame(maxWidth: .infinity)
    }

    // MARK: Feature peeks

    private var featurePeeks: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.md) {
            SocialSectionEyebrow(title: "WHAT'S IN THE TAB")

            VStack(spacing: BindrSpacing.sm) {
                peekRow(
                    icon: "arrow.left.arrow.right",
                    title: "Trade Wall",
                    description: "List cards, browse listings, lock in deals.",
                    tint: BindrPalette.deckBlue
                )
                peekRow(
                    icon: "sparkles",
                    title: "Live feed",
                    description: "Friends pulling, listing, hunting — in real time.",
                    tint: BindrPalette.ownedGreen
                )
                peekRow(
                    icon: "crown.fill",
                    title: "Grail alerts",
                    description: "Get pinged the second a card on your wishlist hits the wall.",
                    tint: BindrPalette.binderGold
                )
                peekRow(
                    icon: "person.crop.square.filled.and.at.rectangle",
                    title: "Collection profile",
                    description: "Share a page collectors actually want to look at.",
                    tint: BindrPalette.wishlistViolet
                )
            }
        }
    }

    private func peekRow(icon: String, title: String, description: String, tint: Color) -> some View {
        HStack(spacing: BindrSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: BindrRadius.md, style: .continuous)
                    .fill(tint.opacity(colorScheme == .dark ? 0.20 : 0.16))
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, BindrSpacing.md)
        .padding(.vertical, BindrSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(cornerRadius: BindrRadius.lg, interactive: false)
    }

    // MARK: Ticker preview

    private var tickerBlock: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.md) {
            SocialSectionEyebrow(title: "LIVE NOW", accentDot: true)
            LiveActivityTicker()
                .frame(minHeight: 180)
        }
    }

    // MARK: CTA

    private var ctaRow: some View {
        VStack(spacing: BindrSpacing.sm) {
            Button {
                Haptics.success()
                onFinish()
            } label: {
                HStack(spacing: 8) {
                    Text("Enter Bindr")
                        .font(.system(size: 17, weight: .heavy))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background {
                    RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.78)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: accent.opacity(colorScheme == .dark ? 0.55 : 0.32), radius: 22, x: 0, y: 10)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, BindrSpacing.lg)
            .padding(.bottom, BindrSpacing.lg)
        }
        .padding(.top, BindrSpacing.sm)
        .background {
            LinearGradient(
                colors: [
                    Color.clear,
                    Color(uiColor: .systemBackground).opacity(0.65),
                    Color(uiColor: .systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }
}
