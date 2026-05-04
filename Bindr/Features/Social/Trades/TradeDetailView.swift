import SwiftUI
import SwiftData

struct TradeDetailView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let tradeID: UUID

    @State private var tradeWithItems: TradeWithItems?
    @State private var myProfile: SocialProfile?
    @State private var theirProfile: SocialProfile?
    @State private var isLoading = false
    @State private var isMutating = false
    @State private var errorMessage: String?
    @State private var showConfirmDecline = false
    @State private var showConfirmCancel = false
    @State private var showConfirmComplete = false
    @State private var myItemsValueUSD: Double = 0
    @State private var theirItemsValueUSD: Double = 0
    @State private var isValuationLoading = false
    @State private var valuationCardCacheByID: [String: Card] = [:]

    private var currentUserID: UUID? {
        if case .signedIn(let uid, _) = services.socialAuth.authState { return uid }
        return nil
    }

    private var trade: Trade? { tradeWithItems?.trade }

    private var isInitiator: Bool {
        guard let uid = currentUserID, let t = trade else { return false }
        return t.initiatorID == uid
    }

    private var themeColor: Color {
        if let hex = myProfile?.avatarBackgroundColor, !hex.isEmpty {
            return Color(hex: hex)
        }
        return .cyan
    }

    var body: some View {
        ZStack {
            // Immersive Retro-Tech Background
            Color.black.ignoresSafeArea()
            
            // Atmospheric Scanlines
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, themeColor.opacity(0.03), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 2)
                .offset(y: -100)
                .ignoresSafeArea()

            if isLoading && tradeWithItems == nil {
                ProgressView()
                    .tint(themeColor)
                    .scaleEffect(1.5)
            } else if let tradeWithItems {
                tradeContent(tradeWithItems)
            } else {
                ContentUnavailableView(
                    "Trade Disconnected",
                    systemImage: "wifi.exclamationmark",
                    description: Text("The link could not be established.")
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(trade?.status.rawValue.uppercased() ?? "PENDING")
                        .font(.system(size: 10, weight: .black))
                        .tracking(2)
                        .foregroundStyle(themeColor)
                    Text("TRADE SESSION")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
        }
        .task {
            services.setupCollectionLedger(modelContext: modelContext)
            await refresh()
        }
        .task(id: services.trade.lastMutationAt) {
            await refresh()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
        .alert("Decline this trade?", isPresented: $showConfirmDecline) {
            Button("Decline", role: .destructive) { Task { await performCancel() } }
            Button("Keep Trade", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Cancel this trade?", isPresented: $showConfirmCancel) {
            Button("Cancel Trade", role: .destructive) { Task { await performCancel() } }
            Button("Keep Trade", role: .cancel) { }
        } message: {
            Text("This will close the trade for both sides.")
        }
        .alert("Mark this trade as complete?", isPresented: $showConfirmComplete) {
            Button("Mark Complete") { Task { await performComplete() } }
            Button("Not Yet", role: .cancel) { }
        } message: {
            Text("Use this only after cards and cash have been exchanged.")
        }
    }

    private func tradeContent(_ twi: TradeWithItems) -> some View {
        let resolvedUID = currentUserID ?? UUID()
        let myItems = twi.myItems(currentUserID: resolvedUID)
        let theirItems = twi.theirItems(currentUserID: resolvedUID)
        let myCash = twi.myCash(currentUserID: resolvedUID)
        let theirCash = twi.theirCash(currentUserID: resolvedUID)
        let myTotalUSD = myItemsValueUSD + displayAmountToUSD(myCash)
        let theirTotalUSD = theirItemsValueUSD + displayAmountToUSD(theirCash)

        return VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // TOP POD: Their Side
                    tradePod(
                        label: "THEIR OFFER",
                        profile: theirProfile,
                        items: theirItems,
                        cash: theirCash,
                        totalValueUSD: theirTotalUSD,
                        alignment: .top
                    )
                    
                    // CENTRAL LINK CORE
                    centralLinkCore(twi.trade.status)
                        .padding(.vertical, -30)
                        .zIndex(10)
                    
                    // BOTTOM POD: My Side
                    tradePod(
                        label: "MY OFFER",
                        profile: myProfile,
                        items: myItems,
                        cash: myCash,
                        totalValueUSD: myTotalUSD,
                        alignment: .bottom
                    )
                }
                .padding(.vertical, 20)
            }
            
            // ACTION FOOTER - Pinned to bottom, no overlap
            VStack(spacing: 12) {
                actionButtons(twi)
            }
            .padding(20)
            .padding(.bottom, 10) // Extra space for safe area
            .background {
                ZStack {
                    Color.black.opacity(0.8)
                        .blur(radius: 20)
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                }
                .ignoresSafeArea()
            }
        }
        .task(id: valuationSignature(for: twi)) {
            await refreshTradeValues(for: twi)
        }
    }

    private func tradePod(
        label: String,
        profile: SocialProfile?,
        items: [TradeItem],
        cash: Double,
        totalValueUSD: Double,
        alignment: VerticalAlignment
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Pod Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(themeColor.opacity(0.6))
                    
                    if let profile {
                        Text(profile.displayName ?? "@\(profile.username)")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if isValuationLoading {
                        ProgressView().tint(themeColor).scaleEffect(0.7)
                    } else {
                        Text(formattedDisplayAmountUSD(totalValueUSD))
                            .font(.system(size: 17, weight: .black, design: .monospaced))
                            .foregroundStyle(themeColor)
                    }
                    Text("\(items.count) CARDS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 8)
            
            // Item Scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if cash > 0 {
                        cashTile(cash)
                    }
                    
                    if items.isEmpty && cash == 0 {
                        Text("NO ASSETS STAGED")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.3))
                            .frame(height: 120)
                    } else {
                        ForEach(items) { item in
                            TradeCardTile(item: item, themeColor: themeColor, cardLoader: { id in await services.cardData.loadCard(masterCardId: id) })
                        }
                    }
                }
            }
        }
        .padding(20)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [themeColor.opacity(0.3), .clear],
                            startPoint: alignment == .top ? .bottom : .top,
                            endPoint: alignment == .top ? .top : .bottom
                        ),
                        lineWidth: 1
                    )
            }
        }
        .padding(.horizontal, 16)
    }

    private func centralLinkCore(_ status: TradeStatus) -> some View {
        ZStack {
            // Pulsing Connection Lines
            VStack(spacing: 0) {
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, themeColor.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 2, height: 60)
                
                Circle()
                    .stroke(themeColor.opacity(0.5), lineWidth: 2)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Circle()
                            .fill(themeColor.opacity(0.1))
                        
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(themeColor)
                    }
                
                Rectangle()
                    .fill(LinearGradient(colors: [themeColor.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: 2, height: 60)
            }
            
            // Status Tag
            Text(status.rawValue.uppercased())
                .font(.system(size: 10, weight: .black))
                .tracking(2)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(themeColor, in: Capsule())
                .foregroundStyle(.black)
                .offset(x: 60)
        }
    }

    private func cashTile(_ amount: Double) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "banknote.fill")
                .font(.system(size: 24))
                .foregroundStyle(themeColor)
            
            Text("\(services.priceDisplay.currency.symbol)\(amount, format: .number.precision(.fractionLength(2)))")
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
        }
        .frame(width: 100, height: 140)
        .background(themeColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(themeColor.opacity(0.3), lineWidth: 1))
    }

    @ViewBuilder
    private func actionButtons(_ twi: TradeWithItems) -> some View {
        let status = twi.trade.status

        VStack(spacing: 10) {
            if status == .pending && !isInitiator {
                // Receiver sees: Accept, Counter, Decline
                Button { Task { await performAccept() } } label: {
                    Label("Accept Trade", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TradeActionButtonStyle(color: Color(hex: "52C97C"), isBusy: isMutating))

                NavigationLink(value: SocialDestination.tradeBuilder(
                    receiverID: twi.trade.initiatorID,
                    theirCards: twi.initiatorItems,
                    myCards: twi.receiverItems,
                    existingTradeID: twi.trade.id,
                    originalTrade: twi.trade
                )) {
                    Label("Counter Offer", systemImage: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TradeActionButtonStyle(color: Color(hex: "E8B84B"), isBusy: false))

                Button { showConfirmDecline = true } label: {
                    Label("Decline", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TradeActionButtonStyle(color: Color(hex: "E05252"), isBusy: isMutating))

            } else if status == .pending && isInitiator {
                Button { showConfirmCancel = true } label: {
                    Label("Cancel Trade", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TradeActionButtonStyle(color: Color(hex: "E05252"), isBusy: isMutating))

            } else if status == .countered && !isInitiator {
                // Person who received the counter (original initiator) can accept, counter again, or decline
                Button { Task { await performAccept() } } label: {
                    Label("Accept Counter", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TradeActionButtonStyle(color: Color(hex: "52C97C"), isBusy: isMutating))

                NavigationLink(value: SocialDestination.tradeBuilder(
                    receiverID: twi.trade.receiverID,
                    theirCards: twi.receiverItems,
                    myCards: twi.initiatorItems,
                    existingTradeID: twi.trade.id,
                    originalTrade: twi.trade
                )) {
                    Label("Counter Again", systemImage: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TradeActionButtonStyle(color: Color(hex: "E8B84B"), isBusy: false))

                Button { showConfirmDecline = true } label: {
                    Label("Decline", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TradeActionButtonStyle(color: Color(hex: "E05252"), isBusy: isMutating))

            } else if status == .countered && isInitiator {
                Button { showConfirmCancel = true } label: {
                    Label("Cancel Trade", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TradeActionButtonStyle(color: Color(hex: "E05252"), isBusy: isMutating))

            } else if status == .accepted {
                Button { showConfirmComplete = true } label: {
                    Label("Mark Complete", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TradeActionButtonStyle(color: Color(hex: "52C97C"), isBusy: isMutating))

                Button { showConfirmCancel = true } label: {
                    Label("Cancel Trade", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TradeActionButtonStyle(color: Color(hex: "E05252"), isBusy: isMutating))
            }
        }
        .disabled(isMutating)
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tradeWithItems = try await services.trade.fetchTrade(id: tradeID)
            if let twi = tradeWithItems, let uid = currentUserID {
                let theirID = twi.counterpartID(currentUserID: uid)
                async let theirFetch = services.socialProfile.fetchProfile(id: theirID)
                async let myFetch = services.socialProfile.fetchMyProfile()
                theirProfile = try await theirFetch
                myProfile = try await myFetch
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performAccept() async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await services.trade.acceptTrade(id: tradeID)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performCancel() async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await services.trade.cancelTrade(id: tradeID)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performComplete() async {
        isMutating = true
        defer { isMutating = false }
        do {
            let snapshot = tradeWithItems
            try await services.trade.completeTrade(id: tradeID)
            if let snapshot {
                await applyLocalTradeSettlementIfNeeded(snapshot)
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func valuationSignature(for twi: TradeWithItems) -> String {
        let resolvedUID = currentUserID ?? UUID()
        let myKey = twi.myItems(currentUserID: resolvedUID)
            .map { "\($0.cardID)|\($0.variantKey)|\($0.quantity)" }
            .joined(separator: ";")
        let theirKey = twi.theirItems(currentUserID: resolvedUID)
            .map { "\($0.cardID)|\($0.variantKey)|\($0.quantity)" }
            .joined(separator: ";")
        return "\(twi.id.uuidString)|\(myKey)|\(theirKey)|\(services.priceDisplay.currency.rawValue)|\(services.pricing.usdToGbp)"
    }

    private func refreshTradeValues(for twi: TradeWithItems) async {
        isValuationLoading = true
        defer { isValuationLoading = false }

        let resolvedUID = currentUserID ?? UUID()
        var nextMyValueUSD: Double = 0
        var nextTheirValueUSD: Double = 0

        for item in twi.myItems(currentUserID: resolvedUID) {
            guard let usd = await usdValue(for: item) else { continue }
            nextMyValueUSD += usd * Double(max(item.quantity, 1))
        }
        for item in twi.theirItems(currentUserID: resolvedUID) {
            guard let usd = await usdValue(for: item) else { continue }
            nextTheirValueUSD += usd * Double(max(item.quantity, 1))
        }

        myItemsValueUSD = nextMyValueUSD
        theirItemsValueUSD = nextTheirValueUSD
    }

    private func usdValue(for item: TradeItem) async -> Double? {
        guard let card = await loadCardForValuation(id: item.cardID) else { return nil }
        if let exactVariant = await services.pricing.usdPriceForVariant(for: card, variantKey: item.variantKey) {
            return exactVariant
        }
        return await services.pricing.usdPrice(for: card, printing: item.variantKey)
    }

    private func loadCardForValuation(id: String) async -> Card? {
        if let cached = valuationCardCacheByID[id] {
            return cached
        }
        guard let loaded = await services.cardData.loadCard(masterCardId: id) else {
            return nil
        }
        valuationCardCacheByID[id] = loaded
        return loaded
    }

    private func displayAmountToUSD(_ amount: Double) -> Double {
        switch services.priceDisplay.currency {
        case .usd:
            return amount
        case .gbp:
            let fx = max(services.pricing.usdToGbp, 0.0001)
            return amount / fx
        }
    }

    private func formattedDisplayAmountUSD(_ amountUSD: Double) -> String {
        services.priceDisplay.currency.format(amountUSD: amountUSD, usdToGbp: services.pricing.usdToGbp)
    }

    private func applyLocalTradeSettlementIfNeeded(_ twi: TradeWithItems) async {
        let settlementKey = "trade.local.settlement.\(twi.id.uuidString)"
        guard !UserDefaults.standard.bool(forKey: settlementKey) else { return }
        guard let ledger = services.collectionLedger else { return }
        guard let uid = currentUserID else { return }

        let myItems = twi.myItems(currentUserID: uid)
        let theirItems = twi.theirItems(currentUserID: uid)
        let myCash = twi.myCash(currentUserID: uid)
        let theirCash = twi.theirCash(currentUserID: uid)
        let counterparty = theirProfile?.displayName ?? theirProfile?.username ?? "Trade partner"
        let currencyCode = services.priceDisplay.currency == .gbp ? "GBP" : "USD"
        let reference = "trade-complete-\(twi.id.uuidString)"

        for item in myItems {
            let quantity = max(item.quantity, 1)
            guard let stack = findCardStack(cardID: item.cardID, variantKey: item.variantKey),
                  stack.quantity > 0 else { continue }
            let cardName = await resolvedCardName(for: item.cardID)
            do {
                try ledger.recordSingleCardDisposition(
                    item: stack,
                    kind: .traded,
                    quantity: min(quantity, stack.quantity),
                    currencyCode: currencyCode,
                    cardDisplayName: cardName,
                    unitPrice: nil,
                    counterparty: counterparty,
                    notes: "Trade complete"
                )
            } catch {
                continue
            }
        }

        for item in theirItems {
            let cardName = await resolvedCardName(for: item.cardID)
            do {
                try ledger.recordSingleCardAcquisition(
                    cardID: item.cardID,
                    variantKey: item.variantKey,
                    kind: .trade,
                    quantity: max(item.quantity, 1),
                    currencyCode: currencyCode,
                    cardDisplayName: cardName,
                    unitPrice: nil,
                    packedOpenedFrom: nil,
                    tradeCounterparty: counterparty,
                    tradeGaveAway: nil,
                    giftFrom: nil,
                    boughtFrom: nil
                )
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

        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: settlementKey)
    }

    private func findCardStack(cardID: String, variantKey: String) -> CollectionItem? {
        let descriptor = FetchDescriptor<CollectionItem>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.first(where: {
            $0.cardID == cardID
                && $0.variantKey == variantKey
                && ($0.itemKind == ProductKind.singleCard.rawValue || $0.itemKind == ProductKind.gradedItem.rawValue)
        })
    }

    private func cashLedgerEntryExists(reference: String) -> Bool {
        let descriptor = FetchDescriptor<LedgerLine>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.contains(where: { $0.externalRef == reference })
    }

    private func resolvedCardName(for cardID: String) async -> String {
        if let card = await services.cardData.loadCard(masterCardId: cardID) {
            return card.cardName
        }
        return cardID
    }
}

// MARK: - TradeCardTile

private struct TradeCardTile: View {
    let item: TradeItem
    let themeColor: Color
    let cardLoader: (String) async -> Card?

    @State private var card: Card?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let imageURLString = card?.imageLowSrc {
                    CachedAsyncImage(url: AppConfiguration.imageURL(relativePath: imageURLString)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        shimmer
                    }
                } else {
                    shimmer
                }
            }
            .frame(width: 86, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.4), radius: 6, y: 3)

            VStack(spacing: 2) {
                Text(card?.cardName ?? "Loading...")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                if item.quantity > 1 {
                    Text("×\(item.quantity)")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(themeColor)
                }
            }
        }
        .frame(width: 86)
        .task { card = await cardLoader(item.cardID) }
    }

    private var shimmer: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.05))
    }
}

// MARK: - Button Style

private struct TradeActionButtonStyle: ButtonStyle {
    let color: Color
    let isBusy: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isBusy ? Color.secondary : Color.primary)
            .padding(.vertical, 12)
            .glassCardStyle(cornerRadius: 12, interactive: true)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(color.opacity(configuration.isPressed ? 0.48 : 0.32), lineWidth: 1)
            }
    }
}
