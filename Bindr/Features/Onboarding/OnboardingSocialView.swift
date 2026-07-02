import AuthenticationServices
import SwiftData
import SwiftUI

// MARK: - OnboardingSocialView
//
// Step 4. Social sign-in before the premium upsell.
// Matches the shared onboarding layout: headline, feature rows, footer CTA.
// Apple Sign-In is the primary action; users can skip and set up social later.

struct OnboardingSocialView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent

    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var currentNonce: String?
    @State private var errorMessage: String?
    @State private var isSigningIn = false
    @State private var isRestoringLibrary = false
    @State private var didContinue = false

    private var isConfigured: Bool {
        AppConfiguration.supabaseURL != nil && !AppConfiguration.supabasePublishableKey.isEmpty
    }

    private var isSignedIn: Bool {
        services.socialAuth.isSignedIn
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: BindrSpacing.xl) {
                    OnboardingHeadline(
                        title: "Join the\ncommunity.",
                        subtitle: "Sign in with Apple or Google to share binders, spot trade matches, and follow friends' latest pulls."
                    )

                    if !isConfigured {
                        configurationNotice
                    } else if isSignedIn {
                        signedInBanner
                    }

                    socialFeatures
                    Color.clear.frame(height: 140)
                }
                .padding(.horizontal, BindrSpacing.lg)
                .padding(.top, BindrSpacing.xl)
            }
            .scrollIndicators(.hidden)

            OnboardingFooterBar(
                primary: { footerPrimary },
                secondary: {
                    if isSignedIn || !isConfigured {
                        EmptyView()
                    } else {
                        OnboardingSecondaryLink(title: "Not now", action: skipOnce)
                    }
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await services.socialAuth.restoreSession()
            if services.socialAuth.isSignedIn {
                await restoreLibraryFromCloud()
            }
        }
    }

    private func restoreLibraryFromCloud() async {
        guard !isRestoringLibrary else { return }
        isRestoringLibrary = true
        defer { isRestoringLibrary = false }
        await services.restoreCloudBackupAfterSignIn(modelContext: modelContext)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerPrimary: some View {
        VStack(spacing: BindrSpacing.sm) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(BindrPalette.alertRed)
                    .multilineTextAlignment(.center)
            }

            if !isConfigured {
                OnboardingPrimaryButton(title: "Continue", action: continueOnce)
            } else if isRestoringLibrary || services.collectionSync.isRestoring {
                OnboardingPrimaryButton(title: "Restoring library…", action: {})
                    .disabled(true)
            } else if isSignedIn {
                OnboardingPrimaryButton(title: "Continue", action: continueOnce)
            } else {
                SocialSignInButtons(
                    currentNonce: $currentNonce,
                    isBusy: isSigningIn,
                    onAppleSignInResult: { result in
                        Task { await handleAppleSignInResult(result) }
                    },
                    onGoogleSignIn: {
                        Task { await handleGoogleSignIn() }
                    }
                )
            }
        }
    }

    // MARK: - Content blocks

    private var configurationNotice: some View {
        Text("Social features aren't configured in this build. You can set up your profile later from the Social tab.")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(BindrSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCardStyle(cornerRadius: BindrRadius.lg, interactive: false)
    }

    private var signedInBanner: some View {
        HStack(spacing: BindrSpacing.md) {
            if isRestoringLibrary || services.collectionSync.isRestoring {
                ProgressView()
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(BindrPalette.ownedGreen)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isRestoringLibrary || services.collectionSync.isRestoring
                     ? "Restoring your library…"
                     : "Signed in")
                    .font(.system(size: 15, weight: .semibold))
                Text(isRestoringLibrary || services.collectionSync.isRestoring
                     ? "Downloading your cloud backup before you continue."
                     : "Your social profile is ready to set up.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, BindrSpacing.md)
        .padding(.vertical, BindrSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(cornerRadius: BindrRadius.lg, interactive: false)
    }

    private var socialFeatures: some View {
        VStack(spacing: BindrSpacing.sm) {
            OnboardingFeatureRow(
                icon: "arrow.left.arrow.right",
                title: "Trade Wall",
                description: "See suggested matches, wishlist opportunities, and friends' available cards."
            )
            OnboardingFeatureRow(
                icon: "sparkles",
                title: "Activity feed",
                description: "Follow pulls, binder shares, and accepted trades as they happen."
            )
            OnboardingFeatureRow(
                icon: "star",
                title: "Wishlist alerts",
                description: "Know when a friend has a card from your wishlist available."
            )
            OnboardingFeatureRow(
                icon: "person.crop.square",
                title: "Public showcase",
                description: "Share binders and collections with a profile other collectors can discover."
            )
        }
    }

    // MARK: - Auth

    private func handleGoogleSignIn() async {
        errorMessage = nil
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            try await services.socialAuth.signInWithGoogleOAuth()
            await services.socialPush.updateRegistrationState()
            await restoreLibraryFromCloud()
            if !didContinue {
                continueOnce()
            }
        } catch let error as GoogleOAuthSession.OAuthError {
            if case .cancelled = error { return }
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Sign in with Apple returned an unexpected credential type."
                return
            }
            guard
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = "Unable to read Apple identity token."
                return
            }

            try await services.socialAuth.signInWithApple(
                idToken: idToken,
                rawNonce: currentNonce,
                appleUserIdentifier: credential.user
            )
            await services.socialPush.updateRegistrationState()
            await restoreLibraryFromCloud()
            if !didContinue {
                continueOnce()
            }
        } catch {
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func skipOnce() {
        guard !didContinue else { return }
        didContinue = true
        onSkip()
    }

    private func continueOnce() {
        guard !didContinue else { return }
        didContinue = true
        onContinue()
    }
}
