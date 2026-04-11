import SwiftUI

struct ScanResultBar: View {
    @Environment(AppServices.self) private var services

    let result: ScanResult
    /// Only the centered page should show expanded UI; others stay compact while off-screen.
    var isCurrentPage: Bool
    @Binding var isExpanded: Bool
    /// Cap for the scrollable detail region when expanded (from parent `GeometryReader`).
    var maxExpandedContentHeight: CGFloat
    /// Called when the user picks another catalog match from “Wrong card?”.
    var onPickAlternative: (Card) -> Void

    @State private var selectedVariant: String = ""
    @State private var showWrongCardSheet = false
    /// Market price for `selectedVariant` (raw), formatted with `PriceDisplaySettings`.
    @State private var barVariantPriceText: String = "—"
    @State private var addToCollectionPayload: AddToCollectionSheetPayload?
    @State private var wishlistFeedback: WishlistFeedback?
    @State private var dragOffset: CGFloat = 0
    /// Vertical scroll offset from `onScrollGeometryChange` — collapse only when near top.
    @State private var expandedScrollOffsetY: CGFloat = 0

    private var card: Card { result.card }

    private var showExpanded: Bool { isCurrentPage && isExpanded }

    /// Filled wishlist star — matches `CardBrowseDetailView` (gold, not accent blue).
    private static let wishlistStarGold = Color(red: 0.98, green: 0.78, blue: 0.18)

    /// `contentOffset.y` at/near top; allow small float / inset so we don’t collapse while scrolled.
    private static let expandedScrollTopTolerance: CGFloat = 20

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

    var body: some View {
        VStack(spacing: 0) {
            handleBar

            if showExpanded {
                ScrollView(showsIndicators: false) {
                    ScannerResultExpandedContent(card: card, topPadding: 8)
                }
                .frame(maxHeight: maxExpandedContentHeight)
                .onScrollGeometryChange(for: CGFloat.self) { geo in
                    geo.contentOffset.y
                } action: { _, y in
                    expandedScrollOffsetY = y
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if !showExpanded {
                // Card row — trailing: market price for selected variant (swipe up still expands via handle / drag)
                HStack(spacing: 14) {
                    cardThumbnail
                    cardInfo
                    Spacer(minLength: 8)
                    Text(barVariantPriceText)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
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
                }
            }

            if let feedback = wishlistFeedback {
                HStack(spacing: 6) {
                    Image(systemName: feedback.icon).foregroundStyle(feedback.color)
                    Text(feedback.message).font(.subheadline).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            actionButtons
                .padding(.top, showExpanded ? 10 : 14)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .offset(y: showExpanded ? 0 : min(0, dragOffset))
        // Simultaneous + axis check so parent can receive horizontal drags for multi-result paging.
        .simultaneousGesture(barVerticalDragGesture)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: showExpanded)
        .onChange(of: showExpanded) { _, expanded in
            if expanded { expandedScrollOffsetY = 0 }
        }
        .onAppear {
            selectedVariant = variants.first ?? "normal"
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
        .sheet(item: $addToCollectionPayload) { payload in
            AddToCollectionSheet(card: payload.card, variantKey: payload.variantKey)
                .environment(services)
        }
    }

    private var handleBar: some View {
        Button {
            guard isCurrentPage else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
                isExpanded.toggle()
            }
            HapticManager.impact(.light)
        } label: {
            VStack(spacing: 10) {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 4)
                Image(systemName: showExpanded ? "chevron.compact.down" : "chevron.compact.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.top, 10)
            .padding(.bottom, showExpanded ? 8 : 14)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var barVerticalDragGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard isCurrentPage else { return }
                // Let horizontal swipes pass through to the carousel in `CardScannerView`.
                guard abs(value.translation.height) >= abs(value.translation.width) - 2 else { return }
                if showExpanded { return }
                if value.translation.height < 0 {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                guard isCurrentPage else { return }
                let verticalIntent = abs(value.translation.height) >= abs(value.translation.width) - 2
                if showExpanded {
                    guard verticalIntent else { return }
                    // Only dismiss the expanded panel when detail scroll is at the top (not mid-scroll).
                    guard expandedScrollOffsetY <= Self.expandedScrollTopTolerance else { return }
                    if value.translation.height > 56 || value.predictedEndTranslation.height > 120 {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
                            isExpanded = false
                        }
                        HapticManager.impact(.light)
                    }
                    return
                }
                guard verticalIntent else { return }
                if value.translation.height < -50 || value.predictedEndTranslation.height < -120 {
                    dragOffset = 0
                    HapticManager.impact(.light)
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        isExpanded = true
                    }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        dragOffset = 0
                    }
                }
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
                .fill(Color.white.opacity(0.08))
                .frame(width: 52, height: 72)
        }
        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
    }

    // MARK: - Card info

    private var cardInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.cardName)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(card.setCode.uppercased() + " · #" + card.cardNumber)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
            if let rarity = card.rarity {
                Text(rarity)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
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
                            .foregroundStyle(isSelected ? .black : .white.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(isSelected ? Color.white : Color.white.opacity(0.12)))
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
            actionButton(icon: "plus.circle.fill", label: "Collection", style: .secondary) {
                addToCollectionPayload = AddToCollectionSheetPayload(card: card, variantKey: selectedVariant)
            }
            wishlistActionButton
            actionButton(icon: "questionmark.circle.fill", label: "Wrong card?", style: .primary) {
                guard isCurrentPage else { return }
                showWrongCardSheet = true
                HapticManager.impact(.light)
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
                    .foregroundStyle(isCurrentVariantWishlisted ? Self.wishlistStarGold : Color.white)
                Text("Wishlist")
                    .font(.system(size: 11, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.12))
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
            .foregroundStyle(style == .primary ? .black : .white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(style == .primary ? Color.white : Color.white.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Wishlist

    private func toggleWishlist() {
        guard let wishlist = services.wishlist else { return }
        if isCurrentVariantWishlisted {
            do {
                try wishlist.removeCardVariant(cardID: card.masterCardId, variantKey: selectedVariant)
                show(feedback: .removed)
                HapticManager.impact(.light)
            } catch {
                show(feedback: .error(error.localizedDescription))
            }
            return
        }
        do {
            try wishlist.addItem(cardID: card.masterCardId, variantKey: selectedVariant)
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
                        description: Text("There aren’t other catalog candidates for this scan. Try scanning again with clearer lighting or a steadier frame.")
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
