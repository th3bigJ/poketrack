import SwiftUI

// MARK: - BindrOnboardingFlow
//
// 5-screen first-run experience:
//   1. Welcome                                     — `OnboardingWelcomeView`
//   2. Pick your game (Pokémon / One Piece)        — `OnboardingGameSelectionView`
//   3. Enable offline collection                   — `OnboardingOfflineModeView`
//   4. Enable notifications                        — `OnboardingNotificationsView`
//   5. Premium subscription upsell                 — `OnboardingPremiumView`
//
// Routing contract:
//   * The flow is dismissable: `isPresented` binding tracked by the host
//     (`RootView`).
//   * On final step completion we call `services.brandSettings.completeBrandOnboarding()`
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
    /// Called synchronously just before `isPresented` is set to false, so the
    /// host can flip its own state in the same pass and avoid a blank-frame gap.
    var onWillDismiss: (() -> Void)? = nil
    @State private var step: BindrOnboardingStep = .welcome
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
        .onDisappear {
            // Safety net: if the sheet is dismissed by ANY means (interactive
            // gesture in Simulator, system modal stack dismissal, etc.) without
            // finish() being called, still unblock the launch pipeline.
            if !services.brandSettings.hasCompletedBrandOnboarding {
                services.brandSettings.completeBrandOnboarding()
            }
        }
    }

    @ViewBuilder
    private var contentStack: some View {
        ZStack {
            switch step {
            case .welcome:
                OnboardingWelcomeView(onContinue: { advance() })
                    .transition(stepTransition)
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
            case .notifications:
                OnboardingNotificationsView(onContinue: { advance() })
                    .transition(stepTransition)
            case .premium:
                OnboardingPremiumView(onFinish: { finish() })
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
                advance()
            } label: {
                Text("Skip")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(skipHidden ? 0 : 1)
        }
    }

    private var skipHidden: Bool {
        step == .welcome || step == .notifications || step == .premium
    }

    private func advance() {
        Haptics.lightImpact()
        // Apply game selection at the moment we leave the picker so the
        // brand-bootstrap pipeline has the correct enabled set even if
        // the user backs out of the flow mid-way.
        if step == .game {
            services.brandSettings.enabledBrands = [selectedBrand]
            services.brandSettings.selectedCatalogBrand = selectedBrand
            services.prefetchCatalogInBackground(for: [selectedBrand])
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
        // Start the offline pack download now that all onboarding transitions are done.
        if services.offlineImageSettings.isOfflinePackEnabled(for: selectedBrand) {
            Task {
                await services.offlineImageDownload.runFullDownloadIfNeeded(
                    brand: selectedBrand,
                    nationalDexPokemon: services.cardData.nationalDexPokemon,
                    sealedProducts: services.sealedProducts.products
                )
            }
        }
        onWillDismiss?()
        withAnimation(.easeInOut(duration: 0.3)) {
            isPresented = false
        }
    }
}

// MARK: - Step model

enum BindrOnboardingStep: Int, CaseIterable {
    case welcome       = 0
    case game          = 1
    case offline       = 2
    case notifications = 3
    case premium       = 4

    var next: BindrOnboardingStep? {
        BindrOnboardingStep(rawValue: rawValue + 1)
    }
}
