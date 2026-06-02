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
    let onSignInResult: (Result<ASAuthorization, Error>) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: BindrSpacing.lg) {
                    heroBlock
                    featuresBlock

                    // Bottom safe area for the floating CTA panel.
                    Color.clear.frame(height: 180)
                }
                .padding(.horizontal, BindrSpacing.lg)
            }
            .contentMargins(.top, headerInset, for: .scrollContent)
            .scrollIndicators(.hidden)

            ctaPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .bindrPageBackground(ignoresSafeArea: false)
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

            Text("Share your collection, discover suggested trades, and react to friends' pulls. Sign in with iCloud to join the network.")
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
                // All feature icons use the accent tint via the
                // SocialFeatureCard default — no per-tile pastel mixing.
                SocialFeatureCard(
                    icon: "arrow.left.arrow.right",
                    title: "Trade Network",
                    description: "Auto-find suggested trades based on wishlists and trade lists.",
                    index: 1
                )
                SocialFeatureCard(
                    icon: "sparkles",
                    title: "Activity feed",
                    description: "See pulls, binders, and trades as they happen in real-time.",
                    index: 2
                )
                SocialFeatureCard(
                    icon: "star",
                    title: "Wishlist alerts",
                    description: "Be notified the moment a card you want becomes available for trade.",
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



    private func proofQuote(text: String, author: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "quote.opening")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(accent.opacity(0.7))
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .lineSpacing(1)
            Text(author)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(BindrSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(cornerRadius: BindrRadius.xl, interactive: false)
    }

    // MARK: Sticky CTA panel

    /// Bottom panel hosts the Apple sign-in button, a secondary auth slot,
    /// and any error text from the most recent attempt. We mount it as a
    /// `ZStack` overlay rather than padding the scroll view so the CTA
    /// stays in thumb reach regardless of how far the user has scrolled.
    private var ctaPanel: some View {
        VStack(spacing: BindrSpacing.sm) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(BindrPalette.alertRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BindrSpacing.lg)
            }

            SignInWithAppleButton(.signIn) { request in
                let nonce = SocialNonceGenerator.random()
                currentNonce = nonce
                request.requestedScopes = [.email, .fullName]
                request.nonce = SocialNonceGenerator.sha256(nonce)
            } onCompletion: { result in
                Haptics.lightImpact()
                onSignInResult(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous))
            .padding(.horizontal, BindrSpacing.lg)

        }
        .padding(.top, BindrSpacing.md)
        .padding(.bottom, BindrSpacing.lg)
        .frame(maxWidth: .infinity)
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
            .ignoresSafeArea()
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
