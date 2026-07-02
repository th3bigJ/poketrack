import SwiftUI

struct TermsOfServiceView: View {
    private static let webURL = URL(string: "https://www.bindr-tcg.com/terms")!
    private static let contactEmail = "info@bindr-tcg.com"

    private let sections: [LegalPolicySection] = [
        LegalPolicySection(
            title: "1. About Bindr",
            blocks: [
                .paragraph("Bindr is an independent app for Pokémon TCG collection management, card scanning, pricing reference, deck and binder organisation, trading tools, and optional social features."),
                .paragraph("Bindr is not affiliated with, endorsed by, sponsored by, approved by, or officially connected with The Pokémon Company International, Nintendo, Creatures Inc., GAME FREAK, any marketplace, grading company, tournament organiser, retailer, or platform unless expressly stated in the App.")
            ]
        ),
        LegalPolicySection(
            title: "2. Eligibility",
            blocks: [
                .paragraph("You must be at least 13 years old to use Bindr, or the minimum age required in your country if higher. If you are under 18, you should use the App with permission from a parent or guardian.")
            ]
        ),
        LegalPolicySection(
            title: "3. Accounts",
            blocks: [
                .bullets([
                    "Many features work without an account.",
                    "Social features and cloud backup require you to sign in, including through Sign in with Apple, Sign in with Google (when available), or email/password where offered.",
                    "You are responsible for activity on your account and for keeping your device secure.",
                    "You must provide accurate profile information and not impersonate others.",
                    "You may delete your account at any time in More → Account & Privacy → Delete Account and Data.",
                    "If you use Sign in with Apple or Sign in with Google, you also agree to the applicable terms and privacy policies of Apple or Google for that authentication step. Bindr receives only the account information described in our Privacy Policy."
                ])
            ]
        ),
        LegalPolicySection(
            title: "4. Bindr Premium subscriptions",
            blocks: [
                .subtitle("4.1 Overview"),
                .paragraph("Bindr offers an optional auto-renewable subscription called Bindr Premium with monthly and annual plans. Premium unlocks higher limits and additional features compared to the free tier."),
                .subtitle("4.2 Billing through Apple"),
                .paragraph("All purchases are processed by Apple through your Apple ID. We do not collect or store your payment card information. Apple's terms and privacy policy apply to billing and payment processing."),
                .subtitle("4.3 Auto-renewal"),
                .paragraph("Subscriptions automatically renew unless cancelled at least 24 hours before the end of the current billing period. Your Apple ID account will be charged for renewal within 24 hours prior to the end of the current period at the price shown in the App Store at the time of renewal."),
                .subtitle("4.4 Managing and cancelling"),
                .paragraph("You can manage or cancel your subscription at any time in iOS Settings → Apple ID → Subscriptions. Deleting the App does not cancel your subscription."),
                .subtitle("4.5 Free tier and Premium features"),
                .paragraph("The free version of Bindr includes usage limits (for example on collection size, scans, binders, decks, wishlist items, and certain social actions). Premium removes or raises those limits and may unlock additional features. Feature availability may change as the App evolves."),
                .subtitle("4.6 Refunds"),
                .paragraph("Refund requests are handled by Apple under Apple's refund policies. Contact Apple Support or visit reportaproblem.apple.com."),
                .subtitle("4.7 Restore purchases"),
                .paragraph("If you reinstall Bindr or use a new device, you can restore an active Premium subscription using Restore Purchases in the App, signed in with the same Apple ID used for the original purchase."),
                .subtitle("4.8 Free trial"),
                .paragraph("We may offer a free trial for new subscribers who have not previously used an introductory offer in the Bindr Premium subscription group. Unless you cancel at least 24 hours before the trial ends, your Apple ID will be charged the subscription price shown for the plan you selected.")
            ]
        ),
        LegalPolicySection(
            title: "5. Acceptable use",
            blocks: [
                .paragraph("You agree not to:"),
                .bullets([
                    "Use Bindr for unlawful, harmful, fraudulent, or abusive purposes",
                    "Harass, threaten, defame, or violate the rights of others",
                    "Upload or share content you do not have the right to share",
                    "Attempt to reverse engineer, scrape, overload, or disrupt the App or services",
                    "Circumvent subscription, usage limits, or security measures",
                    "Use automated systems to access the service without permission",
                    "Misrepresent card authenticity, ownership, condition, or trade terms"
                ]),
                .paragraph("We may suspend or terminate access if you violate these Terms or if necessary to protect users or the service.")
            ]
        ),
        LegalPolicySection(
            title: "6. User content and social features",
            blocks: [
                .paragraph("You retain ownership of content you submit, such as posts, comments, profile information, and shared binders or decks. You grant us a non-exclusive, worldwide, royalty-free licence to host, store, display, and distribute that content solely to operate and improve Bindr and provide the features you choose to use."),
                .paragraph("You are solely responsible for your content and interactions with other users. We do not guarantee the accuracy, safety, or legality of user-generated content or real-world trades arranged through or outside the App.")
            ]
        ),
        LegalPolicySection(
            title: "7. Intellectual property",
            blocks: [
                .paragraph("Bindr’s app design, code, branding, and original content are owned by us or our licensors. Pokémon names, card artwork, set names, logos, and related materials belong to their respective owners and are referenced in the App only for identification and personal collection purposes."),
                .paragraph("You may not copy, modify, distribute, sell, or lease any part of the App except as allowed by law or with our written permission.")
            ]
        ),
        LegalPolicySection(
            title: "8. Scanner, catalogue, and pricing information",
            blocks: [
                .paragraph("Scanner matches, catalogue entries, variants, legality information, release data, and market prices are provided for general informational purposes only. They may be incomplete, delayed, or incorrect."),
                .paragraph("Prices, charts, totals, and estimates are not financial, investment, tax, insurance, or professional appraisal advice. Always verify physical cards and trusted official sources before relying on App information for buying, selling, trading, or grading decisions.")
            ]
        ),
        LegalPolicySection(
            title: "9. Trades and offline transactions",
            blocks: [
                .paragraph("Trade calculators, trade records, friend trades, and related tools are convenience features only. We do not verify card authenticity, ownership, condition, delivery, payment, or whether a trade is completed outside the App. You are solely responsible for evaluating and completing any trade.")
            ]
        ),
        LegalPolicySection(
            title: "10. Availability and changes",
            blocks: [
                .paragraph("We may modify, suspend, or discontinue any part of Bindr at any time, including features, catalogue data, pricing sources, free-tier limits, or Premium benefits. We aim to provide reliable service but do not guarantee uninterrupted or error-free operation.")
            ]
        ),
        LegalPolicySection(
            title: "11. Disclaimer of warranties",
            blocks: [
                .paragraph("To the fullest extent permitted by law, Bindr and all related services are provided “as is” and “as available” without warranties of any kind, whether express or implied, including implied warranties of merchantability, fitness for a particular purpose, and non-infringement.")
            ]
        ),
        LegalPolicySection(
            title: "12. Limitation of liability",
            blocks: [
                .paragraph("To the fullest extent permitted by law, we are not liable for indirect, incidental, special, consequential, or punitive damages, or for loss of profits, data, goodwill, or collection value, arising from your use of Bindr."),
                .paragraph("Our total liability for any claim relating to Bindr will not exceed the greater of (a) the amount you paid us in the 12 months before the claim, or (b) GBP £10, except where liability cannot be excluded under applicable law."),
                .paragraph("Nothing in these Terms limits liability for death or personal injury caused by negligence, fraud, or any other liability that cannot be limited by law.")
            ]
        ),
        LegalPolicySection(
            title: "13. Indemnity",
            blocks: [
                .paragraph("You agree to indemnify and hold us harmless from claims, losses, and expenses arising from your use of Bindr, your content, your interactions with other users, or your violation of these Terms or applicable law, except to the extent caused by our negligence or wilful misconduct.")
            ]
        ),
        LegalPolicySection(
            title: "14. Third-party services",
            blocks: [
                .paragraph("Bindr may link to or reference third-party websites, marketplaces, or services. We are not responsible for third-party content, policies, or practices. Your use of Apple or Google sign-in services is subject to those providers’ terms and privacy policies.")
            ]
        ),
        LegalPolicySection(
            title: "15. Termination",
            blocks: [
                .paragraph("You may stop using Bindr at any time. We may suspend or terminate your access if you breach these Terms or if necessary for legal, security, or operational reasons. Sections that by nature should survive termination will continue to apply.")
            ]
        ),
        LegalPolicySection(
            title: "16. Governing law",
            blocks: [
                .paragraph("These Terms are governed by the laws of England and Wales, without regard to conflict-of-law rules. If you are a consumer in the UK or EEA, you may also benefit from mandatory protections of your country of residence."),
                .contact(Self.contactEmail, context: "Disputes should first be raised with us at")
            ]
        ),
        LegalPolicySection(
            title: "17. Changes to these Terms",
            blocks: [
                .paragraph("We may update these Terms from time to time. The updated version will be posted at bindr-tcg.com/terms with a revised “Last updated” date. Continued use of Bindr after changes become effective constitutes acceptance of the updated Terms where permitted by law.")
            ]
        ),
        LegalPolicySection(
            title: "18. Contact",
            blocks: [
                .contact(Self.contactEmail, context: "Questions about these Terms or Bindr Premium:")
            ]
        )
    ]

    var body: some View {
        LegalPolicyDocumentView(
            navigationTitle: "Terms of Service",
            headerTitle: "Terms of Service",
            headerIcon: "doc.text.fill",
            lastUpdated: "21 June 2026",
            webURL: Self.webURL,
            webPathLabel: "bindr-tcg.com/terms",
            introParagraphs: [
                "These Terms of Service (“Terms”) govern your use of the Bindr mobile application (“App”) and related services operated by App1xy (“we”, “us”, “our”).",
                "By downloading, accessing, or using Bindr, you agree to these Terms and our Privacy Policy. If you do not agree, do not use the App."
            ],
            sections: sections,
            contactEmail: Self.contactEmail
        )
    }
}

#Preview {
    NavigationStack {
        TermsOfServiceView()
    }
}
