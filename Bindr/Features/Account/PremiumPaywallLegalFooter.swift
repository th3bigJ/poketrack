import SwiftUI

/// Subscription disclosure and legal links shown beneath paywall CTAs.
struct PremiumPaywallLegalFooter: View {
    @Environment(\.bindrAccent) private var accent

    let disclosureText: String

    private static let privacyURL = URL(string: "https://www.bindr-tcg.com/privacy")!
    private static let termsURL = URL(string: "https://www.bindr-tcg.com/terms")!

    var body: some View {
        VStack(spacing: BindrSpacing.xs) {
            Text(disclosureText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                Link("Privacy Policy", destination: Self.privacyURL)
                Text("·")
                    .foregroundStyle(.tertiary)
                Link("Terms of Service", destination: Self.termsURL)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity)
    }
}
