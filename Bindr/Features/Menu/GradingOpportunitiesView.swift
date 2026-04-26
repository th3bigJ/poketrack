import SwiftData
import SwiftUI

struct GradingOpportunitiesView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentCard) private var presentCard

    @Query(sort: \CollectionItem.dateAcquired, order: .reverse) private var collectionItems: [CollectionItem]

    @State private var opportunities: [GradingOpportunity] = []
    @State private var selectedTab: GradingTab = .psa
    @State private var isLoading = false

    private var activeBrand: TCGBrand { services.brandSettings.selectedCatalogBrand }

    private var eligibleItems: [CollectionItem] {
        collectionItems.filter { item in
            guard item.quantity > 0 else { return false }
            guard item.itemKind == ProductKind.singleCard.rawValue else { return false }
            guard TCGBrand.inferredFromMasterCardId(item.cardID) == activeBrand else { return false }
            return isRaw(item)
        }
    }

    private var taskKey: String {
        let ids = eligibleItems
            .map { "\($0.cardID)|\($0.variantKey)|\($0.quantity)|\($0.gradingCompany ?? "")|\($0.grade ?? "")" }
            .joined(separator: "§")
        return "\(activeBrand.rawValue)#\(ids)"
    }

    private var displayedOpportunities: [DisplayedOpportunity] {
        opportunities.compactMap { item in
            let gradedPrice: Double?
            let gradeLabel: String
            switch selectedTab {
            case .psa:
                gradedPrice = item.psa10USD
                gradeLabel = "PSA 10"
            case .ace:
                gradedPrice = item.ace10USD
                gradeLabel = "ACE 10"
            }

            guard let gradedPrice else { return nil }
            let profitPerCard = gradedPrice - item.rawUSD
            guard profitPerCard > 0 else { return nil }

            return DisplayedOpportunity(
                id: item.id,
                card: item.card,
                variantKey: item.variantKey,
                quantity: item.quantity,
                rawUSD: item.rawUSD,
                gradedUSD: gradedPrice,
                gradeLabel: gradeLabel,
                profitPerCardUSD: profitPerCard,
                totalProfitUSD: profitPerCard * Double(item.quantity)
            )
        }
        .sorted {
            if abs($0.profitPerCardUSD - $1.profitPerCardUSD) > 0.0001 {
                return $0.profitPerCardUSD > $1.profitPerCardUSD
            }
            if abs($0.totalProfitUSD - $1.totalProfitUSD) > 0.0001 {
                return $0.totalProfitUSD > $1.totalProfitUSD
            }
            return $0.card.cardName.localizedCaseInsensitiveCompare($1.card.cardName) == .orderedAscending
        }
    }

    private var displayedCards: [Card] {
        displayedOpportunities.map(\.card)
    }

    private var safeColumnCount: Int {
        min(max(gradingGridOptions.columnCount, 1), 4)
    }

    private var gradingGridOptions: BrowseGridOptions {
        var options = services.browseGridOptions.options
        options.showSetName = true
        options.showSetID = false
        options.showPricing = true
        options.showOwned = false
        return options
    }

    var body: some View {
        Group {
            if collectionItems.isEmpty {
                emptyState(
                    title: "No collection yet",
                    image: "square.stack.3d.up.slash",
                    description: "Add cards to your collection first, then this page can spot grading upside."
                )
            } else if eligibleItems.isEmpty {
                emptyState(
                    title: "No raw cards to grade",
                    image: "checklist.unchecked",
                    description: "This checks raw single cards in your active game. Switch game from More → Settings to view another collection."
                )
            } else if isLoading && opportunities.isEmpty {
                ProgressView("Scanning grading opportunities…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            header
        }
        .task(id: taskKey) {
            await refreshOpportunities()
        }
    }

    private var header: some View {
        ZStack {
            Text("Grading Opportunities")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)

            HStack {
                ChromeGlassCircleButton(accessibilityLabel: "Back") {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 12) {
                SlidingSegmentedPicker(
                    selection: $selectedTab,
                    items: GradingTab.allCases,
                    title: { $0.title }
                )
                .padding(.horizontal, 16)

                if displayedOpportunities.isEmpty {
                    ContentUnavailableView(
                        "No \(selectedTab.title) opportunities",
                        systemImage: "chart.line.downtrend.xyaxis",
                        description: Text("No cards in your raw collection currently show profit for \(selectedTab.gradeLabel).")
                    )
                    .frame(minHeight: 280)
                    .padding(.horizontal, 16)
                } else {
                    EagerVGrid(items: displayedOpportunities, columns: safeColumnCount, spacing: 12) { item in
                        Button {
                            presentCard(item.card, displayedCards)
                        } label: {
                            CardGridCell(
                                card: item.card,
                                gridOptions: gradingGridOptions,
                                setName: setName(for: item.card),
                                postPriceFootnote: footnote(for: item),
                                overridePrice: item.gradedUSD,
                                gradeLabel: item.gradeLabel
                            )
                        }
                        .buttonStyle(CardCellButtonStyle())
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            .padding(.top, 8)
        }
    }

    private func setName(for card: Card) -> String? {
        services.cardData.sets.first(where: { $0.setCode == card.setCode })?.name
    }

    private func footnote(for item: DisplayedOpportunity) -> String {
        "Upside - +\(format(amountUSD: item.profitPerCardUSD))"
    }

    private func refreshOpportunities() async {
        isLoading = true
        defer { isLoading = false }

        let grouped = Dictionary(grouping: eligibleItems) { item in
            let variant = normalizedVariantKey(item.variantKey)
            return "\(item.cardID)|\(variant)"
        }

        var next: [GradingOpportunity] = []
        next.reserveCapacity(grouped.count)

        for (_, groupedItems) in grouped {
            guard let sample = groupedItems.first else { continue }
            let variant = normalizedVariantKey(sample.variantKey)
            let quantity = groupedItems.reduce(0) { $0 + max(0, $1.quantity) }
            guard quantity > 0 else { continue }
            guard let card = await services.cardData.loadCard(masterCardId: sample.cardID) else { continue }

            guard let raw = await services.pricing.usdPriceForVariantAndGrade(
                for: card,
                variantKey: variant,
                grade: "raw"
            ), raw > 0 else { continue }

            let psa10 = await services.pricing.usdPriceForVariantAndGrade(
                for: card,
                variantKey: variant,
                grade: "psa10"
            )
            let ace10 = await services.pricing.usdPriceForVariantAndGrade(
                for: card,
                variantKey: variant,
                grade: "ace10"
            )

            let hasAnyProfit = (psa10 ?? 0) > raw || (ace10 ?? 0) > raw
            guard hasAnyProfit else { continue }

            next.append(
                GradingOpportunity(
                    id: "\(card.masterCardId)|\(variant)",
                    card: card,
                    variantKey: variant,
                    quantity: quantity,
                    rawUSD: raw,
                    psa10USD: psa10,
                    ace10USD: ace10
                )
            )
        }

        opportunities = next
    }

    private func format(amountUSD: Double) -> String {
        services.priceDisplay.currency.format(
            amountUSD: amountUSD,
            usdToGbp: services.pricing.usdToGbp
        )
    }

    private func normalizedVariantKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "normal" : trimmed
    }

    private func isRaw(_ item: CollectionItem) -> Bool {
        let company = item.gradingCompany?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let grade = item.grade?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return company.isEmpty && grade.isEmpty
    }

    private func emptyState(title: String, image: String, description: String) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                ContentUnavailableView(
                    title,
                    systemImage: image,
                    description: Text(description)
                )
                .frame(minHeight: 280)
            }
            .padding(.top, 16)
        }
    }
}

private enum GradingTab: String, CaseIterable, Identifiable {
    case psa
    case ace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .psa: return "PSA"
        case .ace: return "ACE"
        }
    }

    var gradeLabel: String {
        switch self {
        case .psa: return "PSA 10"
        case .ace: return "ACE 10"
        }
    }
}

private struct GradingOpportunity: Identifiable {
    let id: String
    let card: Card
    let variantKey: String
    let quantity: Int
    let rawUSD: Double
    let psa10USD: Double?
    let ace10USD: Double?
}

private struct DisplayedOpportunity: Identifiable {
    let id: String
    let card: Card
    let variantKey: String
    let quantity: Int
    let rawUSD: Double
    let gradedUSD: Double
    let gradeLabel: String
    let profitPerCardUSD: Double
    let totalProfitUSD: Double
}
