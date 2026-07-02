import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

// MARK: - SocialLandingView
//
// Replaces the original `SocialSignInUpsellView` placeholder. The screen
// is built around a single emotional pitch — *"the collector ecosystem is
// already alive, you just aren't in it yet"* — and surfaces that with a
// floating-card hero, live activity ticker, and per-feature glass tiles.
//
// Auth flow:
//   * Apple Sign-In remains the primary CTA. The nonce + signing is owned
//     by this view (mirroring the original implementation) and bubbled up
//     to `SocialRootView` via the `onSignInResult` callback.
//   * Future auth providers (Jordan) plug in below the Apple button via
//     `secondaryAuthSlot` — currently rendered as a placeholder "Continue
//     with Email" affordance so the layout reserves room.
//
// This view never reaches into `AppServices` directly so it can be
// previewed and reused inside onboarding / friend invite surfaces.

struct SocialLandingView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent

    @Binding var currentNonce: String?
    let errorMessage: String?
    let headerInset: CGFloat
    let isBusy: Bool
    let onSignInResult: (Result<ASAuthorization, Error>) -> Void
    let onGoogleSignIn: () -> Void

    init(
        currentNonce: Binding<String?>,
        errorMessage: String?,
        headerInset: CGFloat,
        isBusy: Bool = false,
        onSignInResult: @escaping (Result<ASAuthorization, Error>) -> Void,
        onGoogleSignIn: @escaping () -> Void = {}
    ) {
        self._currentNonce = currentNonce
        self.errorMessage = errorMessage
        self.headerInset = headerInset
        self.isBusy = isBusy
        self.onSignInResult = onSignInResult
        self.onGoogleSignIn = onGoogleSignIn
    }

    var body: some View {
        ScrollView {
            VStack(spacing: BindrSpacing.xl) {
                heroBlock
                featuresBlock
                signInSection
            }
            .padding(.horizontal, BindrSpacing.lg)
            .padding(.bottom, RootChromeEnvironment.floatingTabBarContentInset)
        }
        .contentMargins(.top, headerInset, for: .scrollContent)
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Hero

    private var heroBlock: some View {
        VStack(spacing: BindrSpacing.lg) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Connect with the")
                    .font(.system(size: 30, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Text("community.")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(accent)
                    Spacer(minLength: 0)
                }
            }
            .multilineTextAlignment(.leading)

            Text("Share your collection, spot trade opportunities, and react to friends' pulls. Sign in with Apple or Google to join the network.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(2)
        }
    }

    // MARK: Features

    private var featuresBlock: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.md) {
            SocialSectionEyebrow(title: "IN THE SOCIAL TAB")

            VStack(spacing: BindrSpacing.sm) {
                SocialFeatureCard(
                    icon: "arrow.left.arrow.right",
                    title: "Trade Wall",
                    description: "See suggested matches, wishlist opportunities, and friends' available cards in one place.",
                    index: 1
                )
                SocialFeatureCard(
                    icon: "sparkles",
                    title: "Activity feed",
                    description: "See pulls, binder shares, and accepted trades as they happen.",
                    index: 2
                )
                SocialFeatureCard(
                    icon: "star",
                    title: "Wishlist alerts",
                    description: "Know when a friend has a card from your wishlist available.",
                    index: 3
                )
                SocialFeatureCard(
                    icon: "person.crop.square",
                    title: "Public Showcase",
                    description: "Share your binders and collections with a premium profile.",
                    index: 4
                )
                SocialFeatureCard(
                    icon: "bubble.left.and.bubble.right",
                    title: "Interactions",
                    description: "React to pulls and stay connected with other collectors.",
                    index: 5
                )
            }
        }
    }

    // MARK: Sign in

    private var signInSection: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.md) {
            Text("Get started")
                .font(.title3.weight(.semibold))

            VStack(spacing: BindrSpacing.md) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(BindrPalette.alertRed)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                SocialSignInButtons(
                    currentNonce: $currentNonce,
                    isBusy: isBusy,
                    legalStyle: .compact,
                    showsGoogleUnavailableCaption: false,
                    onAppleSignInResult: { result in
                        onSignInResult(result)
                    },
                    onGoogleSignIn: onGoogleSignIn
                )
            }
            .padding(BindrSpacing.lg)
            .glassCardStyle(cornerRadius: BindrRadius.xl, interactive: false)
        }
    }
}

// MARK: - Nonce helpers

/// Pulled out of `SocialRootView` so any future sign-in surface (onboarding,
/// invite link landing, etc.) can reuse the same nonce generation without
/// duplicating the SHA / random logic.
enum SocialNonceGenerator {
    static func random(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var bytes = [UInt8](repeating: 0, count: 16)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            bytes.forEach { byte in
                guard remaining > 0, byte < charset.count else { return }
                result.append(charset[Int(byte)])
                remaining -= 1
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        let digest = CryptoKit.SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
