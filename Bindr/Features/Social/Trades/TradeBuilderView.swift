import SwiftUI

struct TradeBuilderView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

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
    @State private var receiverProfile: SocialProfile?

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
    }

    private var isCounterFlow: Bool { existingTradeID != nil }

    var body: some View {
        List {
            theirSideSection
            mySideSection
            cashSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(isCounterFlow ? "Counter Offer" : "New Trade")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isCounterFlow ? "Send Counter" : "Send Trade") {
                    Task { await submit() }
                }
                .disabled(isSubmitting || (theirCards.isEmpty && myCards.isEmpty))
                .overlay {
                    if isSubmitting { ProgressView().scaleEffect(0.7) }
                }
            }
        }
        .sheet(isPresented: $isMyCardPickerPresented) {
            TradeCardPickerView { selected in
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
            receiverProfile = try? await services.socialProfile.fetchProfile(id: receiverID)
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
            }
        } header: {
            Text(receiverProfile.map { "Their Side (@\($0.username))" } ?? "Their Side")
        } footer: {
            Text("Cards you are requesting from them.")
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
                Label("Add Cards from My Collection", systemImage: "plus.circle")
                    .font(.system(size: 14))
            }
        } header: {
            Text("My Side")
        } footer: {
            Text("Cards you are offering in return.")
        }
    }

    private var cashSection: some View {
        Section {
            HStack {
                Text("You add")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                Spacer()
                HStack(spacing: 4) {
                    Text("£")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $cashInitiatorText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 14))
                        .frame(width: 80)
                }
            }
            HStack {
                Text("They add")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                Spacer()
                HStack(spacing: 4) {
                    Text("£")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $cashReceiverText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 14))
                        .frame(width: 80)
                }
            }
        } header: {
            Text("Cash (Optional)")
        } footer: {
            Text("Add cash to either side to sweeten the deal.")
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let cashMe = Double(cashInitiatorText.replacingOccurrences(of: ",", with: ".")) ?? 0
            let cashThem = Double(cashReceiverText.replacingOccurrences(of: ",", with: ".")) ?? 0

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
}

// MARK: - BuilderCardRow

private struct BuilderCardRow: View {
    let item: NewTradeItemInput
    let cardLoader: (String) async -> Card?

    @State private var card: Card?

    var body: some View {
        HStack(spacing: 10) {
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
        }
        .task { card = await cardLoader(item.cardID) }
    }

    private var shimmer: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.white.opacity(0.05))
    }
}

// MARK: - TradeCardPickerView

struct TradeCardPickerView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let onConfirm: ([NewTradeItemInput]) -> Void

    @State private var collectionCardIDs: [String] = []
    @State private var selectedCardIDs: Set<String> = []
    @State private var isLoading = false
    @State private var searchText = ""

    private var filteredCardIDs: [String] {
        guard !searchText.isEmpty else { return collectionCardIDs }
        return collectionCardIDs.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading collection…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if collectionCardIDs.isEmpty {
                    ContentUnavailableView(
                        "Collection Empty",
                        systemImage: "rectangle.stack",
                        description: Text("Sync your collection to offer cards in a trade.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    cardGrid
                }
            }
            .navigationTitle("Pick Cards")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search card IDs")
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
        .task { await loadCollection() }
    }

    private var cardGrid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(filteredCardIDs, id: \.self) { cardID in
                    SelectablePickerCard(
                        cardID: cardID,
                        isSelected: selectedCardIDs.contains(cardID),
                        cardLoader: { id in await services.cardData.loadCard(masterCardId: id) }
                    ) {
                        if selectedCardIDs.contains(cardID) {
                            selectedCardIDs.remove(cardID)
                        } else {
                            selectedCardIDs.insert(cardID)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private func loadCollection() async {
        guard let uid: UUID = {
            if case .signedIn(let id, _) = services.socialAuth.authState { return id }
            return nil
        }() else { return }

        isLoading = true
        defer { isLoading = false }
        collectionCardIDs = (try? await services.socialCardLibrary.fetchCollectionCardIDs(for: uid)) ?? []
    }
}

private struct SelectablePickerCard: View {
    let cardID: String
    let isSelected: Bool
    let cardLoader: (String) async -> Card?
    let onTap: () -> Void

    @State private var card: Card?

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    if let imageURLString = card?.imageLowSrc {
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
        .task { card = await cardLoader(cardID) }
    }
}
