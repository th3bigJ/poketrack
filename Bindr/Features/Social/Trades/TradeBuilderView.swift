import SwiftUI
import SwiftData

struct TradeBuilderView: View {
    private enum CashField: Hashable {
        case mine
        case theirs
    }

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Query private var collectionItems: [CollectionItem]

    let receiverID: UUID
    let initialTheirCards: [TradeItem]
    let initialMyCards: [TradeItem]
    let existingTradeID: UUID?
    let originalTrade: Trade?
    var onComplete: (() -> Void)? = nil

    @State private var theirCards: [NewTradeItemInput]
    @State private var myCards: [NewTradeItemInput]
    @State private var cashInitiatorText: String = ""
    @State private var cashReceiverText: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var isMyCardPickerPresented = false
    @State private var isTheirCardPickerPresented = false
    @State private var receiverProfile: SocialProfile?
    @State private var receiverCollectionCardIDs: Set<String> = []
    @State private var myCollectionCardIDs: Set<String> = []
    @State private var isOwnershipLoading = true
    @State private var cardNameByID: [String: String] = [:]
    @State private var valuationCardCacheByID: [String: Card] = [:]
    @State private var myCardsValueUSD: Double = 0
    @State private var theirCardsValueUSD: Double = 0
    @State private var isValuationLoading = false
    @FocusState private var focusedCashField: CashField?

    init(
        receiverID: UUID,
        initialTheirCards: [TradeItem],
        initialMyCards: [TradeItem],
        existingTradeID: UUID? = nil,
        originalTrade: Trade? = nil,
        onComplete: (() -> Void)? = nil
    ) {
        self.receiverID = receiverID
        self.initialTheirCards = initialTheirCards
        self.initialMyCards = initialMyCards
        self.existingTradeID = existingTradeID
        self.originalTrade = originalTrade
        self.onComplete = onComplete
        self._theirCards = State(initialValue: initialTheirCards.map {
            NewTradeItemInput(cardID: $0.cardID, variantKey: $0.variantKey, quantity: $0.quantity)
        })
        self._myCards = State(initialValue: initialMyCards.map {
            NewTradeItemInput(cardID: $0.cardID, variantKey: $0.variantKey, quantity: $0.quantity)
        })
        
        if let originalTrade {
            if originalTrade.initiatorID == receiverID {
                self._cashInitiatorText = State(initialValue: originalTrade.cashReceiver > 0 ? String(format: "%.2f", originalTrade.cashReceiver) : "")
                self._cashReceiverText = State(initialValue: originalTrade.cashInitiator > 0 ? String(format: "%.2f", originalTrade.cashInitiator) : "")
            } else {
                self._cashInitiatorText = State(initialValue: originalTrade.cashInitiator > 0 ? String(format: "%.2f", originalTrade.cashInitiator) : "")
                self._cashReceiverText = State(initialValue: originalTrade.cashReceiver > 0 ? String(format: "%.2f", originalTrade.cashReceiver) : "")
            }
        } else {
            self._cashInitiatorText = State(initialValue: "")
            self._cashReceiverText = State(initialValue: "")
        }
    }

    private var isCounterFlow: Bool { existingTradeID != nil }
    private var myUnavailableCards: [NewTradeItemInput] {
        guard !isOwnershipLoading else { return [] }
        return myCards.filter { !myCollectionCardIDs.contains($0.cardID) }
    }
    private var theirUnavailableCards: [NewTradeItemInput] {
        guard !isOwnershipLoading else { return [] }
        return theirCards.filter { !receiverCollectionCardIDs.contains($0.cardID) }
    }
    private var hasUnavailableCards: Bool {
        !myUnavailableCards.isEmpty || !theirUnavailableCards.isEmpty
    }
    private var unavailableCardNameLookupSignature: String {
        (myUnavailableCards.map(\.cardID) + theirUnavailableCards.map(\.cardID))
            .sorted()
            .joined(separator: "|")
    }
    private var valuationSignature: String {
        let myKey = myCards
            .map { "\($0.cardID)|\($0.variantKey)|\($0.quantity)" }
            .sorted()
            .joined(separator: ";")
        let theirKey = theirCards
            .map { "\($0.cardID)|\($0.variantKey)|\($0.quantity)" }
            .sorted()
            .joined(separator: ";")
        return "\(myKey)__\(theirKey)__\(services.priceDisplay.currency.rawValue)__\(services.pricing.usdToGbp)"
    }
    private var localCollectionSignature: String {
        localCollectionCardIDs.sorted().joined(separator: "|")
    }
    private var cashInitiatorDisplayAmount: Double {
        parsedCash(cashInitiatorText)
    }
    private var cashReceiverDisplayAmount: Double {
        parsedCash(cashReceiverText)
    }
    private var cashInitiatorUSD: Double {
        displayAmountToUSD(cashInitiatorDisplayAmount)
    }
    private var cashReceiverUSD: Double {
        displayAmountToUSD(cashReceiverDisplayAmount)
    }
    private var mySideTotalUSD: Double {
        myCardsValueUSD + cashInitiatorUSD
    }
    private var theirSideTotalUSD: Double {
        theirCardsValueUSD + cashReceiverUSD
    }
    private var tradeBalanceUSD: Double {
        mySideTotalUSD - theirSideTotalUSD
    }
    private var isTradeEven: Bool {
        abs(tradeBalanceUSD) < 0.01
    }

    var body: some View {
        List {
            theirSideSection
            mySideSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(isCounterFlow ? "Counter Offer" : "New Trade")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isCounterFlow ? "Send Counter" : "Offer Trade") {
                    Task { await submit() }
                }
                .tint(.primary)
                .disabled(
                    isSubmitting
                    || (theirCards.isEmpty && myCards.isEmpty)
                    || isOwnershipLoading
                    || hasUnavailableCards
                )
                .overlay {
                    if isSubmitting { ProgressView().scaleEffect(0.7) }
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedCashField = nil
                }
            }
        }
        .sheet(isPresented: $isTheirCardPickerPresented) {
            TradeCardPickerView(
                ownerUserID: receiverID,
                navigationTitle: "Pick Their Cards"
            ) { selected in
                for item in selected {
                    if !theirCards.contains(where: { $0.cardID == item.cardID && $0.variantKey == item.variantKey }) {
                        theirCards.append(item)
                    }
                }
            }
            .environment(services)
        }
        .sheet(isPresented: $isMyCardPickerPresented) {
            TradeCardPickerView(
                ownerUserID: currentUserID,
                navigationTitle: "Pick My Cards"
            ) { selected in
                for item in selected {
                    if !myCards.contains(where: { $0.cardID == item.cardID && $0.variantKey == item.variantKey }) {
                        myCards.append(item)
                    }
                }
            }
            .environment(services)
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
        .task {
            isOwnershipLoading = true
            defer { isOwnershipLoading = false }
            receiverProfile = try? await services.socialProfile.fetchProfile(id: receiverID)
            async let theirTradeListTask = services.socialCardLibrary.fetchTradeListCardIDs(for: receiverID)
            receiverCollectionCardIDs = Set<String>((try? await theirTradeListTask) ?? [])
            myCollectionCardIDs = localCollectionCardIDs
        }
        .task(id: unavailableCardNameLookupSignature) {
            await cacheCardNamesForUnavailableCards()
        }
        .task(id: valuationSignature) {
            await refreshTradeValues()
        }
        .task(id: localCollectionSignature) {
            guard !isOwnershipLoading else { return }
            myCollectionCardIDs = localCollectionCardIDs
        }
    }

    private var theirSideSection: some View {
        Section {
            if theirCards.isEmpty {
                Text("No cards selected")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(theirCards) { item in
                    BuilderCardRow(item: item, cardLoader: { id in await services.cardData.loadCard(masterCardId: id) })
                }
                .onDelete(perform: isCounterFlow ? nil : { indices in
                    theirCards.remove(atOffsets: indices)
                })
            }
            if !isCounterFlow {
                Button {
                    isTheirCardPickerPresented = true
                } label: {
                    Label("Add Cards", systemImage: "plus.circle")
                        .font(.system(size: 14))
                }
            }

            HStack {
                Text("They add cash")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                Spacer()
                if isCounterFlow {
                    Text("\(services.priceDisplay.currency.symbol)\(cashReceiverText.isEmpty ? "0.00" : cashReceiverText)")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 4) {
                        Text(services.priceDisplay.currency.symbol)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $cashReceiverText)
                            .keyboardType(.decimalPad)
                            .focused($focusedCashField, equals: .theirs)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 14))
                            .frame(width: 90)
                    }
                }
            }

            HStack {
                Text("Their total")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if isValuationLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text(formattedDisplayAmountUSD(theirSideTotalUSD))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                }
            }
        } header: {
            Text(receiverProfile.map { "Their Side (@\($0.username))" } ?? "Their Side")
        } footer: {
            if theirUnavailableCards.isEmpty {
                Text("Cards you are requesting from them. Total includes cards + cash.")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Warning: They don't currently have \(theirUnavailableCards.count) selected \(theirUnavailableCards.count == 1 ? "card" : "cards") in their trade list.")
                        .foregroundStyle(.red)
                    Text(unavailableNamesText(for: theirUnavailableCards))
                        .foregroundStyle(.red)
                    Button("Remove unavailable cards") {
                        removeUnavailableFromTheirSide()
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
                }
            }
        }
    }

    private var mySideSection: some View {
        Section {
            if myCards.isEmpty {
                Text("No cards selected")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(myCards) { item in
                    BuilderCardRow(item: item, cardLoader: { id in await services.cardData.loadCard(masterCardId: id) })
                }
                .onDelete { indices in
                    myCards.remove(atOffsets: indices)
                }
            }
            Button {
                isMyCardPickerPresented = true
            } label: {
                Label("Add Cards", systemImage: "plus.circle")
                    .font(.system(size: 14))
            }

            HStack {
                Text("I add cash")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                Spacer()
                HStack(spacing: 4) {
                    Text(services.priceDisplay.currency.symbol)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $cashInitiatorText)
                        .keyboardType(.decimalPad)
                        .focused($focusedCashField, equals: .mine)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 14))
                        .frame(width: 90)
                }
            }

            HStack {
                Text("My total")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if isValuationLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text(formattedDisplayAmountUSD(mySideTotalUSD))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                }
            }
        } header: {
            Text("My Side")
        } footer: {
            if myUnavailableCards.isEmpty {
                Text("Cards you are offering in return. Total includes cards + cash.")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Warning: You don't currently have \(myUnavailableCards.count) selected \(myUnavailableCards.count == 1 ? "card" : "cards") in your collection.")
                        .foregroundStyle(.red)
                    Text(unavailableNamesText(for: myUnavailableCards))
                        .foregroundStyle(.red)
                    Button("Remove unavailable cards") {
                        removeUnavailableFromMySide()
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
                }
            }
        }
    }


    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            focusedCashField = nil
            let cashMe = parsedCash(cashInitiatorText)
            let cashThem = parsedCash(cashReceiverText)

            if isCounterFlow, let existingTradeID, let originalTrade {
                _ = try await services.trade.counterTrade(
                    tradeID: existingTradeID,
                    originalTrade: originalTrade,
                    newInitiatorCards: myCards,
                    newReceiverCards: theirCards,
                    cashInitiator: cashMe,
                    cashReceiver: cashThem
                )
            } else {
                _ = try await services.trade.createTrade(
                    receiverID: receiverID,
                    initiatorCards: myCards,
                    receiverCards: theirCards,
                    cashInitiator: cashMe,
                    cashReceiver: cashThem
                )
            }
            onComplete?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var currentUserID: UUID {
        if case .signedIn(let id, _) = services.socialAuth.authState {
            return id
        }
        return UUID()
    }

    private var localCollectionCardIDs: Set<String> {
        Set<String>(collectionItems.compactMap { item in
            guard item.quantity > 0, !item.cardID.isEmpty else { return nil }
            return item.cardID
        })
    }

    private func removeUnavailableFromMySide() {
        guard !isOwnershipLoading else { return }
        myCards.removeAll { !myCollectionCardIDs.contains($0.cardID) }
    }

    private func removeUnavailableFromTheirSide() {
        guard !isOwnershipLoading else { return }
        theirCards.removeAll { !receiverCollectionCardIDs.contains($0.cardID) }
    }

    private func unavailableNamesText(for items: [NewTradeItemInput]) -> String {
        let uniqueCardIDs = Array(Set(items.map(\.cardID))).sorted()
        let names = uniqueCardIDs.map { cardNameByID[$0] ?? $0 }
        return "Unavailable: \(names.joined(separator: ", "))"
    }

    private func cacheCardNamesForUnavailableCards() async {
        let ids = Array(Set(myUnavailableCards.map(\.cardID) + theirUnavailableCards.map(\.cardID)))
        for cardID in ids where cardNameByID[cardID] == nil {
            if let loaded = await services.cardData.loadCard(masterCardId: cardID) {
                cardNameByID[cardID] = loaded.cardName
            } else {
                cardNameByID[cardID] = cardID
            }
        }
    }

    private func refreshTradeValues() async {
        isValuationLoading = true
        defer { isValuationLoading = false }

        var nextMyValueUSD: Double = 0
        var nextTheirValueUSD: Double = 0

        for item in myCards {
            guard let usd = await usdValue(for: item) else { continue }
            nextMyValueUSD += usd * Double(max(item.quantity, 1))
        }
        for item in theirCards {
            guard let usd = await usdValue(for: item) else { continue }
            nextTheirValueUSD += usd * Double(max(item.quantity, 1))
        }

        myCardsValueUSD = nextMyValueUSD
        theirCardsValueUSD = nextTheirValueUSD
    }

    private func usdValue(for item: NewTradeItemInput) async -> Double? {
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

    private func parsedCash(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
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

}

// MARK: - BuilderCardRow

struct BuilderCardRow: View {
    @Environment(AppServices.self) private var services

    let item: NewTradeItemInput
    let cardLoader: (String) async -> Card?

    @State private var card: Card?
    @State private var rowValueUSD: Double?

    var body: some View {
        HStack(spacing: 10) {
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
            .frame(width: 36, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(card?.cardName ?? item.cardID)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                if item.variantKey != "normal" {
                    Text(item.variantKey)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if item.quantity > 1 {
                    Text("×\(item.quantity)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: "E8B84B"))
                }
            }

            Spacer(minLength: 8)

            Text(rowValueText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .task(id: valueLookupSignature) {
            if card == nil {
                card = await cardLoader(item.cardID)
            }
            await refreshRowValue()
        }
    }

    private var shimmer: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.white.opacity(0.05))
    }

    private var valueLookupSignature: String {
        "\(item.cardID)|\(item.variantKey)|\(item.quantity)|\(services.priceDisplay.currency.rawValue)|\(services.pricing.usdToGbp)"
    }

    private var rowValueText: String {
        guard let rowValueUSD else { return "—" }
        return services.priceDisplay.currency.format(amountUSD: rowValueUSD, usdToGbp: services.pricing.usdToGbp)
    }

    private func refreshRowValue() async {
        guard let card else {
            rowValueUSD = nil
            return
        }
        let variantUSD = await services.pricing.usdPriceForVariant(for: card, variantKey: item.variantKey)
        let unitUSD: Double?
        if let variantUSD {
            unitUSD = variantUSD
        } else {
            unitUSD = await services.pricing.usdPrice(for: card, printing: item.variantKey)
        }
        if let unitUSD {
            rowValueUSD = unitUSD * Double(max(item.quantity, 1))
        } else {
            rowValueUSD = nil
        }
    }
}

// MARK: - TradeCardPickerView

struct TradeCardPickerView: View {
    private enum CardSource: String, CaseIterable, Identifiable {
        case tradeList
        case collection

        var id: String { rawValue }

        var title: String {
            switch self {
            case .tradeList: return "Trade List"
            case .collection: return "Collection"
            }
        }
    }

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CollectionItem.dateAcquired, order: .reverse) private var collectionItems: [CollectionItem]
    @Query(sort: \TradeListItem.dateAdded, order: .reverse) private var tradeListItems: [TradeListItem]

    let ownerUserID: UUID
    let navigationTitle: String
    let onConfirm: ([NewTradeItemInput]) -> Void

    @State private var collectionCardIDs: [String] = []
    @State private var selectedCardIDs: Set<String> = []
    @State private var cardNameByID: [String: String] = [:]
    @State private var cardCacheByID: [String: Card] = [:]
    @State private var isLoading = false
    @State private var isIndexingNames = false
    @State private var searchText = ""
    @State private var visibleCount = 60
    @State private var selectedSource: CardSource = .tradeList

    private let pageSize = 60
    private var isCurrentUserPicker: Bool { ownerUserID == currentUserID }
    private var availableSources: [CardSource] { isCurrentUserPicker ? CardSource.allCases : [.tradeList] }

    private var filteredCardIDs: [String] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return collectionCardIDs }
        let query = trimmed.localizedLowercase
        return collectionCardIDs.filter { cardID in
            guard let cardName = cardNameByID[cardID] else { return false }
            return cardName.localizedLowercase.contains(query)
        }
    }

    private var visibleCardIDs: [String] {
        Array(filteredCardIDs.prefix(visibleCount))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !collectionCardIDs.isEmpty || availableSources.count > 1 {
                    sourcePicker
                        .padding(.horizontal, 12)
                        .padding(.top, 12)

                    searchField
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                }

                Group {
                    if isLoading {
                        ProgressView("Loading \(selectedSource.title.lowercased())...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if collectionCardIDs.isEmpty {
                        ContentUnavailableView(
                            emptyTitle,
                            systemImage: "rectangle.stack",
                            description: Text(emptyDescription)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        cardGrid
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selectedCardIDs.count))") {
                        let selected = selectedCardIDs.map { NewTradeItemInput(cardID: $0) }
                        onConfirm(selected)
                        dismiss()
                    }
                    .disabled(selectedCardIDs.isEmpty)
                }
            }
        }
        .tint(.primary)
        .task { await loadCollection() }
        .onChange(of: selectedSource) { _, _ in
            selectedCardIDs = []
            searchText = ""
            visibleCount = pageSize
            Task { await loadCollection() }
        }
        .onChange(of: searchText) { _, _ in
            visibleCount = pageSize
            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            Task { await indexCardNamesIfNeeded() }
        }
    }

    private var currentUserID: UUID {
        if case .signedIn(let id, _) = services.socialAuth.authState {
            return id
        }
        return UUID()
    }

    private var sourcePicker: some View {
        Picker("Card source", selection: $selectedSource) {
            ForEach(availableSources) { source in
                Text(source.title).tag(source)
            }
        }
        .pickerStyle(.segmented)
    }

    private var emptyTitle: String {
        switch selectedSource {
        case .tradeList: return "Trade List Empty"
        case .collection: return "Collection Empty"
        }
    }

    private var emptyDescription: String {
        if selectedSource == .tradeList {
            return isCurrentUserPicker
                ? "Add cards to your trade list to offer them quickly."
                : "This friend has not added any cards to their trade list."
        }
        return isCurrentUserPicker
            ? "Add cards to your collection to offer them in a trade."
            : "This friend has not added any cards to their trade list."
    }

    private var cardGrid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(visibleCardIDs, id: \.self) { cardID in
                    SelectablePickerCard(
                        cardID: cardID,
                        isSelected: selectedCardIDs.contains(cardID),
                        cachedCard: cardCacheByID[cardID],
                        cardLoader: { id in await loadCard(for: id) }
                    ) {
                        if selectedCardIDs.contains(cardID) {
                            selectedCardIDs.remove(cardID)
                        } else {
                            selectedCardIDs.insert(cardID)
                        }
                    }
                    .onAppear {
                        loadMoreCardsIfNeeded(currentCardID: cardID)
                    }
                }
            }
            .padding(12)

            if visibleCount < filteredCardIDs.count {
                ProgressView()
                    .padding(.bottom, 12)
            } else if isIndexingNames {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Indexing card names...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 12)
            }
        }
    }

    private func loadCollection() async {
        isLoading = true
        defer { isLoading = false }
        if isCurrentUserPicker {
            switch selectedSource {
            case .tradeList:
                collectionCardIDs = dedupeCardIDs(tradeListItems.map(\.cardID))
            case .collection:
                collectionCardIDs = dedupeCardIDs(collectionItems.compactMap { item in
                    guard item.quantity > 0 else { return nil }
                    return item.cardID
                })
            }
        } else {
            collectionCardIDs = (try? await services.socialCardLibrary.fetchTradeListCardIDs(for: ownerUserID)) ?? []
        }
    }

    private func dedupeCardIDs(_ ids: [String]) -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []
        for id in ids where !id.isEmpty {
            if seen.insert(id).inserted {
                ordered.append(id)
            }
        }
        return ordered
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.5))
            TextField("Search cards...", text: $searchText)
                .font(.system(size: 13))
                .foregroundStyle(Color.primary)
                .tint(Color(hex: "E8B84B"))
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
        }
    }

    private func loadMoreCardsIfNeeded(currentCardID: String) {
        guard visibleCount < filteredCardIDs.count else { return }
        let triggerIndex = max(visibleCount - 15, 0)
        guard filteredCardIDs.indices.contains(triggerIndex) else { return }
        if filteredCardIDs[triggerIndex] == currentCardID {
            visibleCount = min(visibleCount + pageSize, filteredCardIDs.count)
        }
    }

    private func loadCard(for cardID: String) async -> Card? {
        if let cached = cardCacheByID[cardID] {
            return cached
        }
        guard let loaded = await services.cardData.loadCard(masterCardId: cardID) else {
            return nil
        }
        cardCacheByID[cardID] = loaded
        cardNameByID[cardID] = loaded.cardName
        return loaded
    }

    private func indexCardNamesIfNeeded() async {
        let missingIDs = collectionCardIDs.filter { cardNameByID[$0] == nil }
        guard !missingIDs.isEmpty else { return }
        isIndexingNames = true
        defer { isIndexingNames = false }

        for cardID in missingIDs {
            guard !Task.isCancelled else { return }
            _ = await loadCard(for: cardID)
        }
    }
}

private struct SelectablePickerCard: View {
    let cardID: String
    let isSelected: Bool
    let cachedCard: Card?
    let cardLoader: (String) async -> Card?
    let onTap: () -> Void

    @State private var card: Card?

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    if let imageURLString = card?.displayImageSrc {
                        CachedAsyncImage(url: AppConfiguration.imageURL(relativePath: imageURLString)) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05))
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05))
                    }
                }
                .aspectRatio(5/7, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(hex: "E8B84B"), lineWidth: 2.5)
                    }
                }

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isSelected ? Color(hex: "E8B84B") : Color.white.opacity(0.6))
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .padding(4)
            }
        }
        .buttonStyle(.plain)
        .task {
            if let cachedCard {
                card = cachedCard
            } else {
                card = await cardLoader(cardID)
            }
        }
    }
}
