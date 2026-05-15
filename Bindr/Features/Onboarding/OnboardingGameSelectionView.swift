import SwiftUI

// MARK: - OnboardingGameSelectionView
//
// Step 1 of `BindrOnboardingFlow`. Two large, animated franchise cards
// take the place of the old toggle list — Pokémon vs ONE PIECE. Each
// card has its own gradient identity and tilts toward the user when
// selected, mimicking holding a card up to a light.
//
// Selection contract:
//   * `selectedBrand` defaults to `.pokemon` and is updated on tap.
//   * `onContinue` is only enabled once a brand is picked (Pokémon is
//     pre-selected so the CTA is enabled on appear — matching the
//     legacy default behaviour).
//
// Future: when we add a third brand (MTG, Lorcana, etc.) move the
// catalog metadata into a small `OnboardingGameOption` struct backed
// by `BrandsManifestService` rather than hardcoding cases.

struct OnboardingGameSelectionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent

    @Binding var selectedBrand: TCGBrand
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: BindrSpacing.xl) {
                    headline
                    cardsStack
                    helperRow
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

    private var headline: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.sm) {
            Text("Your collection,\nyour game.")
                .font(.system(size: 38, weight: .heavy))
                .lineSpacing(-2)
            Text("Select the TCG you collect. Your catalog, scanner, and browse feed will adapt to your choice.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cardsStack: some View {
        VStack(spacing: BindrSpacing.md) {
            gameCard(
                brand: .pokemon,
                title: "Pokémon",
                tagline: "The original chase. Energy, sets, and TGs.",
                symbol: "bolt.fill",
                gradient: [Color(hex: "FFB02E"), Color(hex: "FF6F40"), Color(hex: "C0351F")],
                accentTag: "MOST POPULAR"
            )
            gameCard(
                brand: .onePiece,
                title: "ONE PIECE",
                tagline: "Manga rares, alt arts, the new frontier.",
                symbol: "sparkles",
                gradient: [Color(hex: "FF4A57"), Color(hex: "C8121E"), Color(hex: "660810")],
                accentTag: "FASTEST GROWING"
            )
        }
    }

    private func gameCard(
        brand: TCGBrand,
        title: String,
        tagline: String,
        symbol: String,
        gradient: [Color],
        accentTag: String
    ) -> some View {
        let isSelected = selectedBrand == brand
        return Button {
            Haptics.selectionChanged()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                selectedBrand = brand
            }
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: BindrRadius.xxl, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Foil shimmer overlay
                RoundedRectangle(cornerRadius: BindrRadius.xxl, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.32),
                                Color.white.opacity(0.0),
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.plusLighter)

                // Inner gloss highlight
                RoundedRectangle(cornerRadius: BindrRadius.xxl, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.5), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .padding(0.5)

                VStack(alignment: .leading, spacing: BindrSpacing.md) {
                    HStack {
                        Text(accentTag)
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .tracking(1.5)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.25), in: Capsule())
                            .foregroundStyle(.white)
                        Spacer()
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.85), lineWidth: 2)
                                .frame(width: 26, height: 26)
                            if isSelected {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 16, height: 16)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    HStack(alignment: .center, spacing: BindrSpacing.md) {
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.18))
                                .frame(width: 56, height: 56)
                            Image(systemName: symbol)
                                .font(.system(size: 26, weight: .black))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.system(size: 28, weight: .heavy))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(tagline)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(BindrSpacing.lg)
            }
            .frame(height: 200)
            .overlay {
                RoundedRectangle(cornerRadius: BindrRadius.xxl, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.9 : 0.2), lineWidth: isSelected ? 2 : 0.5)
            }
            .scaleEffect(isSelected ? 1.0 : 0.985)
            .rotation3DEffect(
                .degrees(isSelected ? -3 : 0),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.6
            )
            .shadow(
                color: (gradient.last ?? .black).opacity(isSelected ? 0.55 : 0.25),
                radius: isSelected ? 28 : 16,
                x: 0,
                y: isSelected ? 14 : 8
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: isSelected)
    }

    private var helperRow: some View {
        HStack(spacing: BindrSpacing.sm) {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text("Don't worry — you can add the other one later in Account.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var continueButton: some View {
        VStack(spacing: 0) {
            Button {
                Haptics.lightImpact()
                onContinue()
            } label: {
                HStack(spacing: 8) {
                    Text("Continue")
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
