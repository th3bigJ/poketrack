import SwiftUI

// MARK: - OnboardingGameSelectionView
//
// Step 2 of `BindrOnboardingFlow`. Two clean selection cards let the user
// pick their TCG. Uses the same glass card style as the rest of the app
// rather than bespoke gradient cards.
//
// Selection contract:
//   * `selectedBrand` defaults to `.pokemon` and is updated on tap.
//   * `onContinue` is always enabled since Pokémon is pre-selected.
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
                accentTag: "MOST POPULAR",
                tint: Color(hex: "FF6F40")
            )
            gameCard(
                brand: .onePiece,
                title: "ONE PIECE",
                tagline: "Manga rares, alt arts, the new frontier.",
                symbol: "sparkles",
                accentTag: "FASTEST GROWING",
                tint: Color(hex: "E8192C")
            )
        }
    }

    private func gameCard(
        brand: TCGBrand,
        title: String,
        tagline: String,
        symbol: String,
        accentTag: String,
        tint: Color
    ) -> some View {
        let isSelected = selectedBrand == brand
        return Button {
            Haptics.selectionChanged()
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedBrand = brand
            }
        } label: {
            HStack(spacing: BindrSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: BindrRadius.md, style: .continuous)
                        .fill(tint.opacity(colorScheme == .dark ? 0.20 : 0.14))
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: BindrSpacing.sm) {
                        Text(title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.primary)
                        Text(accentTag)
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background { Capsule().fill(tint.opacity(0.15)) }
                    }
                    Text(tagline)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .stroke(isSelected ? accent : Color.primary.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                    if isSelected {
                        Circle()
                            .fill(accent)
                            .frame(width: 14, height: 14)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: isSelected)
            }
            .padding(BindrSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCardStyle(cornerRadius: BindrRadius.xl, interactive: false)
            .overlay {
                RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                    .stroke(isSelected ? accent.opacity(0.55) : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
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
