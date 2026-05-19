import SwiftUI

// MARK: - OnboardingGameSelectionView
//
// Step 2. Refactor brief:
//   * Replaced the bespoke "MOST POPULAR / FASTEST GROWING" pills with a
//     borderless, muted subtitle line — same information without the
//     e-commerce feel.
//   * Selection chrome dropped the gradient-stroke outline + radio dot.
//     Selected card now uses a subtle solid background shift + native
//     `checkmark.circle.fill` accent.
//   * Icon backdrop tile retained but recolored to the brand-system
//     accent (no per-brand pastel).
//   * Primary CTA centred "Continue" — no trailing arrow.

struct OnboardingGameSelectionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent

    @Binding var selectedBrand: TCGBrand
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: BindrSpacing.xl) {
                    OnboardingHeadline(
                        title: "Your collection,\nyour game.",
                        subtitle: "Select the TCG you collect. Your catalog, scanner, and browse feed will adapt to your choice."
                    )
                    cardsStack
                    helperRow
                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, BindrSpacing.lg)
                .padding(.top, BindrSpacing.xl)
            }
            .scrollIndicators(.hidden)

            OnboardingFooterBar(
                primary: {
                    OnboardingPrimaryButton(title: "Continue", action: onContinue)
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cardsStack: some View {
        VStack(spacing: BindrSpacing.sm) {
            gameCard(
                brand: .pokemon,
                title: "Pokémon",
                tagline: "The original chase. Energy, sets, and TGs.",
                symbol: "bolt"
            )
            gameCard(
                brand: .onePiece,
                title: "ONE PIECE",
                tagline: "Manga rares, alt arts, the new frontier.",
                symbol: "sparkles"
            )
        }
    }

    private func gameCard(
        brand: TCGBrand,
        title: String,
        tagline: String,
        symbol: String
    ) -> some View {
        let isSelected = selectedBrand == brand
        return Button {
            Haptics.selectionChanged()
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedBrand = brand
            }
        } label: {
            HStack(spacing: BindrSpacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isSelected ? accent : .secondary)
                    .frame(width: 32, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(tagline)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                // Native checkmark selection cue. No radio dot, no
                // gradient stroke — just the iOS-standard "selected" mark.
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isSelected ? accent : Color.primary.opacity(0.18))
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(BindrSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // Subtle solid background shift instead of a stroke +
                // gradient outline. Reads as iOS-native selection.
                RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                    .fill(isSelected
                          ? accent.opacity(colorScheme == .dark ? 0.14 : 0.08)
                          : Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.04))
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }

    private var helperRow: some View {
        HStack(spacing: BindrSpacing.sm) {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
            Text("You can add the other one later in Account.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}
