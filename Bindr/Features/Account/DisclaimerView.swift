import SwiftUI

struct DisclaimerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var bindrAccent

    private let sections: [LegalDisclaimerSection] = [
        LegalDisclaimerSection(
            icon: "person.crop.circle.badge.xmark",
            title: "Independent app",
            body: "Bindr is an independent Pokemon card scanning, pricing, trading, social and collection management app. Bindr is not affiliated with, endorsed by, sponsored by, approved by, or officially connected with The Pokemon Company International, Nintendo, Creatures Inc., GAME FREAK, any of their subsidiaries or affiliates, or any marketplace, grading company, tournament organiser, retailer or platform unless expressly stated in the app."
        ),
        LegalDisclaimerSection(
            icon: "seal",
            title: "Trademarks and card content",
            body: "All Pokemon card names, set names, game names, character names, artwork, logos, trade dress, symbols and related terminology are the property of their respective owners. References to those materials are used only to identify cards, show collection context, support search, scanner matching, wishlists, deck building, trading, price reference and personal record keeping. Bindr does not claim ownership of third-party intellectual property."
        ),
        LegalDisclaimerSection(
            icon: "camera.viewfinder",
            title: "Scans and catalogue data",
            body: "Scanner results, catalogue details, variants, legality information, release information and collection matches may be incomplete, delayed or incorrect. Users should check the physical card and trusted official sources before relying on a match, variant, set, rarity, language, condition, legality or product detail."
        ),
        LegalDisclaimerSection(
            icon: "chart.line.uptrend.xyaxis",
            title: "Prices and values",
            body: "Prices, totals, charts, currencies, averages and market estimates are provided for general informational purposes only. They are not financial, investment, tax, insurance, appraisal or professional advice. Bindr does not guarantee availability, sale prices, exchange rates, condition adjustments, liquidity, profit, loss, or the accuracy, timeliness or completeness of any price data."
        ),
        LegalDisclaimerSection(
            icon: "arrow.left.arrow.right",
            title: "Trades and collection changes",
            body: "Trade tools, trade calculators, plus and minus card adjustments, friend trades and manual records are convenience features only. Users are responsible for deciding whether a trade is fair, safe, permitted and accurately recorded. Bindr does not verify card authenticity, ownership, condition, delivery, payment, user identity or whether a trade is completed outside the app."
        ),
        LegalDisclaimerSection(
            icon: "person.2",
            title: "Social features",
            body: "Profiles, posts, comments, shared binders, shared decks, wishlists, trade offers and other user-submitted content are created by users. Users are responsible for what they share and for respecting the rights, privacy and safety of others. Bindr may remove, restrict or report content or accounts where needed to protect users, comply with platform rules, or meet legal obligations."
        ),
        LegalDisclaimerSection(
            icon: "lock.shield",
            title: "Data and availability",
            body: "Bindr aims to protect user data and keep services available, but no app or online service can be guaranteed to be uninterrupted, error-free, fully secure or permanently available. Users should keep their own backups of important records and review the app privacy information for details about data collection, use, retention and deletion."
        ),
        LegalDisclaimerSection(
            icon: "exclamationmark.triangle",
            title: "No warranties",
            body: "To the fullest extent permitted by law, Bindr is provided as is and as available, without warranties of any kind. Bindr is not liable for losses, disputes, missed trades, incorrect collection counts, inaccurate scans, pricing errors, data loss, service interruptions, third-party actions, or decisions made using information shown in the app."
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                quickRead
                    .padding(.top, BindrSpacing.xl)
                sectionList
                    .padding(.top, BindrSpacing.xl)
                footer
                    .padding(.top, BindrSpacing.xl)
            }
            .padding(.horizontal, BindrSpacing.lg)
            .padding(.top, BindrSpacing.lg)
            .padding(.bottom, BindrSpacing.xxxl)
        }
        .scrollContentBackground(.hidden)
        .bindrPageBackground()
        .navigationTitle("Legal Disclaimer")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.sm) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(bindrAccent)
                    .frame(width: 34, height: 34)
                    .background(bindrAccent.opacity(0.14), in: Circle())

                Text("Legal Disclaimer")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(.primary)
            }

            Text("How Bindr handles Pokemon card data, prices, scans, social features and trades.")
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickRead: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.sm) {
            Text("At a glance")
                .font(.system(size: 12, weight: .bold))
                .tracking(0.7)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                legalSummaryRow("Independent from The Pokemon Company, Nintendo and marketplaces.")
                legalSummaryRow("Card images, names, logos and brands remain owned by their rights holders.")
                legalSummaryRow("Prices, scans and trade calculations are helpful references, not guarantees.")
                legalSummaryRow("You are responsible for manual collection edits and real-world trades.")
            }
        }
    }

    private var sectionList: some View {
        VStack(spacing: 0) {
            ForEach(sections) { section in
                legalSection(section)
                if section.id != sections.last?.id {
                    Divider()
                        .overlay(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08))
                        .padding(.leading, 44)
                }
            }
        }
    }

    private func legalSummaryRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BindrPalette.ownedGreen)
                .padding(.top, 2)

            Text(text)
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(.primary.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func legalSection(_ section: LegalDisclaimerSection) -> some View {
        HStack(alignment: .top, spacing: BindrSpacing.md) {
            Image(systemName: section.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(section.tint)
                .frame(width: 30, height: 30)
                .background(section.tint.opacity(colorScheme == .dark ? 0.18 : 0.12), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(section.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)

                Text(section.body)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, BindrSpacing.md)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.xs) {
            Text("Last reviewed")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.7)
                .textCase(.uppercase)
                .foregroundStyle(.secondary.opacity(0.75))

            Text("June 2026")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LegalDisclaimerSection: Identifiable {
    let icon: String
    let title: String
    let body: String

    var id: String { title }

    var tint: Color {
        switch title {
        case "Independent app": return BindrPalette.binderGold
        case "Trademarks and card content": return BindrPalette.deckBlue
        case "Scans and catalogue data": return BindrPalette.wishlistViolet
        case "Prices and values": return BindrPalette.ownedGreen
        case "Trades and collection changes": return BindrPalette.binderGold
        case "Social features": return BindrPalette.deckBlue
        case "Data and availability": return BindrPalette.wishlistViolet
        default: return BindrPalette.alertRed
        }
    }
}

#Preview {
    NavigationStack {
        DisclaimerView()
    }
}
