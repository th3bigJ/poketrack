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
    let rootFloatingChromeInset: CGFloat
    let onSignInResult: (Result<ASAuthorization, Error>) -> Void

    @State private var hasAppeared = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: BindrSpacing.xxl) {
                    heroBlock
                    pulseBlock
                    activityBlock
                    featuresBlock
                    socialProofBlock

                    // Bottom safe area for the floating CTA panel.
                    Color.clear.frame(height: 180)
                }
                .padding(.horizontal, BindrSpacing.lg)
                .padding(.top, BindrSpacing.lg)
            }
            .contentMargins(.top, rootFloatingChromeInset + 16, for: .scrollContent)
            .scrollIndicators(.hidden)

            ctaPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .bindrPageBackground(ignoresSafeArea: false)
        .onAppear {
            // Stagger-fade the hero on first appearance so it doesn't snap
            // in if the user navigated here while another transition was
            // still in flight.
            withAnimation(.easeOut(duration: 0.45)) {
                hasAppeared = true
            }
        }
    }

    // MARK: Hero

    private var heroBlock: some View {
        VStack(spacing: BindrSpacing.lg) {
            SocialSectionEyebrow(title: "JOIN THE HUNT", accentDot: true)

            VStack(spacing: 0) {
                Text("The hunt hits")
                    .font(.system(size: 38, weight: .heavy))
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Text("different")
                        .font(.system(size: 38, weight: .heavy))
                        .italic()
                        .foregroundStyle(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Text("together.")
                        .font(.system(size: 38, weight: .heavy))
                        .italic()
                    Spacer(minLength: 0)
                }
            }
            .multilineTextAlignment(.leading)

            Text("One tap into the collector network — see pulls happen live, track grails before they disappear, and trade with friends who actually want what you're sitting on.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(2)

            ZStack {
                heroBackdropGlow
                FloatingCardStack()
                    .frame(height: 280)
                    .offset(y: hasAppeared ? 0 : 20)
                    .opacity(hasAppeared ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, BindrSpacing.sm)
        }
    }

    private var heroBackdropGlow: some View {
        ZStack {
            RadialGradient(
                colors: [accent.opacity(colorScheme == .dark ? 0.30 : 0.18), .clear],
                center: .center,
                startRadius: 10,
                endRadius: 260
            )
            .blur(radius: 30)

            RadialGradient(
                colors: [BindrPalette.binderGold.opacity(0.18), .clear],
                center: UnitPoint(x: 0.85, y: 0.2),
                startRadius: 5,
                endRadius: 180
            )
            .blur(radius: 24)
        }
        .frame(height: 320)
        .allowsHitTesting(false)
    }

    // MARK: Pulse stats

    private var pulseBlock: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.md) {
            SocialSectionEyebrow(title: "COMMUNITY PULSE")
            CollectorPulseStats()
        }
    }

    // MARK: Live activity

    private var activityBlock: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.md) {
            HStack {
                SocialSectionEyebrow(title: "LIVE NOW", accentDot: true)
                Spacer()
                Text("Trade Wall + Feed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            LiveActivityTicker()
                .frame(minHeight: 180)
        }
    }

    // MARK: Features

    private var featuresBlock: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.md) {
            SocialSectionEyebrow(title: "WHAT YOU UNLOCK")

            VStack(spacing: BindrSpacing.sm) {
                SocialFeatureCard(
                    icon: "arrow.left.arrow.right",
                    title: "Trade Wall access",
                    description: "List, browse, and lock in deals with collectors moving the same cards as you.",
                    tint: BindrPalette.deckBlue,
                    index: 1
                )
                SocialFeatureCard(
                    icon: "sparkles",
                    title: "See pulls happen live",
                    description: "Real-time feed of friends pulling, listing, and chasing.",
                    tint: BindrPalette.ownedGreen,
                    index: 2
                )
                SocialFeatureCard(
                    icon: "crown.fill",
                    title: "Grail alerts",
                    description: "Get pinged the second yours hits the wall. Move first.",
                    tint: BindrPalette.binderGold,
                    index: 3
                )
                SocialFeatureCard(
                    icon: "person.crop.square.filled.and.at.rectangle",
                    title: "Collection profile",
                    description: "Your binder, finally worth showing off. Share a page collectors want to see.",
                    tint: BindrPalette.wishlistViolet,
                    index: 4
                )
                SocialFeatureCard(
                    icon: "bubble.left.and.bubble.right.fill",
                    title: "Hype, comments, reactions",
                    description: "Trainers move fast. So does the love when you pull something dirty.",
                    tint: BindrPalette.alertRed,
                    index: 5
                )
            }
        }
    }

    // MARK: Social proof

    private var socialProofBlock: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.md) {
            SocialSectionEyebrow(title: "WHY COLLECTORS STAY")

            VStack(spacing: BindrSpacing.sm) {
                proofQuote(
                    text: "Locked in three trades in a week. This is where collectors actually move.",
                    author: "@robin · Grail hunter"
                )
                proofQuote(
                    text: "Pull notifications hit harder than card breaks now.",
                    author: "@dre.tcg · 1,402 cards"
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
            .shadow(color: accent.opacity(colorScheme == .dark ? 0.45 : 0.22), radius: 18, x: 0, y: 6)
            .padding(.horizontal, BindrSpacing.lg)

            Text("By continuing you agree to Bindr's Terms & Privacy.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 6)
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
