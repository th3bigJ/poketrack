import AuthenticationServices
import SwiftUI

/// Shared Apple + Google sign-in controls used by onboarding, social landing,
/// and account surfaces. Google appears when social auth is configured but
/// stays disabled until Google OAuth credentials are added to Info.plist.
struct SocialSignInButtons: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var currentNonce: String?
    let isBusy: Bool
    let showsGoogle: Bool
    let isGoogleAvailable: Bool
    let showsLegalFooter: Bool
    let legalStyle: SocialSignInLegalStyle
    let showsGoogleUnavailableCaption: Bool
    let onAppleSignInResult: (Result<ASAuthorization, Error>) -> Void
    let onGoogleSignIn: () -> Void

    init(
        currentNonce: Binding<String?>,
        isBusy: Bool = false,
        showsGoogle: Bool = AppConfiguration.showsGoogleSignInButton,
        isGoogleAvailable: Bool = AppConfiguration.isGoogleSignInAvailable,
        showsLegalFooter: Bool = true,
        legalStyle: SocialSignInLegalStyle = .standard,
        showsGoogleUnavailableCaption: Bool = true,
        onAppleSignInResult: @escaping (Result<ASAuthorization, Error>) -> Void,
        onGoogleSignIn: @escaping () -> Void
    ) {
        self._currentNonce = currentNonce
        self.isBusy = isBusy
        self.showsGoogle = showsGoogle
        self.isGoogleAvailable = isGoogleAvailable
        self.showsLegalFooter = showsLegalFooter
        self.legalStyle = legalStyle
        self.showsGoogleUnavailableCaption = showsGoogleUnavailableCaption
        self.onAppleSignInResult = onAppleSignInResult
        self.onGoogleSignIn = onGoogleSignIn
    }

    var body: some View {
        VStack(spacing: BindrSpacing.md) {
            VStack(spacing: BindrSpacing.sm) {
                appleButton
                if showsGoogle {
                    googleButton
                }
            }

            if showsLegalFooter {
                SocialSignInLegalFooter(style: legalStyle)
            }
        }
    }

    private var appleButton: some View {
        ZStack {
            SignInWithAppleButton(.signIn) { request in
                let nonce = SocialNonceGenerator.random()
                currentNonce = nonce
                request.requestedScopes = [.email, .fullName]
                request.nonce = SocialNonceGenerator.sha256(nonce)
            } onCompletion: { result in
                Haptics.lightImpact()
                onAppleSignInResult(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous))
            .disabled(isBusy)
            .opacity(isBusy ? 0.35 : 1)

            if isBusy {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(colorScheme == .dark ? .white : .black)
            }
        }
    }

    private var googleButton: some View {
        VStack(spacing: 6) {
            Button {
                guard !isBusy, isGoogleAvailable else { return }
                Haptics.lightImpact()
                onGoogleSignIn()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Continue with Google")
                        .font(.system(size: 17, weight: .semibold))
                    Spacer(minLength: 0)
                    if !isGoogleAvailable {
                        Text("Soon")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                }
                .foregroundStyle(isGoogleAvailable ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .padding(.horizontal, BindrSpacing.md)
                .background {
                    RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(isBusy || !isGoogleAvailable)
            .opacity(isBusy ? 0.35 : (isGoogleAvailable ? 1 : 0.72))

            if !isGoogleAvailable, showsGoogleUnavailableCaption {
                Text("Google sign-in will be enabled in a future update.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

/// Bottom fade used by onboarding and social sign-in panels so CTAs sit over
/// the themed page background instead of a flat systemBackground slab.
struct OnboardingStickyFooterBackground: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.85), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea(edges: .bottom)
    }
}
