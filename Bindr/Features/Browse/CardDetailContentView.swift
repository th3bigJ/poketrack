import SwiftData
import SwiftUI

enum CardDetailContentSection: String, CaseIterable, Identifiable {
    case pricing = "Pricing"
    case details = "Card Details"

    var id: String { rawValue }
}

struct CardDetailCollectionScope<Content: View>: View {
    @Query private var collectionItems: [CollectionItem]
    @Query private var ledgerLines: [LedgerLine]

    private let content: ([CollectionItem], [LedgerLine]) -> Content

    init(
        card: Card,
        @ViewBuilder content: @escaping ([CollectionItem], [LedgerLine]) -> Content
    ) {
        let cardID = card.masterCardId
        _collectionItems = Query(
            filter: #Predicate<CollectionItem> { item in
                item.cardID == cardID
            },
            sort: [SortDescriptor(\.variantKey)]
        )
        _ledgerLines = Query(
            filter: #Predicate<LedgerLine> { line in
                line.cardID == cardID
            },
            sort: [SortDescriptor(\.occurredAt, order: .reverse)]
        )
        self.content = content
    }

    var body: some View {
        content(
            collectionItems.filter { $0.quantity > 0 },
            ledgerLines
        )
    }
}

struct CardDetailContentActions {
    var onDismiss: () -> Void
    var onToggleWishlist: () -> Void
    var onShare: () -> Void
    var onOpenImage: () -> Void
    var onOpenSet: (() -> Void)?
    var onAddToCollection: (String) -> Void
    var onRemoveFromCollection: () -> Void
    var onOpenHolding: (HoldingLine) -> Void
    var onOpenEbay: () -> Void
}

struct CardDetailContentView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    let card: Card
    let set: TCGSet?
    let availableVariantKeys: [String]
    let isWishlisted: Bool
    let showsCollectionActions: Bool
    let showsWishlistAction: Bool
    let addToDeckAction: ((Card, String, Int) -> Void)?
    let directTradeContext: CardTradeContext?
    let actions: CardDetailContentActions



    private var hasStats: Bool {
        card.hp != nil || !cleanedTypes(card.elementTypes).isEmpty || card.weakness != nil || card.resistance != nil || card.retreatCost != nil
    }



    private func groupedHoldings(
        collectionItems: [CollectionItem],
        ledgerLines: [LedgerLine]
    ) -> [HoldingGroup] {
        HoldingGroup.grouped(
            for: card.masterCardId,
            from: collectionItems,
            ledgerLines: ledgerLines
        )
    }

    private func isOwned(
        collectionItems: [CollectionItem],
        ledgerLines: [LedgerLine]
    ) -> Bool {
        !collectionItems.isEmpty || !groupedHoldings(collectionItems: collectionItems, ledgerLines: ledgerLines).isEmpty
    }

    private var preferredVariantKey: String {
        if availableVariantKeys.contains("normal") { return "normal" }
        return availableVariantKeys.first ?? "normal"
    }

    private var facts: [(String, String)] {
        var output: [(String, String)] = []
        appendFact("Number", cleaned(card.printedNumber) ?? cleaned(card.cardNumber), to: &output)
        appendFact("Rarity", cleaned(card.rarity), to: &output)
        appendFact("Category", cleaned(card.category), to: &output)
        appendFact("HP", card.hp.map(String.init), to: &output)
        appendFact("Type", cleanedList(card.elementTypes), to: &output)
        appendFact("Subtype", cleanedList(card.subtypes) ?? cleaned(card.subtype), to: &output)
        appendFact("Regulation", cleaned(card.regulationMark), to: &output)
        appendFact("Artist", cleaned(card.artist), to: &output)
        appendFact("Retreat", card.retreatCost.map(String.init), to: &output)
        return output
    }

    var body: some View {
        CardDetailCollectionScope(card: card) { collectionItems, ledgerLines in
            scopedBody(collectionItems: collectionItems, ledgerLines: ledgerLines)
        }
        .id(card.masterCardId)
    }

    @ViewBuilder
    private func scopedBody(
        collectionItems: [CollectionItem],
        ledgerLines: [LedgerLine]
    ) -> some View {
        GeometryReader { geo in
            let contentWidth = geo.size.width - 32
            let owned = isOwned(collectionItems: collectionItems, ledgerLines: ledgerLines)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    navigationChrome
                    heroSection(
                        contentWidth: contentWidth,
                        collectionItems: collectionItems,
                        ledgerLines: ledgerLines
                    )

                    CardPricingPanel(
                        card: card,
                        useGlass: true,
                        chartHeight: chartHeight(contentWidth: contentWidth, viewportHeight: geo.size.height),
                        chartAccent: resolvedTypeAccent
                    )

                    if owned {
                        sectionDivider
                        collectionSection(collectionItems: collectionItems, ledgerLines: ledgerLines)
                    }

                    sectionDivider
                    ebayRow

                    if addToDeckAction == nil {
                        sectionDivider
                        CardFriendTradeMatchesSection(
                            card: card,
                            directContext: directTradeContext,
                            maximumMatches: 1
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .overlay(alignment: .top) { dragPill }
        }
        .background(.clear)
    }

    /// Slim grabber pinned to the very top so the user knows the sheet swipes away.
    private var dragPill: some View {
        Capsule(style: .continuous)
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.35 : 0.22))
            .frame(width: 38, height: 5)
            .padding(.top, 8)
            .allowsHitTesting(false)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 1)
    }

    /// Backdrop wash derived from the card's primary Pokémon type. `nil` (Colorless /
    /// Normal / typeless) falls back to the user's selected app theme.
    var typeBackgroundAccent: Color? {
        guard let first = cleanedTypes(card.elementTypes).first else { return nil }
        return PokemonTypeBadge.backgroundAccent(for: first)
    }

    private var resolvedTypeAccent: Color {
        typeBackgroundAccent ?? services.theme.chartAccentColor
    }

    /// Shortens the chart so the hero image, price and chart land on one screen.
    private func chartHeight(contentWidth: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        guard viewportHeight > 0 else { return 180 }
        let imageWidth = max(0, (contentWidth - 16) * 0.5)
        let heroHeight = imageWidth * 7.0 / 5.0
        // Reserve room for the price block, range picker and inter-section spacing.
        let reserved: CGFloat = heroHeight + 248
        return min(130, max(100, viewportHeight - reserved))
    }

    private var navigationChrome: some View {
        HStack {
            detailCircleButton(
                systemImage: "chevron.left",
                accessibilityLabel: "Close card details",
                action: actions.onDismiss
            )

            Spacer()

            if showsWishlistAction {
                detailCircleButton(
                    systemImage: isWishlisted ? "star.fill" : "star",
                    accessibilityLabel: isWishlisted ? "Remove from wishlist" : "Add to wishlist",
                    foreground: isWishlisted ? Color(red: 0.98, green: 0.78, blue: 0.18) : .primary,
                    action: actions.onToggleWishlist
                )
            }

            detailCircleButton(
                systemImage: "square.and.arrow.up",
                accessibilityLabel: "Share card",
                action: actions.onShare
            )
        }
        .frame(height: 42)
    }

    private func heroSection(
        contentWidth: CGFloat,
        collectionItems: [CollectionItem],
        ledgerLines: [LedgerLine]
    ) -> some View {
        let spacing: CGFloat = 16
        let imageWidth = max(0, (contentWidth - spacing) * 0.5)
        let imageHeight = imageWidth * 7.0 / 5.0
        return HStack(alignment: .top, spacing: spacing) {
            cardImage(width: imageWidth)

            VStack(alignment: .leading, spacing: 10) {
                titleBlock
                
                if hasStats {
                    primaryStatsContainer
                    secondaryStatsContainer
                }
                
                actionBar(collectionItems: collectionItems, ledgerLines: ledgerLines)
            }
            .frame(minHeight: imageHeight, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private func cardImage(width: CGFloat) -> some View {
        Button {
            actions.onOpenImage()
            Haptics.lightImpact()
        } label: {
            CachedAsyncImage(
                url: AppConfiguration.imageURL(relativePath: card.displayImageSrc),
                targetSize: CGSize(width: 520, height: 728)
            ) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                    .aspectRatio(5 / 7, contentMode: .fit)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.15 : 0.40), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View card image full screen")
        .frame(width: width)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.cardName)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            HStack(alignment: .center, spacing: 8) {
                if let number = cleaned(card.printedNumber) ?? cleaned(card.cardNumber) {
                    Text("#\(number)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if let rarity = cleaned(card.rarity) {
                    Text(rarity.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
                        )
                }
            }

            if let set {
                SetLogoAsyncImage(
                    logoSrc: set.logoSrc,
                    height: 22,
                    brand: TCGBrand.inferredFromMasterCardId(card.masterCardId),
                    alignment: .leading
                )
                .frame(height: 26)
                .accessibilityLabel(set.name)
                .padding(.vertical, 4)
            }
        }
    }

    private var primaryStatsContainer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                Text("HP")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("Type")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("Weak.")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            HStack(spacing: 0) {
                Text(card.hp.map(String.init) ?? "—")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: 4) {
                    let types = cleanedTypes(card.elementTypes)
                    if types.isEmpty {
                        Text("—")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                    } else {
                        ForEach(Array(types.prefix(2)), id: \.self) { type in
                            PokemonTypeBadge(type: type, size: 20)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: 4) {
                    if let parsed = parseAffinity(card.weakness) {
                        PokemonTypeBadge(type: parsed.type, size: 20)
                        if let modifier = parsed.modifier {
                            Text(modifier)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                        }
                    } else {
                        Text("—")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var secondaryStatsContainer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                Text("Resistance")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("Retreat")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    if let parsed = parseAffinity(card.resistance) {
                        PokemonTypeBadge(type: parsed.type, size: 20)
                        if let modifier = parsed.modifier {
                            Text(modifier)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                        }
                    } else {
                        Text("—")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(card.retreatCost.map(String.init) ?? "—")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }



    private func cleanedTypes(_ values: [String]?) -> [String] {
        (values ?? []).compactMap { cleaned($0) }
    }

    /// Splits a weakness/resistance string such as `"Lightning ×2"` or `"Fighting -20"`
    /// into its Pokémon type and the trailing modifier text.
    private func parseAffinity(_ raw: String?) -> (type: String, modifier: String?)? {
        guard let raw = cleaned(raw) else { return nil }
        let knownTypes = ["Grass", "Fire", "Water", "Lightning", "Psychic", "Fighting", "Darkness", "Metal", "Dragon", "Fairy", "Colorless"]
        for type in knownTypes where raw.localizedCaseInsensitiveContains(type) {
            var remainder = raw
            if let range = remainder.range(of: type, options: .caseInsensitive) {
                remainder.removeSubrange(range)
            }
            let modifier = remainder.trimmingCharacters(in: .whitespaces)
            return (type, modifier.isEmpty ? nil : modifier)
        }
        let parts = raw.split(separator: " ", maxSplits: 1).map(String.init)
        if parts.count == 2 { return (parts[0], parts[1]) }
        return (raw, nil)
    }

    private static let collectionGreen = Color(red: 0.12, green: 0.67, blue: 0.28)

      /// Remove appears when the card is already in the collection; add stays available for extra copies.
    @ViewBuilder
    private func actionBar(
        collectionItems: [CollectionItem],
        ledgerLines: [LedgerLine]
    ) -> some View {
        let owned = isOwned(collectionItems: collectionItems, ledgerLines: ledgerLines)
        HStack(spacing: 8) {
            if let addToDeckAction {
                Button {
                    addToDeckAction(card, preferredVariantKey, 1)
                    Haptics.lightImpact()
                } label: {
                    compactActionLabel(
                        title: "Add to Deck",
                        systemImage: "plus.circle.fill",
                        tint: services.theme.chartAccentColor,
                        filled: true
                    )
                }
                .buttonStyle(.plain)
            } else if showsCollectionActions {
                addToCollectionButton(isOwned: owned)

                if owned {
                    Button {
                        actions.onRemoveFromCollection()
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(red: 0.88, green: 0.22, blue: 0.24))
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(red: 0.95, green: 0.27, blue: 0.27).opacity(0.12))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color(red: 0.95, green: 0.27, blue: 0.27).opacity(0.30), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove from Collection")
                }
            }
        }
    }

    @ViewBuilder
    private func addToCollectionButton(isOwned: Bool) -> some View {
        let title = isOwned ? "Add Copy" : "Add to Collection"
        if availableVariantKeys.count > 1 {
            Menu {
                ForEach(availableVariantKeys, id: \.self) { key in
                    Button(variantTitle(key)) {
                        actions.onAddToCollection(key)
                    }
                }
            } label: {
                compactActionLabel(
                    title: title,
                    systemImage: "plus.circle.fill",
                    tint: Self.collectionGreen,
                    filled: true
                )
            }
        } else {
            Button {
                actions.onAddToCollection(preferredVariantKey)
            } label: {
                compactActionLabel(
                    title: title,
                    systemImage: "plus.circle.fill",
                    tint: Self.collectionGreen,
                    filled: true
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func compactActionLabel(
        title: String,
        systemImage: String,
        tint: Color,
        filled: Bool
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(filled ? Color.white : tint)
            .padding(.horizontal, 20)
            .frame(height: 44)
            .background(filled ? tint : tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                ForEach(facts, id: \.0) { fact in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(fact.0)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(fact.1)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                    .padding(10)
                    .glassInsetStyle(cornerRadius: 14)
                }
            }

            if let attacks = card.attacks, !attacks.isEmpty {
                detailSectionTitle("Attacks")
                VStack(spacing: 10) {
                    ForEach(Array(attacks.enumerated()), id: \.offset) { _, attack in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(attack.name)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                if let damage = cleaned(attack.damage) {
                                    Text(damage)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(services.theme.chartAccentColor)
                                }
                            }
                            if let effect = cleaned(attack.effect) {
                                Text(effect)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .glassInsetStyle(cornerRadius: 16)
                    }
                }
            }

            if let flavorText = cleaned(card.flavorText) {
                detailSectionTitle("Flavor Text")
                Text(flavorText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .glassInsetStyle(cornerRadius: 16)
            }
        }
    }

    private func collectionSection(
        collectionItems: [CollectionItem],
        ledgerLines: [LedgerLine]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your Collection")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Self.collectionGreen)

            ForEach(groupedHoldings(collectionItems: collectionItems, ledgerLines: ledgerLines)) { group in
                let primaryLine = group.lines.first
                Button {
                    if let primaryLine {
                        actions.onOpenHolding(primaryLine)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(variantTitle(group.variantKey))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(services.theme.chartAccentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(services.theme.chartAccentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

                        collectionValue(label: "Qty", value: "\(group.totalQuantity)")
                        collectionValue(label: "Paid", value: primaryLine?.priceText ?? "—")
                        collectionValue(
                            label: "Added",
                            value: primaryLine?.date.formatted(date: .abbreviated, time: .omitted) ?? "—"
                        )

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var ebayRow: some View {
        Button {
            actions.onOpenEbay()
        } label: {
            HStack(spacing: 10) {
                ebayWordmark
                VStack(alignment: .leading, spacing: 1) {
                    Text("View on eBay")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("See latest listings and sold items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func detailCircleButton(
        systemImage: String,
        accessibilityLabel: String,
        foreground: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        ChromeGlassCircleButton(accessibilityLabel: accessibilityLabel, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(foreground)
        }
    }

    private func fullWidthActionLabel(
        title: String,
        systemImage: String,
        tint: Color,
        filled: Bool
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(filled ? Color.white : tint)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(filled ? tint : tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statColumn(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(title == "HP" ? Color.red : .secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(width: 1, height: 38)
    }

    private func collectionValue(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private var ebayWordmark: some View {
        HStack(spacing: 0) {
            Text("e").foregroundStyle(Color(red: 0.89, green: 0.15, blue: 0.13))
            Text("B").foregroundStyle(Color(red: 0.00, green: 0.38, blue: 0.75))
            Text("a").foregroundStyle(Color(red: 0.97, green: 0.74, blue: 0.06))
            Text("y").foregroundStyle(Color(red: 0.44, green: 0.68, blue: 0.11))
        }
        .font(.system(size: 20, weight: .bold, design: .rounded))
        .frame(width: 74, alignment: .leading)
    }

    private func variantTitle(_ key: String) -> String {
        let spaced = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return spaced.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func cleanedList(_ values: [String]?) -> String? {
        guard let values else { return nil }
        let items = values.compactMap(cleaned)
        return items.isEmpty ? nil : items.joined(separator: ", ")
    }

    private func appendFact(_ label: String, _ value: String?, to output: inout [(String, String)]) {
        if let value { output.append((label, value)) }
    }
}

/// Coloured circular Pokémon energy badge (icon glyph on a type-coloured circle).
/// The project has no official energy art assets, so this approximates each type with an
/// SF Symbol on the app's established type-colour palette.
struct PokemonTypeBadge: View {
    let type: String
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: Self.symbol(for: type))
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Self.color(for: type)))
            .accessibilityLabel(type)
    }

    static func color(for type: String) -> Color {
        switch type.lowercased() {
        case "fire":                  return Color(red: 0.94, green: 0.29, blue: 0.18)
        case "water":                 return Color(red: 0.22, green: 0.55, blue: 0.93)
        case "grass":                 return Color(red: 0.30, green: 0.72, blue: 0.38)
        case "lightning", "electric": return Color(red: 0.97, green: 0.78, blue: 0.18)
        case "psychic":               return Color(red: 0.66, green: 0.36, blue: 0.83)
        case "fighting":              return Color(red: 0.60, green: 0.36, blue: 0.22)
        case "darkness", "dark":      return Color(red: 0.22, green: 0.15, blue: 0.34)
        case "metal", "steel":        return Color(red: 0.58, green: 0.62, blue: 0.66)
        case "dragon":                return Color(red: 0.48, green: 0.12, blue: 0.14)
        case "fairy":                 return Color(red: 0.92, green: 0.45, blue: 0.66)
        case "colorless", "normal":   return Color(red: 0.68, green: 0.64, blue: 0.58)
        default:                      return Color(uiColor: .systemGray2)
        }
    }

    /// Subtle page-wash colour for the card detail backdrop, or `nil` to fall back
    /// to the app theme (Colorless / Normal / unknown types keep the user's theme).
    static func backgroundAccent(for type: String) -> Color? {
        switch type.lowercased() {
        case "fire", "water", "grass", "lightning", "electric", "psychic",
             "fighting", "darkness", "dark", "metal", "steel", "dragon", "fairy",
             "colorless", "normal":
            return color(for: type)
        default:
            return nil
        }
    }

    static func symbol(for type: String) -> String {
        switch type.lowercased() {
        case "fire":                  return "flame.fill"
        case "water":                 return "drop.fill"
        case "grass":                 return "leaf.fill"
        case "lightning", "electric": return "bolt.fill"
        case "psychic":               return "eye.fill"
        case "fighting":              return "figure.boxing"
        case "darkness", "dark":      return "moon.fill"
        case "metal", "steel":        return "gearshape.fill"
        case "dragon":                return "tornado"
        case "fairy":                 return "sparkles"
        case "colorless", "normal":   return "star.fill"
        default:                      return "circle.fill"
        }
    }
}

struct CardDetailTypeBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    let accent: Color

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            LinearGradient(
                colors: [
                    accent.opacity(colorScheme == .dark ? 0.34 : 0.30),
                    accent.opacity(colorScheme == .dark ? 0.24 : 0.20),
                    accent.opacity(colorScheme == .dark ? 0.15 : 0.11)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
