import SwiftUI

struct ScanResultBar: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    let result: ScanResult
    /// Only the centered page should show expanded UI; others stay compact while off-screen.
    var isCurrentPage: Bool
    /// Called when the user picks another catalog match from "Wrong card?".
    var onPickAlternative: (Card) -> Void
    /// Opens the full card detail sheet.
    var onOpenDetails: () -> Void
    /// Opens the bulk add-to-collection sheet for all scanned cards.
    var onAddAllToCollection: () -> Void
    /// Bound to the parent so the selected variant is readable when swiping up.
    @Binding var selectedVariant: String
    @State private var showWrongCardSheet = false
    /// Market price for `selectedVariant` (raw), formatted with `PriceDisplaySettings`.
    @State private var barVariantPriceText: String = "—"
    @State private var wishlistFeedback: WishlistFeedback?

    private var card: Card { result.card }

    private var collectionPlusGlyphColor: Color {
        colorScheme == .dark ? .white : Color.primary
    }

    /// Filled wishlist star — matches `CardBrowseDetailView` (gold, not accent blue).
    private static let wishlistStarGold = Color(red: 0.98, green: 0.78, blue: 0.18)

    private var isCurrentVariantWishlisted: Bool {
        guard let wl = services.wishlist else { return false }
        _ = wl.items
        return wl.isInWishlist(cardID: card.masterCardId, variantKey: selectedVariant)
    }

    private enum WishlistFeedback {
        case added, removed, alreadyExists, limitReached, error(String)

        var message: String {
            switch self {
            case .added:         return "Added to wishlist"
            case .removed:       return "Removed from wishlist"
            case .alreadyExists: return "Already in wishlist"
            case .limitReached:  return "Wishlist limit reached"
            case .error(let e):  return e
            }
        }
        var icon: String {
            switch self {
            case .added:         return "checkmark.circle.fill"
            case .removed:       return "checkmark.circle.fill"
            case .alreadyExists: return "checkmark.circle"
            case .limitReached:  return "exclamationmark.circle.fill"
            case .error:         return "xmark.circle.fill"
            }
        }
        var color: Color {
            switch self {
            case .added, .removed:       return .green
            case .alreadyExists:         return .secondary
            case .limitReached, .error:  return .orange
            }
        }
    }

    private var variants: [String] {
        if let v = card.pricingVariants, !v.isEmpty { return v }
        return ["normal"]
    }

    /// One print → single add; multiple → menu.
    private var singleVariantForActions: String? {
        variants.count == 1 ? variants.first : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Card row
            HStack(spacing: 14) {
                cardThumbnail
                cardInfo
                Spacer(minLength: 8)
                Text(barVariantPriceText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120, alignment: .trailing)
            }
            .padding(.horizontal, 16)

            if variants.count > 1 {
                variantPicker
                    .padding(.top, 14)
                    .padding(.horizontal, 16)

                Text("Select a variant before adding to collection")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                    .padding(.horizontal, 16)
            }

            if let feedback = wishlistFeedback {
                HStack(spacing: 6) {
                    Image(systemName: feedback.icon).foregroundStyle(feedback.color)
                    Text(feedback.message).font(.subheadline).foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            actionButtons
                .padding(.top, 14)
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
        }
        .onAppear {
            if selectedVariant.isEmpty { selectedVariant = variants.first ?? "normal" }
        }
        .onChange(of: card.masterCardId) { _, _ in
            selectedVariant = variants.first ?? "normal"
        }
        .task(id: "\(card.masterCardId)_\(selectedVariant)_\(services.priceDisplay.currency.rawValue)_\(services.pricing.usdToGbp)") {
            await refreshBarVariantPrice()
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
    }

    // MARK: - Card info

    private var cardInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.cardName)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(card.setCode.uppercased() + " · #" + card.cardNumber)
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

    // MARK: - Variant picker

    private var variantPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(variants, id: \.self) { key in
                    let isSelected = key == selectedVariant
                    Button {
                        selectedVariant = key
                        HapticManager.impact(.light)
                    } label: {
                        Text(variantDisplayName(key))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(isSelected ? Color.primary : Color.primary.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selectedVariant)
                }
            }
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        HStack(spacing: 10) {
            actionButton(icon: "questionmark.circle.fill", label: "Wrong card?", style: .secondary) {
                guard isCurrentPage else { return }
                showWrongCardSheet = true
                HapticManager.impact(.light)
            }
            actionButton(icon: "info.circle.fill", label: "Card details", style: .secondary) {
                guard isCurrentPage else { return }
                onOpenDetails()
                HapticManager.impact(.light)
            }
            actionButton(icon: "plus.circle.fill", label: "Add", style: .primary) {
                guard isCurrentPage else { return }
                onAddAllToCollection()
                HapticManager.impact(.medium)
            }
        }
    }

    private var wishlistActionButton: some View {
        Button {
            guard isCurrentPage else { return }
            toggleWishlist()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: isCurrentVariantWishlisted ? "star.fill" : "star")
                    .font(.system(size: 20))
                    .foregroundStyle(isCurrentVariantWishlisted ? Self.wishlistStarGold : .primary)
                Text("Wishlist")
                    .font(.system(size: 11, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(.primary)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCurrentVariantWishlisted ? "Remove from wishlist" : "Add to wishlist")
    }

    private enum ButtonStyle { case primary, secondary }

    private func actionButton(icon: String, label: String, style: ButtonStyle, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 20))
                Text(label).font(.system(size: 11, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(style == .primary ? Color(uiColor: .systemBackground) : .primary)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(style == .primary ? Color.primary : Color.primary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Wishlist

    private func isVariantWishlisted(_ key: String) -> Bool {
        guard let wl = services.wishlist else { return false }
        _ = wl.items
        return wl.isInWishlist(cardID: card.masterCardId, variantKey: key)
    }

    private func toggleWishlist() {
        toggleWishlist(forVariantKey: selectedVariant)
    }

    private func toggleWishlist(forVariantKey key: String) {
        guard let wishlist = services.wishlist else { return }
        if isVariantWishlisted(key) {
            do {
                try wishlist.removeCardVariant(cardID: card.masterCardId, variantKey: key)
                selectedVariant = key
                show(feedback: .removed)
                HapticManager.impact(.light)
            } catch {
                show(feedback: .error(error.localizedDescription))
            }
            return
        }
        do {
            try wishlist.addItem(cardID: card.masterCardId, variantKey: key)
            selectedVariant = key
            show(feedback: .added)
            HapticManager.impact(.medium)
        } catch WishlistError.alreadyExists {
            show(feedback: .alreadyExists)
        } catch WishlistError.limitReached {
            show(feedback: .limitReached)
        } catch {
            show(feedback: .error(error.localizedDescription))
        }
    }

    private func show(feedback: WishlistFeedback) {
        withAnimation(.spring(response: 0.3)) { wishlistFeedback = feedback }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.25)) { wishlistFeedback = nil }
        }
    }

    // MARK: - Bar price (selected variant, raw grade)

    private func refreshBarVariantPrice() async {
        let key = selectedVariant.isEmpty ? (variants.first ?? "normal") : selectedVariant
        if let usd = await services.pricing.usdPriceForVariantAndGrade(for: card, variantKey: key, grade: "raw") {
            barVariantPriceText = services.priceDisplay.currency.format(amountUSD: usd, usdToGbp: services.pricing.usdToGbp)
        } else {
            barVariantPriceText = "—"
        }
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
    @Environment(\.dismiss) private var dismiss

    let alternatives: [Card]
    let onSelect: (Card) -> Void

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
                                            Text(card.setCode.uppercased() + " · #" + card.cardNumber)
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
