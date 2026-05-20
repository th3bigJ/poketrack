import SwiftUI
import UIKit

/// Bulk add all scanned cards to the collection in one action.
struct ScannerBulkAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services

    let results: [ScanResult]
    @Binding var selectedVariantsByResultID: [UUID: String]
    @Binding var selectedVariantQuantitiesByResultID: [UUID: [String: Int]]
    /// Called on the main actor after a successful add, before the sheet dismisses (clear scan session).
    var onSuccessClearSession: () -> Void = {}

    /// Per-card + per-variant acquisition (default `.packed` when unset).
    @State private var acquisitionByResultID: [UUID: [String: CollectionAcquisitionKind]] = [:]
    /// Per-card + per-variant bought prices keyed by ScanResult.id + variant key.
    @State private var pricesByResultID: [UUID: [String: String]] = [:]
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var successCount = 0
    @State private var showSuccess = false
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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(results) { result in
                        BulkAddCardRow(
                            result: result,
                            variants: variants(for: result.card),
                            selectedVariantKey: variantBinding(for: result),
                            variantQuantities: variantQuantitiesBinding(for: result),
                            acquisitionByVariant: acquisitionByVariantBinding(for: result),
                            pricesByVariant: pricesByVariantBinding(for: result),
                            currencySymbol: currencySymbol
                        )
                    }
                } header: {
                    Text("\(results.count) card\(results.count == 1 ? "" : "s") scanned")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add to collection")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.primary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Add") { save() }
                            .fontWeight(.semibold)
                            .disabled(!canSave)
                            .foregroundStyle(.primary)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissDecimalKeyboard() }
                }
            }
            .overlay {
                if showSuccess {
                    successOverlay
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallSheet().environment(services)
            }
        }
    }

    private func dismissDecimalKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var canSave: Bool {
        !results.contains { result in
            let quantities = selectedVariantQuantitiesByResultID[result.id] ?? [:]
            let selected = quantities.filter { $0.value > 0 }
            return selected.keys.contains { acquisition(for: result.id, variantKey: $0) == .trade }
        } &&
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
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("\(successCount) card\(successCount == 1 ? "" : "s") added")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text("Successfully added to your collection")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }

    // MARK: - Save

    private func save() {
        errorMessage = nil
        guard let ledger = services.collectionLedger else {
            errorMessage = "Collection isn't ready. Try again."
            return
        }

        for result in results {
            let quantities = selectedVariantQuantitiesByResultID[result.id] ?? [:]
            let selected = quantities.filter { $0.value > 0 }
            for (variantKey, _) in selected {
                let kind = acquisition(for: result.id, variantKey: variantKey)
                if kind == .trade {
                    errorMessage = "Trades are not available yet. Change how you acquired \(result.card.cardName) (\(variantDisplayName(variantKey)))."
                    return
                }
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
                        continue
                    }
                    saved += quantity
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
            errorMessage = firstError
            return
        }

        successCount = saved
        HapticManager.impact(.medium)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            showSuccess = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            onSuccessClearSession()
            dismiss()
        }
    }
}

// MARK: - Card row

private struct BulkAddCardRow: View {
    @Environment(AppServices.self) private var services

    let result: ScanResult
    let variants: [String]
    @Binding var selectedVariantKey: String
    @Binding var variantQuantities: [String: Int]
    @Binding var acquisitionByVariant: [String: CollectionAcquisitionKind]
    @Binding var pricesByVariant: [String: String]
    let currencySymbol: String

    @State private var priceHint: String = "—"

    private var card: Card { result.card }
    private var setDisplayName: String {
        services.cardData.sets.first(where: { $0.setCode == card.setCode })?.name
            ?? card.setCode.uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                CachedAsyncImage(
                    url: AppConfiguration.imageURL(relativePath: card.imageLowSrc),
                    targetSize: CGSize(width: 44, height: 62)
                ) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                }
                .frame(width: 44, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(card.cardName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(setDisplayName + " · #" + card.cardNumber)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if activeAcquisitionKind != .bought {
                        Label {
                            Text("Market \(priceHint)")
                                .font(.caption)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(variants, id: \.self) { key in
                    variantQuantityRow(for: key)
                }
            }
        }
        .padding(.vertical, 4)
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
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.primary.opacity(0.1)))
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
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.primary.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }

            if qty > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("How acquired")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("How acquired for \(variantDisplayName(key))", selection: Binding(
                        get: { acquisitionByVariant[key] ?? .packed },
                        set: { acquisitionByVariant[key] = $0 }
                    )) {
                        ForEach(CollectionAcquisitionKind.allCases, id: \.self) { kind in
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
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill((selectedVariantKey == key ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06)))
        )
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
