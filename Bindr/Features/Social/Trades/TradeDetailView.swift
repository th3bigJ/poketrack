import SwiftUI
import SwiftData

struct TradeDetailView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Binding var navigationPath: NavigationPath
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
        services.theme.accentColor
    }

    private var toolbarStatusText: String {
        if let tradeWithItems {
            return tradeStatusText(tradeWithItems)
        }
        return trade?.status.displayName ?? "Pending"
    }

    var body: some View {
        ZStack {
            Color(uiColor: colorScheme == .dark ? .black : .systemGroupedBackground)
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
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 12) {
                ChromeGlassCircleButton(accessibilityLabel: "Back") {
                    HapticManager.impact(.light)
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Active Trade")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(.primary)
                    Text(toolbarStatusText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if let trade {
                    TradeStatusBadge(status: trade.status, label: toolbarStatusText)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)
        }
        .task {
            services.setupCollectionLedger(modelContext: modelContext)
            await refresh()
        }
        .task(id: tradeWithItems?.trade.status) {
            await pollAcceptedTradeUntilComplete()
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
            Button("Confirm") { Task { await performComplete() } }
            Button("Not Yet", role: .cancel) { }
        } message: {
            Text("Use this only after your side of the exchange is done. Your collection updates when you confirm. The trade completes after both traders confirm.")
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
                VStack(alignment: .leading, spacing: 16) {
                    tradeSummaryCard(twi, myTotalUSD: myTotalUSD, theirTotalUSD: theirTotalUSD)

                    tradeSection(
                        title: "You give",
                        detail: tradeSideDetail(items: myItems, cash: myCash),
                        profile: myProfile,
                        items: myItems,
                        cash: myCash,
                        totalValueUSD: myTotalUSD,
                        tint: BindrPalette.alertRed,
                        emptyText: "Nothing from your side yet."
                    )

                    tradeSection(
                        title: "You receive",
                        detail: tradeSideDetail(items: theirItems, cash: theirCash),
                        profile: theirProfile,
                        items: theirItems,
                        cash: theirCash,
                        totalValueUSD: theirTotalUSD,
                        tint: BindrPalette.ownedGreen,
                        emptyText: "Nothing from their side yet."
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 18)
            }
            
            actionFooter(twi)
        }
        .task(id: valuationSignature(for: twi)) {
            await refreshTradeValues(for: twi)
        }
    }

    private func tradeSummaryCard(_ twi: TradeWithItems, myTotalUSD: Double, theirTotalUSD: Double) -> some View {
        let resolvedUID = currentUserID ?? UUID()
        let iConfirmedCompletion = twi.myCompleted(currentUserID: resolvedUID)
        let theyConfirmedCompletion = twi.theirCompleted(currentUserID: resolvedUID)
        let partnerName = theirProfile?.displayName ?? theirProfile.map { "@\($0.username)" } ?? "Trade partner"

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                if let theirProfile {
                    ProfileAvatarView(profile: theirProfile, size: 46)
                } else {
                    Circle()
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .frame(width: 46, height: 46)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(partnerName)
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(statusHelpText(twi))
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer(minLength: 0)
            }
            
            HStack(spacing: 10) {
                valuePill(title: "You give", amountUSD: myTotalUSD, tint: BindrPalette.alertRed)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.7))
                valuePill(title: "You receive", amountUSD: theirTotalUSD, tint: BindrPalette.ownedGreen)
            }
            
            if twi.trade.status == .accepted {
                HStack {
                    completionStep(title: "You", isComplete: iConfirmedCompletion)
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(height: 1)
                    completionStep(title: "Them", isComplete: theyConfirmedCompletion)
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .glassCardStyle(cornerRadius: 18, interactive: false)
    }

    private func valuePill(title: String, amountUSD: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            
            if isValuationLoading {
                ProgressView()
                    .tint(tint)
                    .scaleEffect(0.8)
                    .frame(height: 18, alignment: .leading)
            } else {
                Text(formattedDisplayAmountUSD(amountUSD))
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(colorScheme == .dark ? 0.16 : 0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }

    private func completionStep(title: String, isComplete: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isComplete ? BindrPalette.ownedGreen : Color.secondary.opacity(0.55))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isComplete ? .primary : .secondary)
        }
    }

    private func tradeSection(
        title: String,
        detail: String,
        profile: SocialProfile?,
        items: [TradeItem],
        cash: Double,
        totalValueUSD: Double,
        tint: Color,
        emptyText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 3) {
                    Text(isValuationLoading ? "Checking..." : formattedDisplayAmountUSD(totalValueUSD))
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(tint)
                    if let profile {
                        Text(profile.displayName ?? "@\(profile.username)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if cash > 0 {
                        cashTile(cash)
                    }
                    
                    if items.isEmpty && cash == 0 {
                        emptyTradeSide(text: emptyText)
                    } else {
                        ForEach(items) { item in
                            TradeCardTile(item: item, themeColor: tint, cardLoader: { id in await services.cardData.loadCard(masterCardId: id) })
                        }
                    }
                }
            }
        }
        .padding(16)
        .glassCardStyle(cornerRadius: 18, interactive: false)
    }

    private func emptyTradeSide(text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 190, height: 118)
            .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func actionFooter(_ twi: TradeWithItems) -> some View {
        VStack(spacing: 12) {
            actionButtons(twi)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 1)
                }
        }
    }

    private func tradeSideDetail(items: [TradeItem], cash: Double) -> String {
        let quantity = items.reduce(0) { $0 + max($1.quantity, 1) }
        var parts: [String] = []
        if quantity > 0 {
            parts.append("\(quantity) card\(quantity == 1 ? "" : "s")")
        }
        if cash > 0 {
            parts.append("\(services.priceDisplay.currency.symbol)\(String(format: "%.2f", cash))")
        }
        return parts.isEmpty ? "No items" : parts.joined(separator: " + ")
    }

    private func statusHelpText(_ twi: TradeWithItems) -> String {
        guard let uid = currentUserID else { return "Review the cards and values before taking action." }
        switch twi.trade.status {
        case .pending:
            return twi.needsResponse(from: uid) ? "This offer is waiting for your response." : "This offer is waiting for their response."
        case .countered:
            return twi.needsResponse(from: uid) ? "They sent a counter offer. Review it before accepting." : "Your counter offer is waiting for them."
        case .accepted:
            if twi.myCompleted(currentUserID: uid) {
                return "You confirmed your side. The trade completes once they confirm."
            }
            if twi.theirCompleted(currentUserID: uid) {
                return "They confirmed their side. Confirm yours when the exchange is done."
            }
            return "Both sides accepted. Confirm your side once the real-world exchange is done."
        case .complete:
            return "This trade is complete and your records have been updated where applicable."
        case .cancelled:
            return "This trade has been closed."
        }
    }

    private func cashTile(_ amount: Double) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "banknote.fill")
                .font(.system(size: 24))
                .foregroundStyle(themeColor)
            
            Text("\(services.priceDisplay.currency.symbol)\(String(format: "%.2f", amount))")
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .frame(width: 100, height: 140)
        .background(themeColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(themeColor.opacity(0.3), lineWidth: 1))
    }

    @ViewBuilder
    private func actionButtons(_ twi: TradeWithItems) -> some View {
        let status = twi.trade.status
        let resolvedUID = currentUserID ?? UUID()
        let iConfirmedCompletion = twi.myCompleted(currentUserID: resolvedUID)
        let theyConfirmedCompletion = twi.theirCompleted(currentUserID: resolvedUID)

        VStack(spacing: 12) {
            if status == .pending || status == .countered {
                if !isInitiator {
                    // RECEIVER ACTION MENU
                    TradeActionMenu(
                        label: "Respond...",
                        icon: "arrow.uturn.right.circle.fill",
                        color: themeColor,
                        isBusy: isMutating,
                        menuItems: [
                            MenuItem(
                                label: "Accept Trade",
                                subLabel: "Add cards to collection",
                                icon: "checkmark.circle.fill",
                                color: Color(hex: "52C97C"),
                                action: { Task { await performAccept() } }
                            ),
                            MenuItem(
                                label: "Counter Offer",
                                subLabel: "Edit this trade offer",
                                icon: "arrow.left.arrow.right.circle.fill",
                                color: Color(hex: "E8B84B"),
                                action: { 
                                    navigationPath.append(SocialDestination.tradeBuilder(
                                        receiverID: twi.trade.initiatorID == resolvedUID ? twi.trade.receiverID : twi.trade.initiatorID,
                                        theirCards: twi.theirItems(currentUserID: resolvedUID),
                                        myCards: twi.myItems(currentUserID: resolvedUID),
                                        existingTradeID: twi.trade.id,
                                        originalTrade: twi.trade
                                    ))
                                }
                            ),
                            MenuItem(
                                label: "Decline",
                                subLabel: "Close this trade session",
                                icon: "xmark.circle.fill",
                                color: Color(hex: "E05252"),
                                action: { showConfirmDecline = true }
                            )
                        ]
                    )
                } else {
                    // SENDER STANDALONE CANCEL
                    Button { showConfirmCancel = true } label: {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                            Text("Cancel Trade")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .foregroundStyle(Color(hex: "E05252"))
                        .glassCardStyle(cornerRadius: 18, interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            } else if status == .accepted {
                if iConfirmedCompletion {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: theyConfirmedCompletion ? "checkmark.circle.fill" : "clock.fill")
                            Text(theyConfirmedCompletion ? "Finalizing trade" : "Waiting for their confirmation")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .foregroundStyle(theyConfirmedCompletion ? Color(hex: "52C97C") : Color(hex: "E8B84B"))
                        .glassCardStyle(cornerRadius: 18, interactive: true)

                        if !theyConfirmedCompletion {
                            Text("Your collection has been updated. The trade will complete once they confirm theirs.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        Button { showConfirmComplete = true } label: {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                Text(theyConfirmedCompletion ? "Confirm & Complete" : "Confirm My Side")
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .foregroundStyle(Color(hex: "52C97C"))
                            .glassCardStyle(cornerRadius: 18, interactive: true)
                        }
                        .buttonStyle(.plain)

                        Button { showConfirmCancel = true } label: {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 20))
                                .frame(width: 56, height: 56)
                                .foregroundStyle(Color(hex: "E05252"))
                                .glassCardStyle(cornerRadius: 18, interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .disabled(isMutating)
    }

    private func tradeStatusText(_ twi: TradeWithItems) -> String {
        guard twi.trade.status == .accepted, let uid = currentUserID else {
            return twi.trade.status.displayName
        }
        if twi.myCompleted(currentUserID: uid) {
            return "Waiting for them"
        }
        if twi.theirCompleted(currentUserID: uid) {
            return "They confirmed"
        }
        return twi.trade.status.displayName
    }

    private struct MenuItem: Identifiable {
        let id = UUID()
        let label: String
        let subLabel: String?
        let icon: String
        let color: Color
        let action: () -> Void
    }

    private struct TradeActionMenu: View {
        let label: String
        let icon: String
        let color: Color
        let isBusy: Bool
        let menuItems: [MenuItem]

        @State private var isExpanded = false
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            VStack(spacing: 12) {
                if isExpanded {
                    VStack(spacing: 0) {
                        ForEach(menuItems) { item in
                            Button {
                                Haptics.selectionChanged()
                                item.action()
                                withAnimation { isExpanded = false }
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: item.icon)
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(item.color)
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.label)
                                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.primary)
                                        if let sub = item.subLabel {
                                            Text(sub)
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            if item.id != menuItems.last?.id {
                                Divider().padding(.horizontal, 20).opacity(0.1)
                            }
                        }
                    }
                    .glassCardStyle(cornerRadius: 24, interactive: true)
                    .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity).combined(with: .move(edge: .bottom)))
                }

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                    Haptics.lightImpact()
                } label: {
                    HStack {
                        Image(systemName: icon)
                        Text(label)
                            .fontWeight(.bold)
                        Spacer()
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .bold))
                            .opacity(0.4)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .foregroundStyle(color)
                    .glassCardStyle(cornerRadius: 18, interactive: true)
                }
                .buttonStyle(.plain)
            }
            .background {
                if isExpanded {
                    Color.black.opacity(0.001)
                        .onTapGesture {
                            withAnimation { isExpanded = false }
                        }
                        .frame(width: 1000, height: 2000)
                        .offset(y: -500)
                }
            }
        }
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

                // Apply local settlement only after this user confirms their side (UserDefaults prevents double-apply).
                if twi.shouldSettleCollection(for: uid) {
                    await applyLocalTradeSettlementIfNeeded(twi)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pollAcceptedTradeUntilComplete() async {
        guard tradeWithItems?.trade.status == .accepted else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard tradeWithItems?.trade.status == .accepted else { return }
            await refresh()
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
            try await services.trade.completeTrade(id: tradeID)
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
        guard let uid = currentUserID else { return }
        let settlementKey = "trade.local.settlement.\(uid.uuidString).\(twi.id.uuidString)"

        let myItems = twi.myItems(currentUserID: uid)
        let theirItems = twi.theirItems(currentUserID: uid)
        let myCash = twi.myCash(currentUserID: uid)
        let theirCash = twi.theirCash(currentUserID: uid)
        let counterparty = theirProfile?.displayName ?? theirProfile?.username ?? "Trade partner"
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
        let descriptor = FetchDescriptor<CollectionItem>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        let matchingStacks = all.filter {
            $0.cardID == cardID
                && ($0.itemKind == ProductKind.singleCard.rawValue || $0.itemKind == ProductKind.gradedItem.rawValue)
        }
        return matchingStacks.first(where: { $0.variantKey == variantKey }) ?? matchingStacks.first
    }

    private func cashLedgerEntryExists(reference: String) -> Bool {
        let descriptor = FetchDescriptor<LedgerLine>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
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

// MARK: - TradeCardTile

private struct TradeCardTile: View {
    let item: TradeItem
    let themeColor: Color
    let cardLoader: (String) async -> Card?

    @State private var card: Card?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let imageURLString = card?.displayImageSrc {
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
                    .foregroundStyle(.primary)
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
