import SwiftUI

// MARK: - BindrOnboardingFlow
//
// 3-screen first-run experience.
//
// Replaces the old `BrandOnboardingView` list-style picker with an
// interactive flow:
//   1. Pick your game (Pokémon / One Piece)        — `OnboardingGameSelectionView`
//   2. Enable offline collection                   — `OnboardingOfflineModeView`
//   3. Discover the social / community layer       — `OnboardingSocialDiscoveryView`
//
// Routing contract:
//   * The flow is dismissable: `isPresented` binding tracked by the host
//     (`RootView`).
//   * On step-3 completion we call `services.brandSettings.completeBrandOnboarding()`
//     for the same downstream effects as the original brand picker had —
//     this keeps the rest of the launch pipeline (catalog bootstrap,
//     splash gating) unchanged.
//
// Progression model is `BindrOnboardingStep` + a small page indicator
// pinned to the top so users always know how far they have to go.

struct BindrOnboardingFlow: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent

    @Binding var isPresented: Bool
    @State private var step: BindrOnboardingStep = .game
    @State private var selectedBrand: TCGBrand = .pokemon

    var body: some View {
        ZStack {
            BindrPageBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                progressHeader
                    .padding(.top, BindrSpacing.lg)
                    .padding(.horizontal, BindrSpacing.lg)

                contentStack
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .interactiveDismissDisabled()
        .preferredColorScheme(services.theme.colorScheme)
    }

    @ViewBuilder
    private var contentStack: some View {
        ZStack {
            switch step {
            case .game:
                OnboardingGameSelectionView(
                    selectedBrand: $selectedBrand,
                    onContinue: { advance() }
                )
                .transition(stepTransition)
            case .offline:
                OnboardingOfflineModeView(
                    brand: selectedBrand,
                    onContinue: { advance() },
                    onSkip: { advance() }
                )
                .transition(stepTransition)
            case .social:
                OnboardingSocialDiscoveryView(
                    onFinish: { finish() }
                )
                .transition(stepTransition)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: step)
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    // MARK: Progress header

    private var progressHeader: some View {
        HStack(spacing: BindrSpacing.sm) {
            ForEach(BindrOnboardingStep.allCases, id: \.self) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? accent : Color.primary.opacity(0.12))
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.32), value: step)
            }

            Spacer(minLength: BindrSpacing.md)

            Button {
                Haptics.lightImpact()
                if step == .social {
                    finish()
                } else {
                    advance()
                }
            } label: {
                Text(step == .social ? "" : "Skip")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(step == .social ? 0 : 1)
        }
    }

    private func advance() {
        Haptics.lightImpact()
        // Apply game selection at the moment we leave the picker so the
        // brand-bootstrap pipeline has the correct enabled set even if
        // the user backs out of the flow mid-way.
        if step == .game {
            services.brandSettings.enabledBrands = [selectedBrand]
            services.brandSettings.selectedCatalogBrand = selectedBrand
        }
        if let next = step.next {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                step = next
            }
        } else {
            finish()
        }
    }

    private func finish() {
        Haptics.success()
        services.brandSettings.enabledBrands = [selectedBrand]
        services.brandSettings.selectedCatalogBrand = selectedBrand
        services.brandSettings.completeBrandOnboarding()
        withAnimation(.easeInOut(duration: 0.3)) {
            isPresented = false
        }
    }
}

// MARK: - Step model

enum BindrOnboardingStep: Int, CaseIterable {
    case game = 0
    case offline = 1
    case social = 2

    var next: BindrOnboardingStep? {
        BindrOnboardingStep(rawValue: rawValue + 1)
    }
}
