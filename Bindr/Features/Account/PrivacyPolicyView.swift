import SwiftUI

struct PrivacyPolicyView: View {
    private static let webURL = URL(string: "https://www.bindr-tcg.com/privacy")!
    private static let contactEmail = "info@bindr-tcg.com"

    private let sections: [LegalPolicySection] = [
        LegalPolicySection(
            title: "1. Who we are",
            blocks: [
                .paragraph("Bindr is an independent Pokémon TCG collection, scanner, pricing, and social app. Bindr is not affiliated with, endorsed by, or sponsored by The Pokémon Company International, Nintendo, Creatures Inc., GAME FREAK, or any marketplace or grading company."),
                .labeledLines([
                    ("Data controller", "App1xy"),
                    ("Contact", Self.contactEmail)
                ])
            ]
        ),
        LegalPolicySection(
            title: "2. Summary",
            blocks: [
                .bullets([
                    "Most of your collection data stays on your device unless you sign in and use cloud backup or social features.",
                    "Sign in with Apple or Google is optional and used for social features and cloud backup — not required for Bindr Premium.",
                    "Subscriptions are processed by Apple. We do not receive your payment card details.",
                    "We do not sell your personal information.",
                    "You can delete your account and associated server data in the App."
                ])
            ]
        ),
        LegalPolicySection(
            title: "3. Information we collect",
            blocks: [
                .subtitle("3.1 Information you provide"),
                .bullets([
                    "Account information — If you sign in with Apple or Google, we receive an account identifier and may receive your name and email address depending on what the provider shares. You may also create an account with email and password.",
                    "Profile information — Display name, username, bio, avatar, and social privacy preferences you choose to set.",
                    "Collection data — Cards, quantities, variants, binders, decks, wishlists, trades, transactions, notes, and related library records you enter or import.",
                    "Social content — Posts, comments, shared binders/decks/wishlists, friend connections, trade offers, and other content you publish or send through social features.",
                    "Support communications — Information you send when contacting us."
                ]),
                .subtitle("3.2 Information collected automatically"),
                .bullets([
                    "Device and app data — Device type, operating system version, app version, language/region settings, and basic diagnostic information needed to operate the App.",
                    "Push notification token — If you enable notifications and are signed in, we store an Apple Push Notification service (APNs) device token so we can send alerts such as social activity or trade-related notifications.",
                    "Subscription status — Apple provides entitlement information so we can unlock Bindr Premium features. We do not receive your full payment details.",
                    "Catalog and pricing downloads — The App downloads public card catalogue, image, and market-pricing files from our content delivery network. These requests do not include your collection contents unless you are signed in and back up or share data as described below."
                ]),
                .subtitle("3.3 Camera and scanner data"),
                .paragraph("If you use the card scanner or QR features, Bindr accesses your device camera with your permission. Images are processed on your device to identify cards and perform matching. We do not use the camera for unrelated purposes. Scanner images are not uploaded as a separate photo gallery unless a feature explicitly requires sending content you choose to share."),
                .subtitle("3.4 Information we do not collect"),
                .bullets([
                    "We do not request precise location data.",
                    "We do not knowingly collect information from children under 13.",
                    "We do not use third-party advertising analytics SDKs in the App."
                ])
            ]
        ),
        LegalPolicySection(
            title: "4. How we use information",
            blocks: [
                .paragraph("We use information to:"),
                .bullets([
                    "Provide core App features such as collection tracking, binders, decks, wishlists, scanning, pricing views, and offline catalogue access.",
                    "Authenticate your account and maintain your session.",
                    "Back up and restore your library when you are signed in.",
                    "Enable optional social features such as profiles, friends, sharing, posts, and trades.",
                    "Deliver push notifications you have allowed.",
                    "Verify and manage Bindr Premium subscriptions.",
                    "Improve reliability, security, and performance of the App and services.",
                    "Respond to support requests and enforce our Terms of Service.",
                    "Comply with legal obligations."
                ])
            ]
        ),
        LegalPolicySection(
            title: "5. Legal bases (EEA/UK users)",
            blocks: [
                .paragraph("If you are in the European Economic Area or United Kingdom, we process personal data on these bases:"),
                .bullets([
                    "Contract — To provide the App, account, backup, social, and subscription features you request.",
                    "Legitimate interests — To secure and improve the service, prevent abuse, and support users, balanced against your rights.",
                    "Consent — For optional permissions such as notifications and camera access, and where required for certain processing.",
                    "Legal obligation — Where we must retain or disclose information under applicable law."
                ])
            ]
        ),
        LegalPolicySection(
            title: "6. Where data is stored and processed",
            blocks: [
                .bullets([
                    "On your device — Collection, binders, decks, wishlists, and related records are stored locally using on-device storage.",
                    "Cloud backup — If you are signed in, an encrypted backup snapshot of your library may be uploaded to our cloud storage so you can restore it and so permitted social/trade features can function.",
                    "Social and account services — Account, profile, social graph, posts, comments, shared content metadata, notification preferences, and device tokens are stored using Supabase-hosted infrastructure.",
                    "Content delivery — Public catalogue, images, and pricing files are served from Cloudflare R2 and related infrastructure.",
                    "Apple services — Sign in with Apple, App Store subscriptions, and push delivery are handled by Apple under Apple’s own policies.",
                    "Google services — If you choose Sign in with Google, authentication is handled by Google under Google’s own terms and privacy policy."
                ]),
                .paragraph("Service providers may process data in countries other than your own. Where required, we use appropriate safeguards for international transfers.")
            ]
        ),
        LegalPolicySection(
            title: "7. Sharing of information",
            blocks: [
                .paragraph("We may share information with:"),
                .bullets([
                    "Service providers — Hosting, authentication, database, storage, and notification providers that help us operate Bindr, subject to confidentiality and security obligations.",
                    "Other users — Content you choose to make visible through social features, sharing settings, public profiles, posts, or shared binders/decks/wishlists.",
                    "Apple — For Sign in with Apple, in-app purchases, and push notification delivery.",
                    "Google — If you choose Sign in with Google, for authentication and account identity as permitted by your Google account settings.",
                    "Legal and safety — When required by law, court order, or to protect users, our rights, or the security of the service.",
                    "Business transfers — If ownership of Bindr changes, data may transfer as part of that transaction with notice where required."
                ]),
                .paragraph("We do not sell your personal information.")
            ]
        ),
        LegalPolicySection(
            title: "8. Your choices and controls",
            blocks: [
                .bullets([
                    "Optional sign-in — You can use many App features without creating an account. Social and cloud backup require sign-in.",
                    "Social sharing toggles — In Account & Privacy, you can control whether wishlist, collection, binders, and decks are eligible for social sharing.",
                    "Notifications — You can enable or disable notifications in iOS Settings and within the App where available.",
                    "Camera — You can deny camera permission; scanning and QR features will not work without it.",
                    "Offline mode — You can enable or disable offline catalogue/image downloads in Settings.",
                    "Subscriptions — Manage or cancel Bindr Premium in iOS Settings → Apple ID → Subscriptions. If you start a free trial, cancel before it ends to avoid being charged for the plan you selected."
                ])
            ]
        ),
        LegalPolicySection(
            title: "9. Data retention",
            blocks: [
                .bullets([
                    "Local library data remains on your device until you delete it, uninstall the App, or use account deletion.",
                    "Cloud backup and social data are retained while your account is active and as needed to provide the service.",
                    "When you delete your account in the App, we delete your Bindr account and associated server-side data, including cloud backup, subject to reasonable backup retention and legal requirements.",
                    "We may retain limited information where necessary for security, fraud prevention, accounting, or legal compliance."
                ])
            ]
        ),
        LegalPolicySection(
            title: "10. Account and data deletion",
            blocks: [
                .paragraph("Signed-in users can delete their account in the App: More → Account & Privacy → Delete Account and Data."),
                .paragraph("This permanently deletes your Bindr account, social profile, posts, comments, trades, friendships, cloud backup, and local library data on that device. Deletion cannot be undone."),
                .contact(Self.contactEmail, context: "To request deletion or export help by email, contact")
            ]
        ),
        LegalPolicySection(
            title: "11. Security",
            blocks: [
                .paragraph("We use reasonable technical and organisational measures to protect information, including encrypted transport (HTTPS), access controls, and authenticated API access. No method of transmission or storage is completely secure.")
            ]
        ),
        LegalPolicySection(
            title: "12. Children’s privacy",
            blocks: [
                .paragraph("Bindr is not directed to children under 13, and we do not knowingly collect personal information from children under 13. If you believe a child has provided us personal information, contact us and we will take appropriate steps to delete it.")
            ]
        ),
        LegalPolicySection(
            title: "13. Your rights",
            blocks: [
                .paragraph("Depending on where you live, you may have rights to:"),
                .bullets([
                    "Access a copy of your personal information",
                    "Correct inaccurate information",
                    "Delete your information",
                    "Restrict or object to certain processing",
                    "Data portability",
                    "Withdraw consent where processing is based on consent",
                    "Lodge a complaint with your local data protection authority"
                ]),
                .contact(Self.contactEmail, context: "To exercise these rights, email")
            ]
        ),
        LegalPolicySection(
            title: "14. Changes to this policy",
            blocks: [
                .paragraph("We may update this Privacy Policy from time to time. We will post the updated version at bindr-tcg.com/privacy and change the “Last updated” date. Material changes may also be communicated in the App where appropriate.")
            ]
        ),
        LegalPolicySection(
            title: "15. Contact",
            blocks: [
                .contact(Self.contactEmail, context: "Questions about this Privacy Policy or our data practices:")
            ]
        )
    ]

    var body: some View {
        LegalPolicyDocumentView(
            navigationTitle: "Privacy Policy",
            headerTitle: "Privacy Policy",
            headerIcon: "hand.raised.fill",
            lastUpdated: "21 June 2026",
            webURL: Self.webURL,
            webPathLabel: "bindr-tcg.com/privacy",
            introParagraphs: [
                "This Privacy Policy explains how App1xy (“we”, “us”, “our”) collects, uses, stores, and shares information when you use the Bindr mobile application (“App”) and related online services.",
                "By using Bindr, you agree to this Privacy Policy. If you do not agree, please do not use the App."
            ],
            sections: sections,
            contactEmail: Self.contactEmail
        )
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
