import SwiftData
import SwiftUI

struct TradesView: View {
    private enum ExpandedTradeSection {
        case wall
        case active
    }

    @Environment(AppServices.self) private var services
    @Environment(\.bindrAccent) private var accent
    @Environment(\.modelContext) private var modelContext
    @Binding var navigationPath: NavigationPath
    var selectedTab: Binding<SocialTab>? = nil
    var headerInset: CGFloat = 0

    @State private var trades: [TradeWithItems] = []
    @State private var profileCache: [UUID: SocialProfile] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showsCompletedTrades = false
    @State private var expandedSection: ExpandedTradeSection = .wall
    @State private var hasLoadedTrades = false

    private var currentUserID: UUID? {
        if case .signedIn(let uid, _) = services.socialAuth.authState { return uid }
        return nil
    }

    private var openTrades: [TradeWithItems] {
        trades.filter { tradeWithItems in
            switch tradeWithItems.trade.status {
            case .pending, .countered, .accepted:
                return true
            case .complete, .cancelled:
                return false
            }
        }
    }

    private var completedTrades: [TradeWithItems] {
        trades.filter { $0.trade.status == .complete }
    }

    private var tradesAwaitingMe: Int {
        guard let currentUserID else { return 0 }
        return openTrades.filter { trade in
            trade.needsResponse(from: currentUserID)
                || (trade.trade.status == .accepted && !trade.myCompleted(currentUserID: currentUserID))
        }.count
    }

    private var displayedTrades: [TradeWithItems] {
        showsCompletedTrades ? (openTrades + completedTrades) : openTrades
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Color.clear.frame(height: headerInset)
                if let selectedTab {
                    SlidingSegmentedPicker(
                        selection: selectedTab,
                        items: SocialTab.allCases,
                        title: { $0.title }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }
                tradeOpportunityTray
                    .padding(.top, 6)
                    .padding(.bottom, 14)
            }
            // Generous bottom padding so the last section never slides under
            // the app's custom bottom tab bar (≈60pt) plus the home indicator
            // (~34pt). The Social shell ignores the bottom safe area so this
            // padding is what keeps content above the nav.
            .padding(.bottom, 120)
        }
        .refreshable { await refresh() }
        .task {
            services.setupCollectionLedger(modelContext: modelContext)
            await loadAfterFirstPaint()
        }
        .onChange(of: services.trade.lastMutationAt) { _, _ in
            Task { await refresh(force: true) }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
    }

    // MARK: - Trade opportunity tray

    private var tradeOpportunityTray: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                tradeOpportunityButton(
                    title: "Trade Wall",
                    subtitle: "Matches & wishlist finds",
                    systemImage: "sparkles",
                    count: nil,
                    isExpanded: expandedSection == .wall
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        expandedSection = .wall
                    }
                }

                tradeOpportunityButton(
                    title: "Active",
                    subtitle: showsCompletedTrades ? "Including completed" : "Open offers",
                    systemImage: "arrow.left.arrow.right",
                    count: openTrades.count,
                    isExpanded: expandedSection == .active
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        expandedSection = .active
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            if expandedSection == .wall {
                TradeWallView(navigationPath: $navigationPath)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 16)
            }

            if expandedSection == .active {
                activeTradesPanel
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Shared Header Helpers

    private func tradeOpportunityButton(
        title: String,
        subtitle: String,
        systemImage: String,
        count: Int?,
        isExpanded: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selectionChanged()
            action()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isExpanded ? Color.white.opacity(0.22) : Color.primary.opacity(0.06))
                        .frame(width: 34, height: 34)
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(isExpanded ? Color.white : Color.primary.opacity(0.75))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(isExpanded ? Color.white : Color.primary)
                            .lineLimit(1)
                        if let count {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(isExpanded ? Color.white : Color.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background((isExpanded ? Color.white.opacity(0.20) : Color.primary.opacity(0.07)), in: Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isExpanded ? Color.white.opacity(0.78) : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(isExpanded ? accent : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isExpanded ? Color.white.opacity(0.18) : Color.primary.opacity(0.07), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Trades List

    private var activeTradesPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Active trades")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(.primary)
                    Text(activeTradesSummary)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("Completed")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Toggle("", isOn: $showsCompletedTrades)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .scaleEffect(0.82)
                        .frame(width: 44, height: 28)
                }
            }

            if isLoading && displayedTrades.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 26)
            } else if displayedTrades.isEmpty && !isLoading {
                openTradesEmptyState
            } else {
                tradesList
            }
        }
    }

    private var activeTradesSummary: String {
        var parts: [String] = []
        parts.append("\(openTrades.count) open")
        if tradesAwaitingMe > 0 {
            parts.append(tradesAwaitingMe == 1 ? "1 needs action" : "\(tradesAwaitingMe) need action")
        }
        if showsCompletedTrades {
            parts.append("\(completedTrades.count) complete")
        }
        return parts.joined(separator: " · ")
    }

    private var tradesList: some View {
        LazyVStack(spacing: 10) {
            ForEach(displayedTrades) { tradeWithItems in
                Button {
                    navigationPath.append(SocialDestination.tradeDetail(tradeID: tradeWithItems.id))
                } label: {
                    TradeRowView(
                        tradeWithItems: tradeWithItems,
                        currentUserID: currentUserID ?? UUID(),
                        counterpartProfile: profileCache[tradeWithItems.counterpartID(currentUserID: currentUserID ?? UUID())]
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var openTradesEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.secondary.opacity(0.4))
            Text(showsCompletedTrades ? "No trades yet" : "No open trades")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.secondary)
            Text(showsCompletedTrades
                 ? "Start from a Trade Wall opportunity, a friend's wishlist, or a friend's available cards."
                 : "Your active pending/countered/accepted trades will appear here.")
                .font(.system(size: 13))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    // MARK: - Data

    private func loadAfterFirstPaint() async {
        guard !hasLoadedTrades else { return }
        hasLoadedTrades = true
        await Task.yield()
        try? await Task.sleep(nanoseconds: 120_000_000)
        await refresh(force: true)
    }

    private func refresh(force: Bool = false) async {
        guard force || !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            trades = try await services.trade.fetchMyTrades()
            await loadProfilesForTrades()
            await applyCompletedTradeSettlementsIfNeeded()
            errorMessage = nil
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadProfilesForTrades() async {
        guard let uid = currentUserID else { return }
        let counterpartIDs = Set(trades.map { $0.counterpartID(currentUserID: uid) })
        let missingIDs = counterpartIDs.filter { profileCache[$0] == nil }
        guard !missingIDs.isEmpty else { return }

        await withTaskGroup(of: SocialProfile?.self) { group in
            for userID in missingIDs {
                group.addTask {
                    try? await services.socialProfile.fetchProfile(id: userID)
                }
            }
            for await profile in group {
                if let profile {
                    profileCache[profile.id] = profile
                }
            }
        }
    }

    private func applyCompletedTradeSettlementsIfNeeded() async {
        guard let uid = currentUserID else { return }
        services.setupCollectionLedger(modelContext: modelContext)
        for tradeWithItems in trades where tradeWithItems.shouldSettleCollection(for: uid) {
            await applyLocalTradeSettlementIfNeeded(tradeWithItems)
        }
    }

    private func applyLocalTradeSettlementIfNeeded(_ twi: TradeWithItems) async {
        guard let uid = currentUserID else { return }
        let settlementKey = "trade.local.settlement.\(uid.uuidString).\(twi.id.uuidString)"

        let myItems = twi.myItems(currentUserID: uid)
        let theirItems = twi.theirItems(currentUserID: uid)
        let myCash = twi.myCash(currentUserID: uid)
        let theirCash = twi.theirCash(currentUserID: uid)
        let counterpartyID = twi.counterpartID(currentUserID: uid)
        let counterpartyProfile = profileCache[counterpartyID]
        let counterparty = counterpartyProfile?.displayName ?? counterpartyProfile?.username ?? "Trade partner"
        let currencyCode = services.priceDisplay.currency == .gbp ? "GBP" : "USD"
        let reference = "trade-complete-\(twi.id.uuidString)"

        let netCashPaid = myCash - theirCash
        let totalReceivedQty = theirItems.reduce(0) { $0 + max($1.quantity, 1) }
        let isCashPurchase = netCashPaid > 0 && totalReceivedQty > 0
        let cardUnitPrice = isCashPurchase ? netCashPaid / Double(totalReceivedQty) : nil

        guard !UserDefaults.standard.bool(forKey: settlementKey) else { return }
        guard let ledger = services.collectionLedger else { return }

        for item in myItems {
            let quantity = max(item.quantity, 1)
            guard let stack = findCardStack(cardID: item.cardID, variantKey: item.variantKey),
                  stack.quantity > 0 else { continue }
            let cardName = await resolvedCardName(for: item.cardID)
            if cardLedgerEntryExists(
                direction: .tradedOut,
                cardID: stack.cardID,
                variantKey: stack.variantKey,
                quantity: quantity,
                counterparty: counterparty
            ) {
                continue
            }
            do {
                try ledger.recordSingleCardDisposition(
                    item: stack,
                    kind: .traded,
                    quantity: min(quantity, stack.quantity),
                    currencyCode: currencyCode,
                    cardDisplayName: cardName,
                    unitPrice: nil,
                    counterparty: counterparty,
                    notes: "Traded to \(counterparty)"
                )
            } catch {
                continue
            }
        }

        for item in theirItems {
            let cardName = await resolvedCardName(for: item.cardID)
            let qty = max(item.quantity, 1)
            if cardLedgerEntryExists(
                direction: isCashPurchase ? .bought : .tradedIn,
                cardID: item.cardID,
                variantKey: item.variantKey,
                quantity: qty,
                counterparty: counterparty
            ) {
                continue
            }
            do {
                try ledger.recordSingleCardAcquisition(
                    cardID: item.cardID,
                    variantKey: item.variantKey,
                    kind: isCashPurchase ? .bought : .trade,
                    quantity: qty,
                    currencyCode: currencyCode,
                    cardDisplayName: cardName,
                    unitPrice: cardUnitPrice,
                    packedOpenedFrom: nil,
                    tradeCounterparty: isCashPurchase ? nil : counterparty,
                    tradeGaveAway: nil,
                    giftFrom: nil,
                    boughtFrom: isCashPurchase ? counterparty : nil
                )
                let note = isCashPurchase ? "Bought from \(counterparty)" : "Traded from \(counterparty)"
                appendCardNote(cardID: item.cardID, variantKey: item.variantKey, note: note)
            } catch {
                continue
            }
        }

        if theirCash > 0, !cashLedgerEntryExists(reference: reference) {
            let line = LedgerLine(
                direction: LedgerDirection.sold.rawValue,
                productKind: ProductKind.other.rawValue,
                lineDescription: "Trade cash received",
                quantity: 1,
                unitPrice: theirCash,
                currencyCode: currencyCode,
                counterparty: counterparty,
                channel: "trade",
                externalRef: reference
            )
            modelContext.insert(line)
        }
        if myCash > 0, !cashLedgerEntryExists(reference: "\(reference)-out") {
            let line = LedgerLine(
                direction: LedgerDirection.bought.rawValue,
                productKind: ProductKind.other.rawValue,
                lineDescription: "Trade cash paid",
                quantity: 1,
                unitPrice: myCash,
                currencyCode: currencyCode,
                counterparty: counterparty,
                channel: "trade",
                externalRef: "\(reference)-out"
            )
            modelContext.insert(line)
        }

        do {
            try modelContext.save()
            UserDefaults.standard.set(true, forKey: settlementKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func appendCardNote(cardID: String, variantKey: String, note: String) {
        let kind = ProductKind.singleCard.rawValue
        let all = (try? modelContext.fetch(FetchDescriptor<CollectionItem>())) ?? []
        for stack in all where stack.cardID == cardID && stack.variantKey == variantKey && stack.itemKind == kind {
            if stack.notes.isEmpty {
                stack.notes = note
            } else if !stack.notes.localizedCaseInsensitiveContains(note) {
                stack.notes = "\(stack.notes); \(note)"
            }
        }
    }

    private func findCardStack(cardID: String, variantKey: String) -> CollectionItem? {
        let all = (try? modelContext.fetch(FetchDescriptor<CollectionItem>())) ?? []
        let matchingStacks = all.filter {
            $0.cardID == cardID
                && ($0.itemKind == ProductKind.singleCard.rawValue || $0.itemKind == ProductKind.gradedItem.rawValue)
        }
        return matchingStacks.first(where: { $0.variantKey == variantKey }) ?? matchingStacks.first
    }

    private func cashLedgerEntryExists(reference: String) -> Bool {
        let all = (try? modelContext.fetch(FetchDescriptor<LedgerLine>())) ?? []
        return all.contains(where: { $0.externalRef == reference })
    }

    private func cardLedgerEntryExists(
        direction: LedgerDirection,
        cardID: String,
        variantKey: String,
        quantity: Int,
        counterparty: String
    ) -> Bool {
        let all = (try? modelContext.fetch(FetchDescriptor<LedgerLine>())) ?? []
        return all.contains {
            $0.direction == direction.rawValue
                && $0.cardID == cardID
                && $0.variantKey == variantKey
                && $0.quantity == quantity
                && $0.counterparty == counterparty
        }
    }

    private func resolvedCardName(for cardID: String) async -> String {
        if let card = await services.cardData.loadCard(masterCardId: cardID) {
            return card.cardName
        }
        return cardID
    }
}
