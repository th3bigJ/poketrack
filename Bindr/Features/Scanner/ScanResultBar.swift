import SwiftUI

struct ScanResultBar: View {
    @Environment(AppServices.self) private var services

    let result: ScanResult
    /// Only the centered page should show expanded UI; others stay compact while off-screen.
    var isCurrentPage: Bool
    /// Called when the user picks another catalog match from "Wrong card?".
    var onPickAlternative: (Card) -> Void
    /// Opens the full card detail sheet.
    var onOpenDetails: () -> Void
    /// Removes this scanned result from the list.
    var onDelete: () -> Void
    /// Bound to the parent so the selected variant is readable when swiping up.
    @Binding var selectedVariant: String
    /// Quantity selected per variant for this scan result.
    @Binding var selectedVariantQuantities: [String: Int]
    @State private var showWrongCardSheet = false
    /// Market prices keyed by variant, formatted with `PriceDisplaySettings`.
    @State private var barVariantPriceTextByKey: [String: String] = [:]

    private var card: Card { result.card }
    private var setDisplayName: String {
        services.cardData.sets.first(where: { $0.setCode == card.setCode })?.name
            ?? card.setCode.uppercased()
    }

    private var variants: [String] {
        if let v = card.pricingVariants, !v.isEmpty { return v }
        return ["normal"]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                cardThumbnail
                cardInfo
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 8) {
                    wrongCardButton
                    deleteCardButton
                }
            }
            .padding(.top, 10)
            .padding(.horizontal, 16)

            Text("Select variant and add to collection")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
                .padding(.horizontal, 16)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(variants, id: \.self) { key in
                        variantRow(key)
                    }
                }
                .padding(.bottom, 6)
            }
            .frame(maxHeight: 265)
            .padding(.top, 8)
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .onAppear {
            for key in variants where (selectedVariantQuantities[key] ?? 0) < 0 {
                selectedVariantQuantities[key] = 0
            }
        }
        .onChange(of: card.masterCardId) { _, _ in
            selectedVariant = ""
            selectedVariantQuantities = [:]
        }
        .task(id: "\(card.masterCardId)_\(services.priceDisplay.currency.rawValue)_\(services.pricing.usdToGbp)") {
            await refreshBarVariantPrices()
        }
        .sheet(isPresented: $showWrongCardSheet) {
            ScannerWrongCardAlternativesSheet(
                alternatives: result.alternativeCards,
                onSelect: { picked in
                    onPickAlternative(picked)
                    showWrongCardSheet = false
                }
            )
        }
    }


    // MARK: - Thumbnail

    private var cardThumbnail: some View {
        CachedAsyncImage(
            url: AppConfiguration.imageURL(relativePath: card.imageLowSrc),
            targetSize: CGSize(width: 52, height: 72)
        ) { img in
            img.resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 52, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } placeholder: {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 52, height: 72)
        }
        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
        .onTapGesture {
            guard isCurrentPage else { return }
            onOpenDetails()
            HapticManager.impact(.light)
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Open card details")
    }

    // MARK: - Card info

    private var cardInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.cardName)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(setDisplayName + " · #" + card.cardNumber)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let rarity = card.rarity {
                Text(rarity)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var wrongCardButton: some View {
        Button {
            guard isCurrentPage else { return }
            showWrongCardSheet = true
            HapticManager.impact(.light)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("Wrong card?")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 128)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var deleteCardButton: some View {
        Button {
            guard isCurrentPage else { return }
            onDelete()
            HapticManager.impact(.light)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                Text("Delete")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Color.red.opacity(0.95))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: 128)
            .background(Color.red.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.red.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete scanned card")
    }

    private func quantitySelector(for key: String) -> some View {
        let quantity = max(0, selectedVariantQuantities[key] ?? 0)

        return HStack(spacing: 10) {
            Button {
                guard quantity > 0 else { return }
                selectedVariant = key
                selectedVariantQuantities[key] = max(0, quantity - 1)
                HapticManager.impact(.light)
            } label: {
                Image(systemName: "minus")
                    .font(.caption.weight(.bold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.primary.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .disabled(quantity <= 0)

            Text("\(quantity)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 22)

            Button {
                selectedVariant = key
                selectedVariantQuantities[key] = quantity + 1
                HapticManager.impact(.light)
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.primary.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quantity \(quantity)")
    }

    private func variantRow(_ key: String) -> some View {
        let isSelected = (selectedVariantQuantities[key] ?? 0) > 0

        return HStack(spacing: 10) {
            Text(variantDisplayName(key))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(priceText(for: key))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .frame(minWidth: 68, alignment: .trailing)
            quantitySelector(for: key)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.12) : Color.primary.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.primary.opacity(0.16) : Color.clear, lineWidth: 1)
        )
    }

    private func priceText(for key: String) -> String {
        barVariantPriceTextByKey[key] ?? "—"
    }

    // MARK: - Bar price (selected variant, raw grade)

    private func refreshBarVariantPrices() async {
        var next: [String: String] = [:]
        for key in variants {
            if let usd = await services.pricing.usdPriceForVariantAndGrade(for: card, variantKey: key, grade: "raw") {
                next[key] = services.priceDisplay.currency.format(amountUSD: usd, usdToGbp: services.pricing.usdToGbp)
            } else {
                next[key] = "—"
            }
        }
        barVariantPriceTextByKey = next
    }

    // MARK: - Helpers

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

// MARK: - Wrong card alternatives

/// Lists other ranked catalog matches for the same OCR pass so the user can correct a mis-match.
struct ScannerWrongCardAlternativesSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let alternatives: [Card]
    let onSelect: (Card) -> Void

    private func setDisplayName(for card: Card) -> String {
        services.cardData.sets.first(where: { $0.setCode == card.setCode })?.name
            ?? card.setCode.uppercased()
    }

    var body: some View {
        NavigationStack {
            Group {
                if alternatives.isEmpty {
                    ContentUnavailableView(
                        "No other matches",
                        systemImage: "rectangle.dashed",
                        description: Text("There aren't other catalog candidates for this scan. Try scanning again with clearer lighting or a steadier frame.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(alternatives.enumerated()), id: \.offset) { idx, card in
                                Button {
                                    HapticManager.selection()
                                    onSelect(card)
                                } label: {
                                    HStack(spacing: 14) {
                                        CachedAsyncImage(
                                            url: AppConfiguration.imageURL(relativePath: card.imageLowSrc),
                                            targetSize: CGSize(width: 44, height: 62)
                                        ) { img in
                                            img
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(Color(uiColor: .tertiarySystemFill))
                                        }
                                        .frame(width: 44, height: 62)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(card.cardName)
                                                .font(.headline)
                                                .foregroundStyle(Color(uiColor: .label))
                                                .multilineTextAlignment(.leading)
                                            Text(setDisplayName(for: card) + " · #" + card.cardNumber)
                                                .font(.subheadline)
                                                .foregroundStyle(Color(uiColor: .secondaryLabel))
                                            if let rarity = card.rarity {
                                                Text(rarity)
                                                    .font(.caption)
                                                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                            }
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if idx < alternatives.count - 1 {
                                    Divider()
                                        .padding(.leading, 74)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Other matches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
    }
}
