import SwiftUI

enum SocialSignInLegalStyle {
    case compact
    case standard
}

/// Terms, privacy, and third-party auth disclosure shown beneath social sign-in CTAs.
struct SocialSignInLegalFooter: View {
    @Environment(\.bindrAccent) private var accent

    var style: SocialSignInLegalStyle = .standard

    private static let privacyURL = URL(string: "https://www.bindr-tcg.com/privacy")!
    private static let termsURL = URL(string: "https://www.bindr-tcg.com/terms")!
    private static let applePrivacyURL = URL(string: "https://www.apple.com/legal/privacy/")!
    private static let googlePrivacyURL = URL(string: "https://policies.google.com/privacy")!
    private static let googleTermsURL = URL(string: "https://policies.google.com/terms")!

    var body: some View {
        switch style {
        case .compact:
            compactFooter
        case .standard:
            standardFooter
        }
    }

    private var compactFooter: some View {
        VStack(spacing: 10) {
            Text("By continuing, you agree to Bindr’s Terms and Privacy. Sign-in is optional and not required for Premium.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                footerLink("Terms", destination: Self.termsURL)
                footerSeparator
                footerLink("Privacy", destination: Self.privacyURL)
                footerSeparator
                providerPoliciesMenu
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var standardFooter: some View {
        VStack(spacing: BindrSpacing.sm) {
            Text(
                "By continuing, you agree to Bindr’s Terms of Service and Privacy Policy. "
                + "Sign in with Apple or Google is optional and not required for Bindr Premium."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Text(
                "Apple and Google authenticate you under their own terms. "
                + "We receive an account identifier and may receive your name and email depending on what each provider shares."
            )
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    footerLink("Terms", destination: Self.termsURL)
                    footerSeparator
                    footerLink("Privacy", destination: Self.privacyURL)
                }

                HStack(spacing: 6) {
                    footerLink("Apple Privacy", destination: Self.applePrivacyURL)
                    footerSeparator
                    footerLink("Google Privacy", destination: Self.googlePrivacyURL)
                    footerSeparator
                    footerLink("Google Terms", destination: Self.googleTermsURL)
                }
            }
            .multilineTextAlignment(.center)
        }
    }

    private var providerPoliciesMenu: some View {
        Menu {
            Link("Apple Privacy Policy", destination: Self.applePrivacyURL)
            Link("Google Privacy Policy", destination: Self.googlePrivacyURL)
            Link("Google Terms of Service", destination: Self.googleTermsURL)
        } label: {
            HStack(spacing: 4) {
                Text("Provider policies")
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(accent)
        }
    }

    private var footerSeparator: some View {
        Text("·").foregroundStyle(.tertiary)
    }

    private func footerLink(_ title: String, destination: URL) -> some View {
        Link(title, destination: destination)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(accent)
    }
}
