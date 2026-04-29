import SwiftUI
import UIKit

/// Bulk add all scanned cards to the collection in one action.
struct ScannerBulkAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services

    let results: [ScanResult]
    @Binding var selectedVariantsByResultID: [UUID: String]
    @Binding var selectedQuantitiesByResultID: [UUID: Int]
    /// Called on the main actor after a successful add, before the sheet dismisses (clear scan session).
    var onSuccessClearSession: () -> Void = {}

    /// Per-card acquisition (default `.packed` when unset).
    @State private var acquisitionByResultID: [UUID: CollectionAcquisitionKind] = [:]
    /// Per-card bought prices keyed by ScanResult.id
    @State private var pricesByResultID: [UUID: String] = [:]
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var successCount = 0
    @State private var showSuccess = false

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
                            variantKey: variantBinding(for: result),
                            quantity: quantityBinding(for: result),
                            acquisitionKind: acquisitionBinding(for: result.id),
                            priceText: Binding(
                                get: { pricesByResultID[result.id] ?? "" },
                                set: { pricesByResultID[result.id] = $0 }
                            ),
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
        }
    }

    private func dismissDecimalKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var canSave: Bool {
        !results.contains { acquisition(for: $0.id) == .trade }
    }

    private func variants(for card: Card) -> [String] {
        if let v = card.pricingVariants, !v.isEmpty { return v }
        return ["normal"]
    }

    private func acquisition(for id: UUID) -> CollectionAcquisitionKind {
        acquisitionByResultID[id] ?? .packed
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

    private func acquisitionBinding(for id: UUID) -> Binding<CollectionAcquisitionKind> {
        Binding(
            get: { acquisition(for: id) },
            set: { acquisitionByResultID[id] = $0 }
        )
    }

    private func quantityBinding(for result: ScanResult) -> Binding<Int> {
        Binding(
            get: { max(1, selectedQuantitiesByResultID[result.id] ?? 1) },
            set: { selectedQuantitiesByResultID[result.id] = max(1, $0) }
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

        for result in results where acquisition(for: result.id) == .trade {
            errorMessage = "Trades are not available yet. Change how you acquired \(result.card.cardName), or remove it from the scan."
            return
        }

        for result in results {
            let kind = acquisition(for: result.id)
            guard kind == .bought else { continue }
            let text = pricesByResultID[result.id] ?? ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  Double(trimmed.replacingOccurrences(of: ",", with: ".")) != nil else {
                errorMessage = "Enter a valid price paid for \(result.card.cardName)."
                return
            }
        }

        isSaving = true
        var saved = 0
        var firstError: String?

        for result in results {
            let variantKey = selectedVariantsByResultID[result.id]
                ?? result.card.pricingVariants?.first
                ?? "normal"
            let quantity = max(1, selectedQuantitiesByResultID[result.id] ?? 1)
            let kind = acquisition(for: result.id)

            do {
                switch kind {
                case .bought:
                    let text = pricesByResultID[result.id] ?? ""
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
                saved += 1
            } catch {
                if firstError == nil { firstError = error.localizedDescription }
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
    @Binding var variantKey: String
    @Binding var quantity: Int
    @Binding var acquisitionKind: CollectionAcquisitionKind
    @Binding var priceText: String
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
                    if acquisitionKind != .bought {
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

            if variants.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Print / variant")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Print / variant", selection: $variantKey) {
                        ForEach(variants, id: \.self) { key in
                            Text(variantDisplayName(key)).tag(key)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.primary)
                }
            }

            HStack {
                Text("Quantity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 10) {
                    Button {
                        guard quantity > 1 else { return }
                        quantity -= 1
                        HapticManager.impact(.light)
                    } label: {
                        Image(systemName: "minus")
                            .font(.caption.weight(.bold))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.primary.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .disabled(quantity <= 1)

                    Text("\(max(1, quantity))")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .frame(minWidth: 24)

                    Button {
                        quantity += 1
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

            VStack(alignment: .leading, spacing: 6) {
                Text("How acquired")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("How acquired", selection: $acquisitionKind) {
                    ForEach(CollectionAcquisitionKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }

            Group {
                switch acquisitionKind {
                case .bought:
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Price paid")
                                .foregroundStyle(.secondary)
                            Spacer()
                            HStack(spacing: 6) {
                                Text(currencySymbol)
                                    .foregroundStyle(.secondary)
                                TextField("0.00", text: $priceText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(minWidth: 72)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Price paid")
                        Text("Cost basis. Market estimate: \(priceHint).")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                case .packed, .gifted:
                    EmptyView()
                case .trade:
                    ContentUnavailableView(
                        "Trades",
                        systemImage: "arrow.left.arrow.right",
                        description: Text("Trades are coming soon. Choose another option above.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.vertical, 4)
        .task(id: "\(card.masterCardId)_\(variantKey)_\(acquisitionKind.rawValue)") {
            await loadPriceHint()
        }
    }

    private func loadPriceHint() async {
        if let usd = await services.pricing.usdPriceForVariantAndGrade(
            for: card, variantKey: variantKey, grade: "raw"
        ) {
            let formatted = services.priceDisplay.currency.format(
                amountUSD: usd, usdToGbp: services.pricing.usdToGbp
            )
            await MainActor.run { priceHint = formatted }
            if priceText.isEmpty, acquisitionKind == .bought {
                let raw = String(format: "%.2f", services.priceDisplay.currency == .gbp
                    ? usd * services.pricing.usdToGbp
                    : usd)
                await MainActor.run { priceText = raw }
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
