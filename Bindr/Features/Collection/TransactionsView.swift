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
    @State private var selectedCardForDetail: Card? = nil
    @State private var selectedSealedProductForDetail: SealedProduct? = nil
    @State private var editingLedgerLine: LedgerLine?
    @State private var pnlRange: ActivityPnLRange = .month
    @State private var holdingsCollectionValue: Double = 0
    @State private var loadedTransactionCount: Int = 50
    @State private var transactionSearchText: String = ""
    @State private var transactionFilters = ActivityTransactionFilters()

    private var activeBrand: TCGBrand { .pokemon }

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
        let rangeKey = pnlRange.title
        let itemKey = periodCollectionItems
            .map { "\($0.cardID)|\($0.variantKey)|\($0.quantity)|\($0.itemKind)|\($0.gradingCompany ?? "")" }
            .joined(separator: "§")
        return "\(brandKey)|\(currencyKey)|\(rangeKey)|\(itemKey)"
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
        var lines = rangeFilteredLines

        if !transactionFilters.types.isEmpty {
            lines = lines.filter { matchesTypeFilter($0) }
        }

        if !transactionFilters.items.isEmpty {
            lines = lines.filter { matchesItemFilter($0) }
        }

        guard !query.isEmpty else { return lines }
        let normalizedQuery = query.lowercased()
        return lines.filter { line in
            searchableText(for: line).localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    private var hasActiveTransactionFilters: Bool {
        transactionFilters.hasActiveFilters
    }

    private var groupedActivityEntries: [ActivityLedgerEntry] {
        var grouped: [UUID: [LedgerLine]] = [:]
        var ungrouped: [LedgerLine] = []

        for line in filteredLedgerLines {
            if let groupID = line.transactionGroupId,
               line.channel == "trade",
               line.counterparty == "Local trade" {
                grouped[groupID, default: []].append(line)
            } else {
                ungrouped.append(line)
            }
        }

        let tradeGroups = grouped.values.map { lines in
            ActivityTradeGroup(lines: lines.sorted { $0.occurredAt > $1.occurredAt })
        }

        return (ungrouped.map(ActivityLedgerEntry.line) + tradeGroups.map(ActivityLedgerEntry.trade))
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    private var displayedActivityEntries: [ActivityLedgerEntry] {
        Array(groupedActivityEntries.prefix(loadedTransactionCount))
    }

    private var hasMoreTransactions: Bool {
        displayedActivityEntries.count < groupedActivityEntries.count
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

    private var periodCollectionItems: [CollectionItem] {
        let cal = Calendar.current
        let now = Date()
        return visibleCollectionItems.filter { item in
            switch pnlRange {
            case .month:
                return cal.isDate(item.dateAcquired, equalTo: now, toGranularity: .month)
            case .year:
                return cal.isDate(item.dateAcquired, equalTo: now, toGranularity: .year)
            case .allTime:
                return true
            }
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
            Task { await services.sealedProducts.loadFromLocalIfAvailable() }
        }
        .onChange(of: activeBrand) { _, _ in
            loadedTransactionCount = 50
        }
        .onChange(of: transactionFilters) { _, _ in
            loadedTransactionCount = 50
        }
        .onChange(of: transactionSearchText) { _, _ in
            loadedTransactionCount = 50
        }
        .sheet(isPresented: $showAddActivity) {
            AddManualActivityView()
        }
        .sheet(item: $selectedCardForDetail) { card in
            CardDetailSheet(cards: [card], startIndex: 0)
                .environment(services)
        }
        .sheet(item: $selectedSealedProductForDetail) { product in
            SealedProductBrowseDetailView(products: [product], startProductID: product.id)
                .environment(services)
        }
        .onChange(of: selectedSealedProductForDetail?.id) { _, productID in
            services.isSealedDetailPresentationActive = (productID != nil)
        }
        .sheet(item: $editingLedgerLine) { line in
            AddManualActivityView(ledgerLineToEdit: line)
        }
        .background(BindrPageBackground().ignoresSafeArea())
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
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            transactionSearchAndFilterRow
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if displayedActivityEntries.isEmpty {
                transactionEmptyResultsView
                    .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(displayedActivityEntries) { entry in
                activityRow(for: entry)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if case .line(let line) = entry {
                            openTransactionDetail(for: line)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteActivityEntry(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)

                        if case .line(let line) = entry {
                            Button {
                                editingLedgerLine = line
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                    .contextMenu {
                        if case .line(let line) = entry {
                            Button {
                                editingLedgerLine = line
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                        }

                        Button(role: .destructive) {
                            deleteActivityEntry(entry)
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

    private var transactionSearchAndFilterRow: some View {
        HStack(spacing: 8) {
            BrowseInlineSearchField(title: "Search transactions", text: $transactionSearchText)

            Menu {
                ActivityTransactionFiltersMenuContent(filters: $transactionFilters)
            } label: {
                Image(systemName: hasActiveTransactionFilters
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(hasActiveTransactionFilters ? services.theme.accentColor : .primary)
                    .modifier(ChromeGlassCircleGlyphModifier())
            }
            .buttonStyle(.plain)
            .menuActionDismissBehavior(.disabled)
            .menuOrder(.fixed)
            .accessibilityLabel("Filter transactions")
        }
    }

    @ViewBuilder
    private var transactionEmptyResultsView: some View {
        let trimmedQuery = transactionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            ContentUnavailableView.search(text: transactionSearchText)
        } else if hasActiveTransactionFilters {
            ContentUnavailableView(
                "No matching transactions",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Try changing your type or item filters.")
            )
        } else {
            ContentUnavailableView(
                "No transactions",
                systemImage: "list.bullet.rectangle",
                description: Text("Transactions for this period will appear here.")
            )
        }
    }

    private var pnlSummaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 10) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(services.theme.accentColor.gradient, in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Summary")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(dashboardPrimaryText)
                        Text(pnlRange.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(services.theme.accentColor)
                    }
                }
                Spacer()
                Text("\(groupedActivityEntries.count) transactions")
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
        .glassCardStyle(cornerRadius: 24, interactive: true)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(services.theme.accentColor.opacity(colorScheme == .dark ? 0.20 : 0.12))
                .frame(width: 96, height: 96)
                .blur(radius: 28)
                .offset(x: 22, y: -26)
                .allowsHitTesting(false)
        }
    }

    private func summaryValueCell(title: String, value: Double, emphasize: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: summaryIcon(for: title))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(colorForSignedValue(value))
                .frame(width: 28, height: 28)
                .background(colorForSignedValue(value).opacity(colorScheme == .dark ? 0.16 : 0.11), in: Circle())

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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(dashboardTileBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(dashboardBorder.opacity(0.5), lineWidth: 1)
        )
    }

    private func summaryIcon(for title: String) -> String {
        switch title {
        case "Bought": return "cart.fill"
        case "Sold": return "tag.fill"
        case "Collection Value": return "rectangle.stack.fill"
        case "Profit": return "sparkles"
        default: return "chart.bar.fill"
        }
    }

    @ViewBuilder
    private func activityRow(for entry: ActivityLedgerEntry) -> some View {
        switch entry {
        case .line(let line):
            transactionRow(for: line)
        case .trade(let group):
            tradeGroupRow(for: group)
        }
    }

    private func tradeGroupRow(for group: ActivityTradeGroup) -> some View {
        let summary = tradeSummary(for: group.lines)
        let netCash = tradeNetCash(for: group.lines)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                transactionThumbnail(for: group.thumbnailLine)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        infoChip(label: "Local Trade", tone: .orange)
                        infoChip(label: "\(group.lines.count) entries")
                        Spacer(minLength: 8)

                        VStack(alignment: .trailing, spacing: 5) {
                            Text(group.occurredAt, format: .dateTime.day().month(.abbreviated).year())
                                .font(.caption.weight(.medium))
                                .foregroundStyle(dashboardSecondaryText)
                                .multilineTextAlignment(.trailing)
                            if abs(netCash) > 0.001 {
                                Text(formatSignedCurrency(netCash))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(colorForSignedValue(netCash))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Local trade")
                            .font(.headline)
                            .foregroundStyle(dashboardPrimaryText)
                            .lineLimit(1)
                        Text(summary)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(dashboardSecondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(cornerRadius: 20, interactive: false)
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
                        HStack(spacing: 8) {
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
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        Text(primaryTitle(for: line))
                            .font(.headline)
                            .foregroundStyle(dashboardPrimaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(dashboardSecondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(cornerRadius: 20, interactive: false)
    }

    private func tradeSummary(for lines: [LedgerLine]) -> String {
        let gave = lines
            .filter { isTradeGaveLine($0) }
            .map(tradeSummaryPart)
        let received = lines
            .filter { isTradeReceivedLine($0) }
            .map(tradeSummaryPart)

        let gaveText = gave.isEmpty ? "nothing" : gave.joined(separator: " + ")
        let receivedText = received.isEmpty ? "nothing" : received.joined(separator: " + ")
        return "\(gaveText) for \(receivedText)"
    }

    private func tradeSummaryPart(for line: LedgerLine) -> String {
        if line.productKind == ProductKind.other.rawValue,
           let value = moneySummary(for: line) {
            return value
        }

        let title = primaryTitle(for: line)
        if line.quantity > 1 {
            return "\(line.quantity)x \(title)"
        }
        return title
    }

    private func isTradeGaveLine(_ line: LedgerLine) -> Bool {
        guard let direction = LedgerDirection(rawValue: line.direction) else { return false }
        switch direction {
        case .tradedOut, .bought:
            return true
        default:
            return false
        }
    }

    private func isTradeReceivedLine(_ line: LedgerLine) -> Bool {
        guard let direction = LedgerDirection(rawValue: line.direction) else { return false }
        switch direction {
        case .tradedIn, .sold:
            return true
        default:
            return false
        }
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
                    nextImages[cardID] = AppConfiguration.imageURL(relativePath: card.displayImageSrc)
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

        for item in periodCollectionItems {
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

    private func sealedProductID(for line: LedgerLine) -> Int? {
        if let rawID = cleaned(line.sealedProductId), let productID = Int(rawID) {
            return productID
        }
        if let cardID = cleaned(line.cardID) {
            return SealedProduct.parseCollectionProductID(cardID)
        }
        return nil
    }

    private func openTransactionDetail(for line: LedgerLine) {
        if line.productKind == ProductKind.sealedProduct.rawValue {
            Task {
                await services.sealedProducts.loadFromLocalIfAvailable()
                guard let productID = sealedProductID(for: line),
                      let product = services.sealedProducts.products.first(where: { $0.id == productID })
                else { return }
                await MainActor.run { selectedSealedProductForDetail = product }
            }
            return
        }

        guard let cardID = cleaned(line.cardID) else { return }
        Task {
            if let card = await services.cardData.loadCard(masterCardId: cardID) {
                await MainActor.run { selectedCardForDetail = card }
            }
        }
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
        case .importedIn: return "Imported"
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
        case .importedIn: return "square.and.arrow.down.fill"
        }
    }

    private func directionColor(for line: LedgerLine) -> Color {
        if isOpenedSealedLine(line) { return .orange }
        guard let direction = LedgerDirection(rawValue: line.direction) else { return .secondary }
        switch direction {
        case .bought, .packed, .tradedIn, .giftedIn, .adjustmentIn, .importedIn:
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

    private func isTradeCashLine(_ line: LedgerLine) -> Bool {
        line.productKind == ProductKind.other.rawValue
    }

    /// Net cash movement for a local trade — only explicit cash lines, not card market values.
    private func tradeNetCash(for lines: [LedgerLine]) -> Double {
        lines
            .filter(isTradeCashLine)
            .reduce(0) { $0 + signedCashValue(for: $1) }
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
        case .packed, .importedIn:
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

    private var dashboardTileBackground: Color {
        colorScheme == .dark ? dashboardCardInsetBackground : .white
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
        }
    }

    private func deleteActivityEntry(_ entry: ActivityLedgerEntry) {
        switch entry {
        case .line(let line):
            deleteLedgerLine(line)
        case .trade(let group):
            for line in group.lines {
                deleteLedgerLine(line)
            }
        }
    }

    private func markActions(for line: LedgerLine) -> [TransactionMarkAction] {
        var actions: [TransactionMarkAction] = [
            .bought, .sold, .packed, .tradedIn, .tradedOut, .giftedIn, .giftedOut, .adjustmentIn, .adjustmentOut
        ]
        if line.productKind == ProductKind.sealedProduct.rawValue {
            actions.append(.opened)
        }
        return actions
    }

    private func markLedgerLine(_ line: LedgerLine, as action: TransactionMarkAction) {
        let isSealedProduct = line.productKind == ProductKind.sealedProduct.rawValue

        switch action {
        case .bought:
            line.direction = LedgerDirection.bought.rawValue
            line.sealedStatus = isSealedProduct ? SealedInventoryStatus.sealed.rawValue : nil
        case .sold:
            line.direction = LedgerDirection.sold.rawValue
            line.sealedStatus = isSealedProduct ? SealedInventoryStatus.sealed.rawValue : nil
        case .packed:
            line.direction = LedgerDirection.packed.rawValue
            line.sealedStatus = isSealedProduct ? SealedInventoryStatus.sealed.rawValue : nil
        case .tradedIn:
            line.direction = LedgerDirection.tradedIn.rawValue
            line.sealedStatus = isSealedProduct ? SealedInventoryStatus.sealed.rawValue : nil
        case .tradedOut:
            line.direction = LedgerDirection.tradedOut.rawValue
            line.sealedStatus = isSealedProduct ? SealedInventoryStatus.sealed.rawValue : nil
        case .giftedIn:
            line.direction = LedgerDirection.giftedIn.rawValue
            line.sealedStatus = isSealedProduct ? SealedInventoryStatus.sealed.rawValue : nil
        case .giftedOut:
            line.direction = LedgerDirection.giftedOut.rawValue
            line.sealedStatus = isSealedProduct ? SealedInventoryStatus.sealed.rawValue : nil
        case .adjustmentIn:
            line.direction = LedgerDirection.adjustmentIn.rawValue
            line.sealedStatus = isSealedProduct ? SealedInventoryStatus.sealed.rawValue : nil
        case .adjustmentOut:
            line.direction = LedgerDirection.adjustmentOut.rawValue
            line.sealedStatus = isSealedProduct ? SealedInventoryStatus.sealed.rawValue : nil
        case .opened:
            line.direction = LedgerDirection.adjustmentOut.rawValue
            line.sealedStatus = SealedInventoryStatus.opened.rawValue
        }

        do {
            try modelContext.save()
            HapticManager.notification(.success)
        } catch {
            HapticManager.notification(.error)
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

    private func matchesTypeFilter(_ line: LedgerLine) -> Bool {
        guard !transactionFilters.types.isEmpty else { return true }
        if transactionFilters.types.contains(.localTrade),
           line.channel == "trade",
           line.counterparty == "Local trade" {
            return true
        }
        return transactionFilters.types.contains(activityTypeFilter(for: line))
    }

    private func matchesItemFilter(_ line: LedgerLine) -> Bool {
        guard !transactionFilters.items.isEmpty else { return true }
        guard let kind = ProductKind(rawValue: line.productKind) else { return false }
        return transactionFilters.items.contains(kind)
    }

    private func activityTypeFilter(for line: LedgerLine) -> ActivityTypeFilter {
        if isOpenedSealedLine(line) { return .opened }
        guard let direction = LedgerDirection(rawValue: line.direction) else { return .adjustmentIn }
        switch direction {
        case .bought: return .bought
        case .packed: return .packed
        case .sold: return .sold
        case .tradedIn: return .tradeIn
        case .tradedOut: return .tradeOut
        case .giftedIn: return .giftIn
        case .giftedOut: return .giftOut
        case .adjustmentIn: return .adjustmentIn
        case .adjustmentOut: return .adjustmentOut
        case .importedIn: return .imported
        }
    }
}

private enum ActivityLedgerEntry: Identifiable {
    case line(LedgerLine)
    case trade(ActivityTradeGroup)

    var id: String {
        switch self {
        case .line(let line):
            return "line-\(line.id.uuidString)"
        case .trade(let group):
            return "trade-\(group.id.uuidString)"
        }
    }

    var occurredAt: Date {
        switch self {
        case .line(let line):
            return line.occurredAt
        case .trade(let group):
            return group.occurredAt
        }
    }
}

private struct ActivityTradeGroup: Identifiable {
    let id: UUID
    let lines: [LedgerLine]

    init(lines: [LedgerLine]) {
        self.lines = lines
        self.id = lines.compactMap(\.transactionGroupId).first ?? UUID()
    }

    var occurredAt: Date {
        lines.map(\.occurredAt).max() ?? Date.distantPast
    }

    var thumbnailLine: LedgerLine {
        lines.first { line in
            LedgerDirection(rawValue: line.direction) == .tradedIn && line.cardID != nil
        } ?? lines.first { line in
            line.cardID != nil
        } ?? lines[0]
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
    static let trade = Color(red: 0.55, green: 0.38, blue: 1.0)
}

private enum ActivityTypeFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case bought
    case sold
    case packed
    case opened
    case tradeIn
    case tradeOut
    case localTrade
    case giftIn
    case giftOut
    case adjustmentIn
    case adjustmentOut
    case imported

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bought: return "Bought"
        case .sold: return "Sold"
        case .packed: return "Packed"
        case .opened: return "Opened"
        case .tradeIn: return "Trade In"
        case .tradeOut: return "Trade Out"
        case .localTrade: return "Local Trade"
        case .giftIn: return "Gift In"
        case .giftOut: return "Gift Out"
        case .adjustmentIn: return "Adjustment In"
        case .adjustmentOut: return "Adjustment Out"
        case .imported: return "Imported"
        }
    }
}

private struct ActivityTransactionFilters: Equatable, Sendable {
    var types: Set<ActivityTypeFilter> = []
    var items: Set<ProductKind> = []

    var hasActiveFilters: Bool {
        !types.isEmpty || !items.isEmpty
    }
}

private struct ActivityTransactionFiltersMenuContent: View {
    @Binding var filters: ActivityTransactionFilters

    var body: some View {
        if filters.hasActiveFilters {
            Section {
                Button(role: .destructive) {
                    filters = ActivityTransactionFilters()
                } label: {
                    Label("Reset filters", systemImage: "arrow.counterclockwise.circle")
                }
            }
        }

        Section("Type") {
            Menu {
                ForEach(ActivityTypeFilter.allCases) { type in
                    Toggle(type.title, isOn: typeBinding(for: type))
                }
            } label: {
                Label(
                    menuTitle("Type", summary: selectionSummary(for: filters.types.map(\.title))),
                    systemImage: "arrow.left.arrow.right.circle"
                )
            }
            .menuActionDismissBehavior(.disabled)
            .menuOrder(.fixed)
        }

        Section("Item") {
            Menu {
                ForEach(ProductKind.allCases, id: \.rawValue) { kind in
                    Toggle(productKindTitle(for: kind), isOn: itemBinding(for: kind))
                }
            } label: {
                Label(
                    menuTitle("Item", summary: selectionSummary(for: filters.items.map(productKindTitle(for:)))),
                    systemImage: "square.stack.3d.up"
                )
            }
            .menuActionDismissBehavior(.disabled)
            .menuOrder(.fixed)
        }
    }

    private func typeBinding(for type: ActivityTypeFilter) -> Binding<Bool> {
        Binding(
            get: { filters.types.contains(type) },
            set: { isOn in
                if isOn {
                    filters.types.insert(type)
                } else {
                    filters.types.remove(type)
                }
            }
        )
    }

    private func itemBinding(for kind: ProductKind) -> Binding<Bool> {
        Binding(
            get: { filters.items.contains(kind) },
            set: { isOn in
                if isOn {
                    filters.items.insert(kind)
                } else {
                    filters.items.remove(kind)
                }
            }
        )
    }

    private func menuTitle(_ title: String, summary: String?) -> String {
        guard let summary, !summary.isEmpty else { return title }
        return "\(title): \(summary)"
    }

    private func selectionSummary(for values: [String]) -> String? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        if sorted.count <= 2 {
            return sorted.joined(separator: ", ")
        }
        return "\(sorted.prefix(2).joined(separator: ", ")) +\(sorted.count - 2)"
    }

    private func productKindTitle(for kind: ProductKind) -> String {
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
