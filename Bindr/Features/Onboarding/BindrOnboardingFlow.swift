import SwiftUI
import SwiftData

// MARK: - BindrOnboardingFlow
//
// 6-screen first-run experience:
//   1. Welcome                                     — `OnboardingWelcomeView`
//   2. Theme & accent color                        — `OnboardingThemeView`
//   3. Enable offline collection                   — `OnboardingOfflineModeView`
//   4. Enable notifications                        — `OnboardingNotificationsView`
//   5. Social sign-in                              — `OnboardingSocialView`
//   6. Premium subscription upsell                 — `OnboardingPremiumView`

struct BindrOnboardingFlow: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent

    @Binding var isPresented: Bool
    var onWillDismiss: (() -> Void)? = nil
    @State private var step: BindrOnboardingStep = .welcome
    @State private var didFinish = false

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
            case .theme:
                OnboardingThemeView(
                    onContinue: { advance() },
                    onSkip: { advance() }
                )
                .transition(stepTransition)
            case .offline:
                OnboardingOfflineModeView(
                    brand: .pokemon,
                    onContinue: { advance() },
                    onSkip: { advance() }
                )
                .transition(stepTransition)
            case .notifications:
                OnboardingNotificationsView(onContinue: { advance() })
                    .transition(stepTransition)
            case .social:
                OnboardingSocialView(
                    onContinue: { advance() },
                    onSkip: { advance() }
                )
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
        if let next = step.next {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                step = next
            }
        } else {
            finish()
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        Haptics.success()
        Task { @MainActor in
            if services.socialAuth.isSignedIn {
                await services.restoreCloudBackupAfterSignIn(modelContext: modelContext)
            } else {
                services.markLaunchCloudBackupRestoreSkipped()
            }
            services.brandSettings.completeBrandOnboarding()
            services.schedulePostBootstrapOfflineImageDownload(for: .pokemon)
            onWillDismiss?()
            withAnimation(.easeInOut(duration: 0.3)) {
                isPresented = false
            }
        }
    }
}

// MARK: - Step model

enum BindrOnboardingStep: Int, CaseIterable {
    case welcome       = 0
    case theme         = 1
    case offline       = 2
    case notifications = 3
    case social        = 4
    case premium       = 5

    var next: BindrOnboardingStep? {
        BindrOnboardingStep(rawValue: rawValue + 1)
    }
}
