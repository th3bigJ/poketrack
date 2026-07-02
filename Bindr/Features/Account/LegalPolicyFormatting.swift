import SwiftUI

struct LegalPolicySection: Identifiable {
    let title: String
    let blocks: [LegalPolicyBlock]

    var id: String { title }
}

enum LegalPolicyBlock {
    case paragraph(String)
    case subtitle(String)
    case bullets([String])
    case labeledLines([(String, String)])
    case contact(String, context: String)
}

struct LegalPolicyDocumentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var bindrAccent
    @Environment(\.openURL) private var openURL

    let navigationTitle: String
    let headerTitle: String
    let headerIcon: String
    let lastUpdated: String
    let webURL: URL
    let webPathLabel: String
    let introParagraphs: [String]
    let sections: [LegalPolicySection]
    let contactEmail: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                webLinkCard
                    .padding(.top, BindrSpacing.lg)
                intro
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
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.sm) {
            HStack(spacing: 10) {
                Image(systemName: headerIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(bindrAccent)
                    .frame(width: 34, height: 34)
                    .background(bindrAccent.opacity(0.14), in: Circle())

                Text(headerTitle)
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(.primary)
            }

            Text("Last updated: \(lastUpdated)")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var webLinkCard: some View {
        Button {
            openURL(webURL)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "safari")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(bindrAccent)
                    .frame(width: 32, height: 32)
                    .background(bindrAccent.opacity(colorScheme == .dark ? 0.18 : 0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("View online")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(webPathLabel)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the document in Safari")
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.sm) {
            ForEach(Array(introParagraphs.enumerated()), id: \.offset) { index, paragraph in
                Text(paragraph)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .foregroundStyle(introForegroundStyle(for: index))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func introForegroundStyle(for index: Int) -> Color {
        index == 0 ? .primary.opacity(0.9) : .secondary
    }

    private var sectionList: some View {
        VStack(spacing: BindrSpacing.xl) {
            ForEach(sections) { section in
                policySection(section)
            }
        }
    }

    private func policySection(_ section: LegalPolicySection) -> some View {
        VStack(alignment: .leading, spacing: BindrSpacing.sm) {
            Text(section.title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: BindrSpacing.sm) {
                ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: LegalPolicyBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        case .subtitle(let text):
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.92))
                .padding(.top, 2)

        case .bullets(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    policyBulletRow(item)
                }
            }

        case .labeledLines(let lines):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines, id: \.0) { label, value in
                    if value == contactEmail {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(label):")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary.opacity(0.9))
                            emailLink
                        }
                    } else {
                        Text("\(label): \(value)")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
            }

        case .contact(_, let context):
            VStack(alignment: .leading, spacing: 4) {
                Text(context)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                emailLink
            }
        }
    }

    private func policyBulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("•")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.top, 1)

            Text(text)
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emailLink: some View {
        Link(contactEmail, destination: URL(string: "mailto:\(contactEmail)")!)
            .font(.system(size: 14, weight: .semibold))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.xs) {
            Text("Online version")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.7)
                .textCase(.uppercase)
                .foregroundStyle(.secondary.opacity(0.75))

            Link(webURL.absoluteString, destination: webURL)
                .font(.system(size: 13, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
