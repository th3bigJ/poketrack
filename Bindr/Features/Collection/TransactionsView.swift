import SwiftData
import SwiftUI

struct TransactionsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Query private var collectionItems: [CollectionItem]
    @Query(sort: \LedgerLine.occurredAt, order: .reverse) private var ledgerLines: [LedgerLine]

    @State private var cardNamesByID: [String: String] = [:]
    @State private var cardImageURLsByID: [String: URL] = [:]
    @State private var showAddActivity = false
    @State private var editingLedgerLine: LedgerLine?
    @State private var pnlRange: ActivityPnLRange = .month
    @State private var holdingsCollectionValue: Double = 0
    @State private var loadedTransactionCount: Int = 50
    @State private var transactionSearchText: String = ""

    private var activeBrand: TCGBrand { services.brandSettings.selectedCatalogBrand }

    private var visibleLedgerLines: [LedgerLine] {
        ledgerLines.filter { line in
            // Manual activity rows (for example "Other") may not have a card id.
            // Keep those visible instead of dropping them in brand filtering.
            guard let cid = line.cardID?.trimmingCharacters(in: .whitespacesAndNewlines), !cid.isEmpty else {
                return true
            }
            return TCGBrand.inferredFromMasterCardId(cid) == activeBrand
        }
    }

    private var ledgerSignature: String {
        let brandKey = activeBrand.rawValue
        return visibleLedgerLines.map { "\($0.id.uuidString)|\($0.occurredAt.timeIntervalSince1970)" }.joined(separator: "§") + "|" + brandKey
    }

    private var holdingsSignature: String {
        let brandKey = activeBrand.rawValue
        let currencyKey = services.priceDisplay.currency.rawValue
        let itemKey = visibleCollectionItems
            .map { "\($0.cardID)|\($0.variantKey)|\($0.quantity)|\($0.itemKind)|\($0.gradingCompany ?? "")" }
            .joined(separator: "§")
        return "\(brandKey)|\(currencyKey)|\(itemKey)"
    }

    private var rangeFilteredLines: [LedgerLine] {
        let cal = Calendar.current
        let now = Date()
        return visibleLedgerLines.filter { line in
            switch pnlRange {
            case .month:
                return cal.isDate(line.occurredAt, equalTo: now, toGranularity: .month)
            case .year:
                return cal.isDate(line.occurredAt, equalTo: now, toGranularity: .year)
            case .allTime:
                return true
            }
        }
    }

    private var filteredLedgerLines: [LedgerLine] {
        let query = transactionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return visibleLedgerLines }
        let normalizedQuery = query.lowercased()
        return visibleLedgerLines.filter { line in
            searchableText(for: line).localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    private var displayedLedgerLines: [LedgerLine] {
        Array(filteredLedgerLines.prefix(loadedTransactionCount))
    }

    private var hasMoreTransactions: Bool {
        displayedLedgerLines.count < filteredLedgerLines.count
    }

    private var boughtTotal: Double {
        rangeFilteredLines.reduce(0) { partial, line in
            guard LedgerDirection(rawValue: line.direction) == .bought, let unitPrice = line.unitPrice else { return partial }
            return partial + (unitPrice * Double(line.quantity))
        }
    }

    private var soldTotal: Double {
        rangeFilteredLines.reduce(0) { partial, line in
            guard LedgerDirection(rawValue: line.direction) == .sold, let unitPrice = line.unitPrice else { return partial }
            return partial + (unitPrice * Double(line.quantity))
        }
    }

    private var visibleCollectionItems: [CollectionItem] {
        collectionItems.filter { item in
            TCGBrand.inferredFromMasterCardId(item.cardID) == activeBrand
        }
    }

    private var collectionValue: Double {
        holdingsCollectionValue
    }

    private var profitValue: Double {
        collectionValue + soldTotal - boughtTotal
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if ledgerLines.isEmpty {
                    emptyState
                } else if visibleLedgerLines.isEmpty {
                    hiddenByBrandEmptyState
                } else {
                    transactionList
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            transactionsHeader
        }
        .task(id: ledgerSignature) {
            await resolveCardNames()
        }
        .task(id: holdingsSignature) {
            await computeHoldingsCollectionValue()
        }
        .onAppear {
            services.setupCollectionLedger(modelContext: modelContext)
            services.sealedProducts.loadFromLocalIfAvailable()
        }
        .onChange(of: activeBrand) { _, _ in
            loadedTransactionCount = 50
        }
        .sheet(isPresented: $showAddActivity) {
            AddManualActivityView()
        }
        .sheet(item: $editingLedgerLine) { line in
            AddManualActivityView(ledgerLineToEdit: line)
        }
    }

    private var transactionsHeader: some View {
        ZStack {
            Text("Activity")
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

                ChromeGlassCircleButton(accessibilityLabel: "Add activity") {
                    showAddActivity = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                ContentUnavailableView(
                    "No transactions yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Add cards to your collection and the ledger will appear here.")
                )
                .frame(minHeight: 280)
            }
            .padding(.top, 16)
        }
    }

    private var hiddenByBrandEmptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                ContentUnavailableView(
                    "No \(activeBrand.displayTitle) transactions",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Transactions only appear for the active game selected in More.")
                )
                .frame(minHeight: 280)
            }
            .padding(.top, 16)
        }
    }

    private var transactionList: some View {
        List {
            pnlSummaryCard
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 10, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            transactionSearchField
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if displayedLedgerLines.isEmpty {
                ContentUnavailableView.search(text: transactionSearchText)
                    .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(displayedLedgerLines, id: \.persistentModelID) { line in
                transactionRow(for: line)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteLedgerLine(line)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)

                        Button {
                            editingLedgerLine = line
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            editingLedgerLine = line
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            deleteLedgerLine(line)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }

            if hasMoreTransactions {
                Button {
                    loadedTransactionCount += 50
                } label: {
                    Text("Load More")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var transactionSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(dashboardSecondaryText)

            TextField("Search transactions", text: $transactionSearchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !transactionSearchText.isEmpty {
                Button {
                    transactionSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(dashboardSecondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            Capsule(style: .continuous)
                .fill(dashboardCardBackground)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(
                    colorScheme == .dark ? Color.white.opacity(0.24) : Color.black.opacity(0.18),
                    lineWidth: 1.5
                )
        )
    }

    private var pnlSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Summary")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(dashboardPrimaryText)
                Spacer()
                Text("\(rangeFilteredLines.count) transactions")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(dashboardSecondaryText)
            }

            SlidingSegmentedPicker(
                selection: $pnlRange,
                items: ActivityPnLRange.allCases,
                title: { $0.title }
            )

            HStack(spacing: 10) {
                summaryValueCell(title: "Bought", value: -boughtTotal, emphasize: false)
                summaryValueCell(title: "Sold", value: soldTotal, emphasize: false)
            }

            HStack(spacing: 10) {
                summaryValueCell(title: "Collection Value", value: collectionValue, emphasize: true)
                summaryValueCell(title: "Profit", value: profitValue, emphasize: true)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(dashboardCardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(dashboardBorder, lineWidth: 1)
                )
        )
    }

    private func summaryValueCell(title: String, value: Double, emphasize: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(dashboardSecondaryText)
            Text(formatSignedCurrency(value))
                .font(emphasize ? .headline.weight(.bold) : .subheadline.weight(.semibold))
                .foregroundStyle(colorForSignedValue(value))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(dashboardCardInsetBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(dashboardBorder.opacity(0.5), lineWidth: 1)
        )
    }

    private func transactionRow(for line: LedgerLine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                transactionThumbnail(for: line)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        infoChip(label: directionTitle(for: line), tone: directionColor(for: line))
                        infoChip(label: "Qty \(line.quantity)")
                        if let variant = cleaned(line.variantKey) {
                            infoChip(label: variantTitle(variant))
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(line.occurredAt, format: .dateTime.day().month(.abbreviated).year())
                                .font(.caption.weight(.medium))
                                .foregroundStyle(dashboardSecondaryText)
                                .multilineTextAlignment(.trailing)
                            if let value = moneySummary(for: line) {
                                Text(value)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(colorForSignedValue(signedCashValue(for: line)))
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    Text(primaryTitle(for: line))
                        .font(.headline)
                        .foregroundStyle(dashboardPrimaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(dashboardCardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(dashboardBorder, lineWidth: 1)
                )
        )
    }

    private func infoChip(label: String, tone: Color? = nil) -> some View {
        Text(label)
            .font(.caption.weight(.medium))
            .foregroundStyle(tone ?? dashboardSecondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill((tone ?? dashboardSecondaryText).opacity(colorScheme == .dark ? 0.16 : 0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke((tone ?? dashboardSecondaryText).opacity(0.25), lineWidth: 1)
            )
    }

    private func resolveCardNames() async {
        var next = cardNamesByID
        var nextImages = cardImageURLsByID
        for line in visibleLedgerLines {
            guard let cardID = cleaned(line.cardID) else { continue }
            if let card = await services.cardData.loadCard(masterCardId: cardID) {
                if next[cardID] == nil {
                    next[cardID] = card.cardName
                }
                if nextImages[cardID] == nil {
                    let preferredPath = cleaned(card.imageHighSrc) ?? card.imageLowSrc
                    nextImages[cardID] = AppConfiguration.imageURL(relativePath: preferredPath)
                }
            }
        }
        cardNamesByID = next
        cardImageURLsByID = nextImages
    }

    @ViewBuilder
    private func transactionThumbnail(for line: LedgerLine) -> some View {
        if let imageURL = imageURL(for: line) {
            if line.productKind == ProductKind.sealedProduct.rawValue {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white)
                    CachedAsyncImage(url: imageURL, targetSize: CGSize(width: 120, height: 168)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        thumbnailFallback(for: line)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: 40, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(dashboardBorder, lineWidth: 1)
                )
            } else {
                CachedAsyncImage(url: imageURL, targetSize: CGSize(width: 120, height: 168)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    thumbnailFallback(for: line)
                }
                .frame(width: 40, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(dashboardBorder, lineWidth: 1)
                )
            }
        } else {
            thumbnailFallback(for: line)
        }
    }

    private func imageURL(for line: LedgerLine) -> URL? {
        if let cardID = cleaned(line.cardID), let url = cardImageURLsByID[cardID] {
            return url
        }
        if line.productKind == ProductKind.sealedProduct.rawValue {
            if let rawID = cleaned(line.sealedProductId), let id = Int(rawID) {
                return services.sealedProducts.products.first(where: { $0.id == id })?.imageURL
            }
            if let cardID = cleaned(line.cardID),
               let id = SealedProduct.parseCollectionProductID(cardID) {
                return services.sealedProducts.products.first(where: { $0.id == id })?.imageURL
            }
        }
        return nil
    }

    private func thumbnailFallback(for line: LedgerLine) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(dashboardCardInsetBackground)
            .frame(width: 40, height: 56)
            .overlay {
                Image(systemName: directionIcon(for: line))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(directionColor(for: line))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(dashboardBorder, lineWidth: 1)
            )
    }

    private func computeHoldingsCollectionValue() async {
        var total = 0.0

        for item in visibleCollectionItems {
            if let sealedProductID = sealedProductID(for: item),
               let sealedUSD = services.sealedProducts.marketPriceUSD(for: sealedProductID) {
                total += sealedUSD * Double(item.quantity)
                continue
            }

            guard let card = await services.cardData.loadCard(masterCardId: item.cardID) else { continue }
            let gradeKey: String = {
                guard let company = item.gradingCompany else { return "raw" }
                switch company.uppercased() {
                case "PSA": return "psa10"
                case "ACE": return "ace10"
                default: return "raw"
                }
            }()

            let usd = await services.pricing.usdPriceForVariantAndGrade(
                for: card,
                variantKey: item.variantKey,
                grade: gradeKey
            ) ?? 0
            total += usd * Double(item.quantity)
        }

        if services.priceDisplay.currency == .gbp {
            holdingsCollectionValue = total * services.pricing.usdToGbp
        } else {
            holdingsCollectionValue = total
        }
    }

    private func sealedProductID(for item: CollectionItem) -> Int? {
        if let rawID = item.sealedProductId, let productID = Int(rawID) {
            return productID
        }
        return SealedProduct.parseCollectionProductID(item.cardID)
    }

    private func primaryTitle(for line: LedgerLine) -> String {
        if line.productKind == ProductKind.sealedProduct.rawValue,
           let description = cleaned(line.lineDescription) {
            return description
        }
        if let cardID = cleaned(line.cardID), let name = cardNamesByID[cardID] {
            return name
        }
        if let cardID = cleaned(line.cardID) {
            return cardID
        }
        if !line.lineDescription.isEmpty {
            return line.lineDescription
        }
        return directionTitle(for: line)
    }

    private func secondarySubtitle(for line: LedgerLine) -> String {
        let description = cleaned(line.lineDescription)
        let counterparty = cleaned(line.counterparty)

        if let description, let counterparty, !description.contains(counterparty) {
            return "\(description) · \(counterparty)"
        }
        if let description {
            return description
        }
        if let counterparty {
            return counterparty
        }
        return productKindTitle(for: line)
    }

    private func directionTitle(for line: LedgerLine) -> String {
        if isOpenedSealedLine(line) { return "Opened" }
        guard let direction = LedgerDirection(rawValue: line.direction) else { return line.direction.capitalized }
        switch direction {
        case .bought: return "Bought"
        case .packed: return "Packed"
        case .sold: return "Sold"
        case .tradedIn: return "Trade In"
        case .tradedOut: return "Trade Out"
        case .giftedIn: return "Gift In"
        case .giftedOut: return "Gift Out"
        case .adjustmentIn: return "Adjustment In"
        case .adjustmentOut: return "Adjustment Out"
        }
    }

    private func productKindTitle(for line: LedgerLine) -> String {
        guard let kind = ProductKind(rawValue: line.productKind) else { return line.productKind }
        switch kind {
        case .singleCard: return "Single card"
        case .gradedItem: return "Graded item"
        case .sealedProduct: return "Sealed product"
        case .boosterPack: return "Booster pack"
        case .etb: return "ETB"
        case .other: return "Other"
        }
    }

    private func directionIcon(for line: LedgerLine) -> String {
        if isOpenedSealedLine(line) { return "shippingbox" }
        guard let direction = LedgerDirection(rawValue: line.direction) else { return "arrow.left.arrow.right" }
        switch direction {
        case .bought: return "cart.fill"
        case .packed: return "shippingbox.fill"
        case .sold: return "dollarsign.circle.fill"
        case .tradedIn, .tradedOut: return "arrow.left.arrow.right.circle.fill"
        case .giftedIn, .giftedOut: return "gift.fill"
        case .adjustmentIn: return "plus.circle.fill"
        case .adjustmentOut: return "minus.circle.fill"
        }
    }

    private func directionColor(for line: LedgerLine) -> Color {
        if isOpenedSealedLine(line) { return .orange }
        guard let direction = LedgerDirection(rawValue: line.direction) else { return .secondary }
        switch direction {
        case .bought, .packed, .tradedIn, .giftedIn, .adjustmentIn:
            return .green
        case .sold, .tradedOut, .giftedOut, .adjustmentOut:
            return .orange
        }
    }

    private func isOpenedSealedLine(_ line: LedgerLine) -> Bool {
        guard line.productKind == ProductKind.sealedProduct.rawValue else { return false }
        return line.sealedStatus == SealedInventoryStatus.opened.rawValue
    }

    private func moneySummary(for line: LedgerLine) -> String? {
        if isOpenedSealedLine(line) { return nil }
        guard let unitPrice = line.unitPrice else { return nil }
        let total = unitPrice * Double(line.quantity)
        return total.formatted(
            .currency(code: line.currencyCode)
            .precision(.fractionLength(2))
        )
    }

    private func signedCashValue(for line: LedgerLine) -> Double {
        guard let unitPrice = line.unitPrice else { return 0 }
        let total = unitPrice * Double(line.quantity)
        guard let direction = LedgerDirection(rawValue: line.direction) else { return 0 }
        switch direction {
        case .bought, .tradedIn, .giftedIn, .adjustmentIn:
            return -total
        case .sold, .tradedOut, .giftedOut, .adjustmentOut:
            return total
        case .packed:
            return 0
        }
    }

    private func formatSignedCurrency(_ value: Double) -> String {
        let absValue = abs(value).formatted(
            .currency(code: services.priceDisplay.currency == .gbp ? "GBP" : "USD")
            .precision(.fractionLength(2))
        )
        if value > 0 { return "+\(absValue)" }
        if value < 0 { return "-\(absValue)" }
        return absValue
    }

    private func colorForSignedValue(_ value: Double) -> Color {
        if value > 0 { return ActivityPalette.success }
        if value < 0 { return ActivityPalette.danger }
        return dashboardSecondaryText
    }

    private var dashboardPrimaryText: Color {
        Color(uiColor: .label)
    }

    private var dashboardSecondaryText: Color {
        Color(uiColor: .secondaryLabel)
    }

    private var dashboardCardBackground: Color {
        colorScheme == .dark ? .black : .white
    }

    private var dashboardCardInsetBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)
    }

    private var dashboardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func variantTitle(_ key: String) -> String {
        let spaced = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return spaced.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func deleteLedgerLine(_ line: LedgerLine) {
        do {
            if let ledger = services.collectionLedger {
                try ledger.deleteLedgerLineAndReconcileCollection(line)
            } else {
                modelContext.delete(line)
                try modelContext.save()
            }
            HapticManager.notification(.success)
        } catch {
            HapticManager.notification(.error)
            print("[Transactions] Failed to delete ledger line: \(error.localizedDescription)")
        }
    }

    private func searchableText(for line: LedgerLine) -> String {
        [
            primaryTitle(for: line),
            secondarySubtitle(for: line),
            directionTitle(for: line),
            productKindTitle(for: line),
            cleaned(line.variantKey).map(variantTitle),
            cleaned(line.cardID)
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .joined(separator: " ")
        .lowercased()
    }
}

private enum ActivityPnLRange: CaseIterable, Identifiable {
    case month
    case year
    case allTime

    var id: Self { self }

    var title: String {
        switch self {
        case .month: return "Month"
        case .year: return "Year"
        case .allTime: return "All Time"
        }
    }
}

private enum ActivityPalette {
    static let success = Color(red: 0.28, green: 0.84, blue: 0.39)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.34)
}

// MARK: - Add Manual Activity Sheet

private struct AddManualActivityView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    private let ledgerLineToEdit: LedgerLine?

    @State private var direction: LedgerDirection = .bought
    @State private var productKind: ProductKind = .singleCard
    @State private var lineDescription: String = ""
    @State private var quantity: Int = 1
    @State private var unitPriceText: String = ""
    @State private var counterparty: String = ""
    @State private var occurredAt: Date = Date()

    private var unitPrice: Double? {
        Double(unitPriceText.replacingOccurrences(of: ",", with: "."))
    }

    private var isEditing: Bool { ledgerLineToEdit != nil }

    private var selectedCurrencyCode: String {
        services.priceDisplay.currency == .gbp ? "GBP" : "USD"
    }

    private var sheetActionColor: Color {
        colorScheme == .dark ? .white : .black
    }

    init(ledgerLineToEdit: LedgerLine? = nil) {
        self.ledgerLineToEdit = ledgerLineToEdit
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    Picker(selection: $direction) {
                        ForEach(LedgerDirection.allCases, id: \.self) { dir in
                            Text(directionTitle(dir)).tag(dir)
                        }
                    } label: {
                        Text("Type")
                            .foregroundStyle(sheetActionColor)
                    }
                    Picker(selection: $productKind) {
                        ForEach(ProductKind.allCases, id: \.self) { kind in
                            Text(productKindTitle(kind)).tag(kind)
                        }
                    } label: {
                        Text("Item")
                            .foregroundStyle(sheetActionColor)
                    }
                    TextField("Description", text: $lineDescription)
                }

                Section("Transaction") {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...9999)
                    HStack {
                        Text("Unit price")
                        Spacer()
                        TextField("Optional", text: $unitPriceText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                    TextField("Counterparty", text: $counterparty)
                    DatePicker("Date", selection: $occurredAt, displayedComponents: .date)
                }
            }
            .navigationTitle(isEditing ? "Edit Activity" : "Add Activity")
            .navigationBarTitleDisplayMode(.inline)
            .tint(sheetActionColor)
            .onAppear {
                populateFieldsIfEditing()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(sheetActionColor)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .foregroundStyle(sheetActionColor)
                        .disabled(lineDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        do {
            if let existing = ledgerLineToEdit {
                existing.occurredAt = occurredAt
                existing.direction = direction.rawValue
                existing.productKind = productKind.rawValue
                existing.lineDescription = lineDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                existing.quantity = quantity
                existing.unitPrice = unitPrice
                existing.currencyCode = selectedCurrencyCode
                existing.counterparty = cleanedCounterparty
            } else {
                let line = LedgerLine(
                    occurredAt: occurredAt,
                    direction: direction.rawValue,
                    productKind: productKind.rawValue,
                    lineDescription: lineDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                    quantity: quantity,
                    unitPrice: unitPrice,
                    currencyCode: selectedCurrencyCode,
                    counterparty: cleanedCounterparty
                )
                modelContext.insert(line)
            }
            try modelContext.save()
            HapticManager.notification(.success)
            dismiss()
        } catch {
            HapticManager.notification(.error)
            print("[Transactions] Failed to save manual activity: \(error.localizedDescription)")
        }
    }

    private var cleanedCounterparty: String? {
        let trimmed = counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func populateFieldsIfEditing() {
        guard let line = ledgerLineToEdit else { return }
        occurredAt = line.occurredAt
        direction = LedgerDirection(rawValue: line.direction) ?? .bought
        productKind = ProductKind(rawValue: line.productKind) ?? .other
        lineDescription = line.lineDescription
        quantity = line.quantity
        unitPriceText = line.unitPrice.map { String($0) } ?? ""
        counterparty = line.counterparty ?? ""
    }

    private func directionTitle(_ dir: LedgerDirection) -> String {
        switch dir {
        case .bought: return "Bought"
        case .packed: return "Packed"
        case .sold: return "Sold"
        case .tradedIn: return "Trade In"
        case .tradedOut: return "Trade Out"
        case .giftedIn: return "Gift In"
        case .giftedOut: return "Gift Out"
        case .adjustmentIn: return "Adjustment In"
        case .adjustmentOut: return "Adjustment Out"
        }
    }

    private func productKindTitle(_ kind: ProductKind) -> String {
        switch kind {
        case .singleCard: return "Single card"
        case .gradedItem: return "Graded item"
        case .sealedProduct: return "Sealed product"
        case .boosterPack: return "Booster pack"
        case .etb: return "ETB"
        case .other: return "Other"
        }
    }
}
