import SwiftUI
import SwiftData

// MARK: - Request

/// Everything the sheet needs to present actions for a card.
struct CardContextActionRequest: Identifiable {
    let id = UUID()
    let card: Card
    /// All variant keys the card supports (used in the variant picker).
    let availableVariantKeys: [String]
    /// Pre-selected variant. When coming from collection this is already known.
    let initialVariantKey: String
    /// When from collection: the owned quantity for this variant (drives quantity steppers).
    let ownedQuantity: Int?
    /// The CollectionItem to use for Mark As. Nil when coming from browse.
    let collectionItem: CollectionItem?
    /// Which action tab to open to first.
    let initialAction: CardContextAction

    init(
        card: Card,
        availableVariantKeys: [String],
        initialVariantKey: String = "normal",
        ownedQuantity: Int? = nil,
        collectionItem: CollectionItem? = nil,
        initialAction: CardContextAction = .collection
    ) {
        self.card = card
        self.availableVariantKeys = availableVariantKeys.isEmpty ? ["normal"] : availableVariantKeys
        self.initialVariantKey = initialVariantKey
        self.ownedQuantity = ownedQuantity
        self.collectionItem = collectionItem
        self.initialAction = initialAction
    }
}

enum CardContextAction: String, CaseIterable, Identifiable {
    case collection = "Collection"
    case wishlist   = "Wishlist"
    case tradeList  = "Trade List"
    case folder     = "Folder"
    case markAs     = "Mark As"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .collection: return "books.vertical"
        case .wishlist:   return "heart"
        case .tradeList:  return "arrow.left.arrow.right"
        case .folder:     return "folder.badge.plus"
        case .markAs:     return "tag"
        }
    }
}

// MARK: - Sheet

struct CardContextActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppServices.self) private var services
    @Query(sort: \CardFolder.createdAt, order: .reverse) private var folders: [CardFolder]
    @Query private var tradeListItems: [TradeListItem]

    let request: CardContextActionRequest

    // Action picker
    @State private var selectedAction: CardContextAction

    // Shared
    @State private var selectedVariantKey: String
    @State private var quantity: Int = 1

    // Collection fields
    @State private var acquisitionKind: CollectionAcquisitionKind = .packed
    @State private var cardCondition: CardCondition = .raw
    @State private var gradingCompany: GradingCompany = .psa
    @State private var occurredAt: Date = Date()
    @State private var collectionPriceText: String = ""

    // Wishlist (no extra fields)

    // Trade List
    @State private var tradeListQuantity: Int = 1

    // Folder
    @State private var addedFolderIDs: Set<UUID> = []
    @State private var folderQuantity: Int = 1
    @State private var showCreateFolderAlert = false
    @State private var newFolderTitle: String = ""

    // Mark As
    @State private var dispositionKind: CollectionDispositionKind = .sold
    @State private var markAsQuantity: Int = 1
    @State private var markAsPriceText: String = ""
    @State private var markAsCounterparty: String = ""
    @State private var markAsNotes: String = ""

    // Error / paywall
    @State private var errorMessage: String?
    @State private var showPaywall = false

    private var headerButtonColor: Color { colorScheme == .dark ? .white : .black }

    private var availableActions: [CardContextAction] {
        if request.collectionItem != nil {
            return CardContextAction.allCases
        }
        return [.collection, .wishlist, .tradeList, .folder]
    }

    private var currencySymbol: String { services.priceDisplay.currency.symbol }
    private var currencyCode: String {
        services.priceDisplay.currency == .gbp ? "GBP" : "USD"
    }

    private var ownedQuantity: Int { request.ownedQuantity ?? 1 }

    private var existingTradeListItem: TradeListItem? {
        tradeListItems.first {
            $0.cardID == request.card.masterCardId && $0.variantKey == selectedVariantKey
        }
    }

    init(request: CardContextActionRequest) {
        self.request = request
        _selectedAction = State(initialValue: request.initialAction)
        _selectedVariantKey = State(initialValue: request.initialVariantKey)
    }

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                actionPickerSection

                switch selectedAction {
                case .collection: collectionFields
                case .wishlist:   wishlistFields
                case .tradeList:  tradeListFields
                case .folder:     folderFields
                case .markAs:     markAsFields
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(selectedAction.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(headerButtonColor)
                }
                ToolbarItem(placement: .confirmationAction) {
                    confirmButton
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                        .foregroundStyle(headerButtonColor)
                }
            }
            .alert("New Folder", isPresented: $showCreateFolderAlert) {
                TextField("Folder name", text: $newFolderTitle)
                Button("Create") { createAndAddToFolder() }
                Button("Cancel", role: .cancel) { newFolderTitle = "" }
            }
        }
        .tint(headerButtonColor)
        .sheet(isPresented: $showPaywall) {
            PaywallSheet().environment(services)
        }
        .onAppear {
            quantity = min(ownedQuantity, 1)
            tradeListQuantity = min(ownedQuantity, existingTradeListItem.map { $0.quantity + 1 } ?? 1)
            markAsQuantity = min(max(ownedQuantity, 1), 1)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(request.card.cardName)
                    .font(.headline)
                if request.availableVariantKeys.count > 1 {
                    Picker("Variant", selection: $selectedVariantKey) {
                        ForEach(request.availableVariantKeys, id: \.self) { key in
                            Text(variantLabel(key)).tag(key)
                        }
                    }
                } else {
                    Text(variantLabel(selectedVariantKey))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if let ownedQuantity = request.ownedQuantity {
                HStack {
                    Text("Owned")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(ownedQuantity)")
                        .foregroundStyle(.primary)
                }
                .font(.subheadline)
            }
        }
    }

    // MARK: - Action picker

    private var actionPickerSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableActions) { action in
                        actionChip(for: action)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    private func actionChip(for action: CardContextAction) -> some View {
        let isSelected = selectedAction == action
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedAction = action
                errorMessage = nil
            }
            Haptics.selectionChanged()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: action.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(action.rawValue)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? services.theme.accentColor : Color.primary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Collection fields

    @ViewBuilder
    private var collectionFields: some View {
        Section {
            Picker("How acquired", selection: $acquisitionKind) {
                ForEach(CollectionAcquisitionKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
        }

        Section {
            Picker("Condition", selection: $cardCondition) {
                ForEach(CardCondition.allCases, id: \.self) { c in
                    Text(c.title).tag(c)
                }
            }
            .pickerStyle(.segmented)

            if cardCondition == .graded {
                Picker("Grading company", selection: $gradingCompany) {
                    ForEach(GradingCompany.allCases, id: \.self) { c in
                        Text(c.title).tag(c)
                    }
                }
                .pickerStyle(.segmented)
            }
        } footer: {
            if cardCondition == .graded {
                Text("Graded value uses the \(gradingCompany.title) 10 market price.")
            }
        }

        Section {
            Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
        }

        Section {
            DatePicker("Date", selection: $occurredAt, displayedComponents: .date)
        }

        if acquisitionKind == .bought {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text("Price per unit")
                    Spacer()
                    HStack(spacing: 6) {
                        Text(currencySymbol).foregroundStyle(.secondary)
                        TextField("0.00", text: $collectionPriceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 72)
                    }
                }
            } footer: {
                Text("What you paid per card (cost basis).")
            }
        }
    }

    // MARK: - Wishlist fields

    @ViewBuilder
    private var wishlistFields: some View {
        Section {
            Label("Card will be added to your wishlist.", systemImage: "heart")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }

    // MARK: - Trade List fields

    @ViewBuilder
    private var tradeListFields: some View {
        Section {
            Stepper(
                "Quantity: \(tradeListQuantity)",
                value: $tradeListQuantity,
                in: 1...max(ownedQuantity, 1)
            )
        } footer: {
            if request.ownedQuantity != nil {
                Text("You own \(ownedQuantity) \(ownedQuantity == 1 ? "copy" : "copies") of this card.")
            }
        }

        if let existing = existingTradeListItem {
            Section {
                HStack {
                    Text("Currently on trade list")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(existing.quantity)")
                }
                .font(.subheadline)
            }
        }
    }

    // MARK: - Folder fields

    @ViewBuilder
    private var folderFields: some View {
        Section {
            Stepper("Quantity: \(folderQuantity)", value: $folderQuantity, in: 1...999)
        }

        Section {
            Button {
                newFolderTitle = ""
                showCreateFolderAlert = true
            } label: {
                Label("New Folder…", systemImage: "folder.badge.plus")
                    .foregroundStyle(.primary)
            }
        }

        if !folders.isEmpty {
            Section("MY FOLDERS") {
                ForEach(folders) { folder in
                    let alreadyAdded = addedFolderIDs.contains(folder.id)
                        || folderContainsCard(folder)
                    Button {
                        guard !alreadyAdded else { return }
                        addCardToFolder(folder)
                    } label: {
                        HStack {
                            Label(folder.title, systemImage: "folder")
                                .foregroundStyle(alreadyAdded ? .secondary : .primary)
                            Spacer()
                            if alreadyAdded {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\((folder.items ?? []).count) cards")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Mark As fields

    @ViewBuilder
    private var markAsFields: some View {
        Section {
            Picker("Status", selection: $dispositionKind) {
                ForEach(CollectionDispositionKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
        }

        Section {
            Stepper(
                "Quantity: \(markAsQuantity)",
                value: $markAsQuantity,
                in: 1...max(ownedQuantity, 1)
            )
        }

        if dispositionKind == .sold {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text("Sold price per card")
                    Spacer()
                    HStack(spacing: 6) {
                        Text(currencySymbol).foregroundStyle(.secondary)
                        TextField("0.00", text: $markAsPriceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 72)
                    }
                }
            }
        }

        Section {
            TextField(markAsCounterpartyLabel, text: $markAsCounterparty)
            TextField("Notes", text: $markAsNotes, axis: .vertical)
                .lineLimit(2...6)
        }
    }

    private var markAsCounterpartyLabel: String {
        switch dispositionKind {
        case .sold:    return "Sold to"
        case .traded:  return "Traded with"
        case .gifted:  return "Gifted to"
        case .lost:    return "Lost details"
        case .damaged: return "Damage details"
        }
    }

    // MARK: - Confirm button

    @ViewBuilder
    private var confirmButton: some View {
        switch selectedAction {
        case .folder:
            Button("Done") { dismiss() }
                .foregroundStyle(headerButtonColor)
        case .wishlist:
            Button("Add") { saveWishlist() }
                .foregroundStyle(headerButtonColor)
        case .collection:
            Button("Add") { saveCollection() }
                .foregroundStyle(headerButtonColor)
                .disabled(acquisitionKind == .trade)
        case .tradeList:
            Button("Save") { saveTradeList() }
                .foregroundStyle(headerButtonColor)
        case .markAs:
            Button("Save") { saveMarkAs() }
                .foregroundStyle(headerButtonColor)
        }
    }

    // MARK: - Save actions

    private func saveCollection() {
        errorMessage = nil
        guard acquisitionKind != .trade else { return }
        guard let ledger = services.collectionLedger else {
            errorMessage = "Collection isn't ready. Try again."
            return
        }
        do {
            let unitPrice: Double? = acquisitionKind == .bought
                ? try parseRequiredPrice(collectionPriceText)
                : nil
            try ledger.recordSingleCardAcquisition(
                cardID: request.card.masterCardId,
                variantKey: selectedVariantKey,
                kind: acquisitionKind,
                quantity: quantity,
                occurredAt: occurredAt,
                currencyCode: currencyCode,
                cardDisplayName: request.card.cardName,
                unitPrice: unitPrice,
                gradingCompany: cardCondition == .graded ? gradingCompany.rawValue : nil,
                grade: cardCondition == .graded ? "10" : nil,
                packedOpenedFrom: nil,
                tradeCounterparty: nil,
                tradeGaveAway: nil,
                giftFrom: nil,
                boughtFrom: nil
            )
            Haptics.success()
            dismiss()
        } catch AddToCollectionValidation.missingPrice {
            errorMessage = "Enter a unit price."
        } catch AddToCollectionValidation.invalidPrice {
            errorMessage = "Enter a valid unit price."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveWishlist() {
        errorMessage = nil
        guard let wl = services.wishlist else {
            errorMessage = "Wishlist isn't ready. Try again."
            return
        }
        do {
            try wl.addItem(cardID: request.card.masterCardId, variantKey: selectedVariantKey, notes: "")
            Haptics.success()
            dismiss()
        } catch let e as WishlistError {
            switch e {
            case .limitReached:
                showPaywall = true
            case .alreadyExists:
                errorMessage = "Already on your wishlist."
            case .saveFailed(let inner):
                errorMessage = inner.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveTradeList() {
        errorMessage = nil
        if let existing = existingTradeListItem {
            existing.quantity = tradeListQuantity
        } else {
            modelContext.insert(TradeListItem(
                cardID: request.card.masterCardId,
                variantKey: selectedVariantKey,
                quantity: tradeListQuantity
            ))
        }
        try? modelContext.save()
        Haptics.success()
        dismiss()
    }

    private func saveMarkAs() {
        errorMessage = nil
        guard let item = request.collectionItem else { return }
        guard let ledger = services.collectionLedger else {
            errorMessage = "Collection isn't ready. Try again."
            return
        }
        do {
            try ledger.recordSingleCardDisposition(
                item: item,
                kind: dispositionKind,
                quantity: markAsQuantity,
                currencyCode: currencyCode,
                cardDisplayName: request.card.cardName,
                unitPrice: try parsedOptionalPrice(markAsPriceText),
                counterparty: markAsCounterparty,
                notes: markAsNotes
            )
            Haptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Folder helpers

    private func folderContainsCard(_ folder: CardFolder) -> Bool {
        (folder.items ?? []).contains {
            $0.cardID == request.card.masterCardId && $0.variantKey == selectedVariantKey
        }
    }

    private func addCardToFolder(_ folder: CardFolder) {
        let item = CardFolderItem(cardID: request.card.masterCardId, variantKey: selectedVariantKey, quantity: folderQuantity)
        item.folder = folder
        modelContext.insert(item)
        try? modelContext.save()
        addedFolderIDs.insert(folder.id)
        Haptics.success()
    }

    private func createAndAddToFolder() {
        let title = newFolderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let folder = CardFolder(title: title)
        modelContext.insert(folder)
        let item = CardFolderItem(cardID: request.card.masterCardId, variantKey: selectedVariantKey, quantity: folderQuantity)
        item.folder = folder
        modelContext.insert(item)
        try? modelContext.save()
        addedFolderIDs.insert(folder.id)
        newFolderTitle = ""
        Haptics.success()
    }

    // MARK: - Helpers

    private func variantLabel(_ key: String) -> String {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized != "normal" else { return "Normal" }
        let spaced = normalized
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        return spaced.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func parseRequiredPrice(_ text: String) throws -> Double {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw AddToCollectionValidation.missingPrice }
        guard let v = Double(t.replacingOccurrences(of: ",", with: ".")) else {
            throw AddToCollectionValidation.invalidPrice
        }
        return v
    }

    private func parsedOptionalPrice(_ text: String) throws -> Double? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        guard let v = Double(t.replacingOccurrences(of: ",", with: ".")) else {
            throw CollectionMarkAsSheetError.invalidPrice
        }
        return v
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private enum AddToCollectionValidation: Error {
    case missingPrice, invalidPrice
}

private enum CollectionMarkAsSheetError: LocalizedError {
    case invalidPrice
    var errorDescription: String? { "Enter a valid price." }
}
