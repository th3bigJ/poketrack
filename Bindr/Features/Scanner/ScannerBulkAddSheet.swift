import SwiftUI
import UIKit

/// Bulk add all scanned cards to the collection or trade in one action.
struct ScannerBulkAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.bindrAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppServices.self) private var services

    let results: [ScanResult]
    @Binding var selectedVariantsByResultID: [UUID: String]
    @Binding var selectedVariantQuantitiesByResultID: [UUID: [String: Int]]
    var purpose: CardScannerPurpose = .collection
    /// Called on the main actor after a successful add, before the sheet dismisses (clear scan session).
    var onSuccessClearSession: () -> Void = {}
    /// Called after a successful trade add, before the scanner dismisses.
    var onTradeAddComplete: () -> Void = {}

    /// Per-card + per-variant acquisition (default `.packed` when unset).
    @State private var acquisitionByResultID: [UUID: [String: CollectionAcquisitionKind]] = [:]
    /// Per-card + per-variant bought prices keyed by ScanResult.id + variant key.
    @State private var pricesByResultID: [UUID: [String: String]] = [:]
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var successCount = 0
    @State private var showSuccess = false
    @State private var successSparkTrigger = 0
    @State private var showPaywall = false

    private var currencyCode: String {
        switch services.priceDisplay.currency {
        case .usd: return "USD"
        case .gbp: return "GBP"
        }
    }

    private var currencySymbol: String {
        services.priceDisplay.currency.symbol
    }

    private var addsToTrade: Bool {
        if case .trade = purpose { return true }
        return false
    }

    private var navigationTitle: String {
        addsToTrade ? "Add to trade" : "Add to collection"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(results.count) card\(results.count == 1 ? "" : "s") scanned")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)

                    ForEach(results) { result in
                        BulkAddCardRow(
                            result: result,
                            variants: variants(for: result.card),
                            selectedVariantKey: variantBinding(for: result),
                            variantQuantities: variantQuantitiesBinding(for: result),
                            acquisitionByVariant: acquisitionByVariantBinding(for: result),
                            pricesByVariant: pricesByVariantBinding(for: result),
                            currencySymbol: currencySymbol,
                            showsAcquisitionDetails: !addsToTrade
                        )
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(BindrPalette.alertRed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .glassCardStyle(cornerRadius: BindrRadius.lg, interactive: false)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .bindrPageBackground()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .glassToolbarButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Add") { save() }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(canSave ? accent : .secondary)
                            .disabled(!canSave)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissDecimalKeyboard() }
                        .glassToolbarButton()
                }
            }
            .overlay {
                if showSuccess {
                    successOverlay
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallSheet()
                    .environment(services)
                    .bindrTheme(accent: services.theme.accentColor)
            }
        }
        .bindrTheme(accent: services.theme.accentColor)
    }

    private func dismissDecimalKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var canSave: Bool {
        results.contains { result in
            let quantities = selectedVariantQuantitiesByResultID[result.id] ?? [:]
            return quantities.values.contains(where: { $0 > 0 })
        }
    }

    private func variants(for card: Card) -> [String] {
        if let v = card.pricingVariants, !v.isEmpty { return v }
        return ["normal"]
    }

    private func acquisition(for id: UUID, variantKey: String) -> CollectionAcquisitionKind {
        acquisitionByResultID[id]?[variantKey] ?? .packed
    }

    private func variantBinding(for result: ScanResult) -> Binding<String> {
        Binding(
            get: {
                selectedVariantsByResultID[result.id]
                    ?? result.card.pricingVariants?.first
                    ?? "normal"
            },
            set: { selectedVariantsByResultID[result.id] = $0 }
        )
    }

    private func acquisitionByVariantBinding(for result: ScanResult) -> Binding<[String: CollectionAcquisitionKind]> {
        Binding(
            get: { acquisitionByResultID[result.id] ?? [:] },
            set: { acquisitionByResultID[result.id] = $0 }
        )
    }

    private func pricesByVariantBinding(for result: ScanResult) -> Binding<[String: String]> {
        Binding(
            get: { pricesByResultID[result.id] ?? [:] },
            set: { pricesByResultID[result.id] = $0 }
        )
    }

    private func variantDisplayName(_ key: String) -> String {
        let spaced = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return spaced.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func variantQuantitiesBinding(for result: ScanResult) -> Binding<[String: Int]> {
        Binding(
            get: { selectedVariantQuantitiesByResultID[result.id] ?? [:] },
            set: { selectedVariantQuantitiesByResultID[result.id] = $0 }
        )
    }

    // MARK: - Success overlay

    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.38 : 0.22)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(BindrPalette.ownedGreen)
                    .bindrSuccessSpark(trigger: successSparkTrigger)

                VStack(spacing: 6) {
                    Text("\(successCount) card\(successCount == 1 ? "" : "s") added")
                        .font(.system(size: 19, weight: .bold, design: .rounded))

                    Text(addsToTrade ? "Successfully added to trade" : "Successfully added to your collection")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .bindrAccentStroke(accent.opacity(0.45), lineWidth: 1)
                }
            }
            .padding(.horizontal, 28)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
    }

    // MARK: - Save

    private func save() {
        errorMessage = nil
        if addsToTrade {
            saveToTrade()
            return
        }
        guard let ledger = services.collectionLedger else {
            errorMessage = "Collection isn't ready. Try again."
            return
        }

        for result in results {
            let quantities = selectedVariantQuantitiesByResultID[result.id] ?? [:]
            let selected = quantities.filter { $0.value > 0 }
            for (variantKey, _) in selected {
                let kind = acquisition(for: result.id, variantKey: variantKey)
                guard kind == .bought else { continue }
                let text = pricesByResultID[result.id]?[variantKey] ?? ""
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      Double(trimmed.replacingOccurrences(of: ",", with: ".")) != nil else {
                    errorMessage = "Enter a valid price paid for \(result.card.cardName) (\(variantDisplayName(variantKey)))."
                    return
                }
            }
        }

        isSaving = true
        var saved = 0
        var firstError: String?
        var savedCandidates: [WishlistRemovalCandidate] = []

        for result in results {
            let variantQuantities = selectedVariantQuantitiesByResultID[result.id] ?? [:]
            let selectedEntries = variantQuantities.filter { $0.value > 0 }
            guard !selectedEntries.isEmpty else { continue }

            for (variantKey, quantity) in selectedEntries {
                let kind = acquisition(for: result.id, variantKey: variantKey)
                do {
                    switch kind {
                    case .bought:
                        let text = pricesByResultID[result.id]?[variantKey] ?? ""
                        let unit = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: ",", with: ".")) ?? 0
                        try ledger.recordSingleCardAcquisition(
                            cardID: result.card.masterCardId,
                            variantKey: variantKey,
                            kind: .bought,
                            quantity: quantity,
                            currencyCode: currencyCode,
                            cardDisplayName: result.card.cardName,
                            unitPrice: unit,
                            packedOpenedFrom: nil,
                            tradeCounterparty: nil,
                            tradeGaveAway: nil,
                            giftFrom: nil,
                            boughtFrom: nil
                        )
                    case .packed:
                        try ledger.recordSingleCardAcquisition(
                            cardID: result.card.masterCardId,
                            variantKey: variantKey,
                            kind: .packed,
                            quantity: quantity,
                            currencyCode: currencyCode,
                            cardDisplayName: result.card.cardName,
                            unitPrice: nil,
                            packedOpenedFrom: nil,
                            tradeCounterparty: nil,
                            tradeGaveAway: nil,
                            giftFrom: nil,
                            boughtFrom: nil
                        )
                    case .gifted:
                        try ledger.recordSingleCardAcquisition(
                            cardID: result.card.masterCardId,
                            variantKey: variantKey,
                            kind: .gifted,
                            quantity: quantity,
                            currencyCode: currencyCode,
                            cardDisplayName: result.card.cardName,
                            unitPrice: nil,
                            packedOpenedFrom: nil,
                            tradeCounterparty: nil,
                            tradeGaveAway: nil,
                            giftFrom: nil,
                            boughtFrom: nil
                        )
                    case .trade:
                        try ledger.recordSingleCardAcquisition(
                            cardID: result.card.masterCardId,
                            variantKey: variantKey,
                            kind: .trade,
                            quantity: quantity,
                            currencyCode: currencyCode,
                            cardDisplayName: result.card.cardName,
                            unitPrice: nil,
                            packedOpenedFrom: nil,
                            tradeCounterparty: nil,
                            tradeGaveAway: nil,
                            giftFrom: nil,
                            boughtFrom: nil
                        )
                    case .imported:
                        continue
                    }
                    saved += quantity
                    savedCandidates.append(
                        WishlistRemovalCandidate(
                            cardID: result.card.masterCardId,
                            cardName: result.card.cardName
                        )
                    )
                } catch CollectionLedgerError.freeTierLimitReached {
                    if firstError == nil { firstError = CollectionLedgerError.freeTierLimitReached.errorDescription }
                    showPaywall = true
                } catch {
                    if firstError == nil { firstError = error.localizedDescription }
                }
            }
        }

        isSaving = false

        if let firstError {
            services.requestWishlistRemovalPrompt(for: savedCandidates)
            errorMessage = firstError
            return
        }

        successCount = saved
        HapticManager.impact(.medium)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            showSuccess = true
        }
        Task { @MainActor in
            await Task.yield()
            successSparkTrigger += 1
            try? await Task.sleep(for: .seconds(1.4))
            onSuccessClearSession()
            dismiss()
            try? await Task.sleep(for: .milliseconds(250))
            services.requestWishlistRemovalPrompt(for: savedCandidates)
        }
    }

    private func saveToTrade() {
        guard case .trade(let onAdd) = purpose else { return }

        var items: [NewTradeItemInput] = []
        for result in results {
            let variantQuantities = selectedVariantQuantitiesByResultID[result.id] ?? [:]
            for (variantKey, quantity) in variantQuantities where quantity > 0 {
                items.append(
                    NewTradeItemInput(
                        cardID: result.card.masterCardId,
                        variantKey: variantKey,
                        quantity: quantity
                    )
                )
            }
        }

        guard !items.isEmpty else {
            errorMessage = "Select at least one card to add."
            return
        }

        onAdd(items)
        successCount = items.reduce(0) { $0 + max($1.quantity, 1) }
        HapticManager.impact(.medium)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            showSuccess = true
        }
        Task { @MainActor in
            await Task.yield()
            successSparkTrigger += 1
            try? await Task.sleep(for: .seconds(1.0))
            onSuccessClearSession()
            onTradeAddComplete()
            dismiss()
        }
    }
}

// MARK: - Card row

private struct BulkAddCardRow: View {
    @Environment(\.bindrAccent) private var accent
    @Environment(AppServices.self) private var services

    let result: ScanResult
    let variants: [String]
    @Binding var selectedVariantKey: String
    @Binding var variantQuantities: [String: Int]
    @Binding var acquisitionByVariant: [String: CollectionAcquisitionKind]
    @Binding var pricesByVariant: [String: String]
    let currencySymbol: String
    var showsAcquisitionDetails: Bool = true

    @State private var priceHint: String = "—"

    private var card: Card { result.card }
    private var setDisplayName: String {
        services.cardData.sets.first(where: { $0.setCode == card.setCode })?.name
            ?? card.setCode.uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                CachedAsyncImage(
                    url: AppConfiguration.imageURL(relativePath: card.displayImageSrc),
                    targetSize: CGSize(width: 52, height: 72)
                ) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: BindrRadius.sm, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                }
                .frame(width: 52, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: BindrRadius.sm, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(card.cardName)
                        .font(.headline)
                        .lineLimit(2)
                    Text(setDisplayName + " · #" + card.cardNumber)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if activeAcquisitionKind != .bought {
                        Label {
                            Text("Market \(priceHint)")
                                .font(.caption.weight(.medium))
                        } icon: {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Variants")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(variants, id: \.self) { key in
                    variantQuantityRow(for: key)
                }
            }
        }
        .padding(16)
        .glassCardStyle(cornerRadius: BindrRadius.lg, interactive: false)
        .onAppear {
            if selectedVariantKey.isEmpty {
                selectedVariantKey = variants.first ?? "normal"
            }
        }
        .task(id: "\(card.masterCardId)_\(selectedVariantKey)_\(activeAcquisitionKind.rawValue)") {
            await loadPriceHint()
        }
    }

    private var activeAcquisitionKind: CollectionAcquisitionKind {
        acquisitionByVariant[selectedVariantKey] ?? .packed
    }

    private func variantQuantityRow(for key: String) -> some View {
        let qty = max(0, variantQuantities[key] ?? 0)

        let kind = acquisitionByVariant[key] ?? .packed

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(variantDisplayName(key))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 8)

                HStack(spacing: 10) {
                    Button {
                        guard qty > 0 else { return }
                        selectedVariantKey = key
                        variantQuantities[key] = qty - 1
                        HapticManager.impact(.light)
                    } label: {
                        Image(systemName: "minus")
                            .font(.caption.weight(.bold))
                            .frame(width: 32, height: 32)
                            .background(.thinMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(qty <= 0)

                    Text("\(qty)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .frame(minWidth: 24)

                    Button {
                        selectedVariantKey = key
                        variantQuantities[key] = qty + 1
                        HapticManager.impact(.light)
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                            .frame(width: 32, height: 32)
                            .background(.thinMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            if qty > 0, showsAcquisitionDetails {
                VStack(alignment: .leading, spacing: 6) {
                    Text("How acquired")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("How acquired for \(variantDisplayName(key))", selection: Binding(
                        get: { acquisitionByVariant[key] ?? .packed },
                        set: { acquisitionByVariant[key] = $0 }
                    )) {
                        ForEach(CollectionAcquisitionKind.manualAddCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    if kind == .bought {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Price per unit")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            HStack(spacing: 6) {
                                Text(currencySymbol)
                                    .foregroundStyle(.secondary)
                                TextField("0.00", text: Binding(
                                    get: { pricesByVariant[key] ?? "" },
                                    set: { pricesByVariant[key] = $0 }
                                ))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(minWidth: 72)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: BindrRadius.md, style: .continuous)
                .fill(qty > 0 ? accent.opacity(0.10) : Color.primary.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: BindrRadius.md, style: .continuous)
                .strokeBorder(qty > 0 ? accent.opacity(0.22) : Color.clear, lineWidth: 1)
        }
    }

    private func loadPriceHint() async {
        if let usd = await services.pricing.usdPriceForVariantAndGrade(
            for: card, variantKey: selectedVariantKey, grade: "raw"
        ) {
            let formatted = services.priceDisplay.currency.format(
                amountUSD: usd, usdToGbp: services.pricing.usdToGbp
            )
            await MainActor.run { priceHint = formatted }
            if (pricesByVariant[selectedVariantKey] ?? "").isEmpty, activeAcquisitionKind == .bought {
                let raw = String(format: "%.2f", services.priceDisplay.currency == .gbp
                    ? usd * services.pricing.usdToGbp
                    : usd)
                await MainActor.run { pricesByVariant[selectedVariantKey] = raw }
            }
        }
    }

    private func variantDisplayName(_ key: String) -> String {
        let spaced = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return spaced.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}
