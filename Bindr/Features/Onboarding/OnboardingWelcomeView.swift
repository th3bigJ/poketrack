import SwiftUI

// MARK: - OnboardingWelcomeView
//
// Step 1 of `BindrOnboardingFlow`. Pitches Bindr's value before the user
// makes any decisions. No data collected, no heavy animations — just a
// clear headline and feature cards that are immediately responsive.

struct OnboardingWelcomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent

    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: BindrSpacing.xl) {
                    headline
                    featureGrid
                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, BindrSpacing.lg)
                .padding(.top, BindrSpacing.xl)
            }
            .scrollIndicators(.hidden)

            continueButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.sm) {
            Text("Your collection,\nbeautifully organized.")
                .font(.system(size: 36, weight: .heavy))
                .lineSpacing(-2)
            Text("The complete toolkit for serious collectors — catalog, scanner, binders, and community in one place.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Feature grid

    private var featureGrid: some View {
        VStack(spacing: BindrSpacing.sm) {
            featureCard(
                icon: "camera.viewfinder",
                title: "Card Scanner",
                description: "Point your camera at any card for instant identification, pricing, and set info.",
                tint: accent
            )
            featureCard(
                icon: "rectangle.grid.3x2.fill",
                title: "Full Catalog",
                description: "Every set, variant, and alt art across Pokémon and ONE PIECE in one place.",
                tint: BindrPalette.deckBlue
            )
            featureCard(
                icon: "books.vertical.fill",
                title: "Digital Binders",
                description: "3D embossed covers and custom layouts to show off your rarest pulls.",
                tint: BindrPalette.binderGold
            )
            featureCard(
                icon: "rectangle.stack.badge.plus",
                title: "Deck Builder",
                description: "Build from scratch or import from PTCGL. Real-time legality checking.",
                tint: BindrPalette.wishlistViolet
            )
            featureCard(
                icon: "chart.line.uptrend.xyaxis",
                title: "Collection Value",
                description: "Live pricing, trend history, and portfolio value at a glance.",
                tint: BindrPalette.ownedGreen
            )
            featureCard(
                icon: "arrow.left.arrow.right",
                title: "Trade Network",
                description: "Find trade partners, list your extras, and get alerts when wishlist cards appear.",
                tint: Color(hex: "FF6B6B")
            )
        }
    }

    private func featureCard(icon: String, title: String, description: String, tint: Color) -> some View {
        HStack(spacing: BindrSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: BindrRadius.md, style: .continuous)
                    .fill(tint.opacity(colorScheme == .dark ? 0.20 : 0.16))
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BindrSpacing.md)
        .padding(.vertical, BindrSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(cornerRadius: BindrRadius.lg, interactive: false)
    }

    // MARK: CTA

    private var continueButton: some View {
        VStack(spacing: 0) {
            Button {
                Haptics.lightImpact()
                onContinue()
            } label: {
                HStack(spacing: 8) {
                    Text("Get Started")
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
            .padding(.top, BindrSpacing.sm)
        }
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
