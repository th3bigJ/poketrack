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
                item.cardID == cardID && item.quantity > 0
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
        content(collectionItems, ledgerLines)
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

    @State private var activePage: CardDetailPage? = .landing

    /// Market price + daily change resolved once by the landing chart panel, then mirrored
    /// by the collapsed details header so the number is already present on swipe (no reload).
    @State private var resolvedPriceText: String = "—"
    @State private var resolvedDailyChange: Double? = nil

    private let collapsedCardWidth: CGFloat = 64
    private let chromeActionButtonDiameter: CGFloat = 48
    private let chromeActionButtonIconSize: CGFloat = 17

    private enum CardDetailPage: String, Hashable {
        case landing
        case details
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
        .onChange(of: card.masterCardId) { _, _ in
            activePage = .landing
        }
    }

    @ViewBuilder
    private func scopedBody(
        collectionItems: [CollectionItem],
        ledgerLines: [LedgerLine]
    ) -> some View {
        GeometryReader { geo in
            let contentWidth = geo.size.width - 32
            let owned = isOwned(collectionItems: collectionItems, ledgerLines: ledgerLines)
            let landingViewport = geo.size.height - topChromeHeight - swipeHintHeight
            let layout = landingLayoutMetrics(
                viewportHeight: landingViewport,
                contentWidth: contentWidth
            )
            let collapsedCardHeight = collapsedCardWidth * 7 / 5
            let detailsTopReservedHeight = collapsedCardHeight + 12
            let onDetailsPage = activePage == .details
            let showsDetailsChrome = onDetailsPage

            ScrollView {
                VStack(spacing: 0) {
                    landingPage(
                        cardWidth: layout.cardWidth,
                        chartHeight: layout.chartHeight,
                        collectionItems: collectionItems,
                        ledgerLines: ledgerLines
                    )
                    .containerRelativeFrame(.vertical)
                    .id(CardDetailPage.landing)
                    .scrollTransition(.animated(.smooth)) { content, phase in
                        content.opacity(phase.isIdentity ? 1 : 0)
                    }

                    detailsPage(
                        topReservedHeight: detailsTopReservedHeight,
                        owned: owned,
                        collectionItems: collectionItems,
                        ledgerLines: ledgerLines
                    )
                    .id(CardDetailPage.details)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(CardDetailPageSnapBehavior())
            .scrollPosition(id: $activePage, anchor: .top)
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 4) {
                    dragPill

                    navigationChrome(owned: owned)
                        .padding(.horizontal, 16)

                    if showsDetailsChrome {
                        detailsPageHeaderRow(collapsedCardHeight: collapsedCardHeight)
                            .padding(.horizontal, 16)
                            .transition(.opacity)
                    }
                }
                .padding(.bottom, 4)
                .background {
                    CardDetailTypeBackground(accent: resolvedTypeAccent)
                }
                .animation(.smooth(duration: 0.22), value: showsDetailsChrome)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !onDetailsPage {
                    swipeUpHintArea
                    .padding(.horizontal, 16)
                    .background {
                        CardDetailTypeBackground(accent: resolvedTypeAccent)
                    }
                    .transition(.opacity)
                }
            }
            .onChange(of: activePage) { _, page in
                guard page != nil else { return }
                Haptics.lightImpact()
            }
            .background {
                CardDetailTypeBackground(accent: resolvedTypeAccent)
                    .ignoresSafeArea()
            }
        }
    }

    private var topChromeHeight: CGFloat { 56 }
    private var swipeHintHeight: CGFloat { 64 }

    /// Slim grabber at the top of the header — indicates the sheet can be dismissed.
    private var dragPill: some View {
        Capsule(style: .continuous)
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.35 : 0.22))
            .frame(width: 38, height: 5)
            .padding(.top, 4)
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

    /// Sizes the card and chart so the landing screen fills the viewport on any device.
    private func landingLayoutMetrics(
        viewportHeight: CGFloat,
        contentWidth: CGFloat
    ) -> (cardWidth: CGFloat, chartHeight: CGFloat) {
        guard viewportHeight > 0 else { return (min(contentWidth * 0.88, 240), 120) }

        let priceHeadlineHeight: CGFloat = 96
        let chartChromeHeight: CGFloat = 44
        let chartBottomInset: CGFloat = 10
        let sectionSpacing: CGFloat = 6
        let priceBlockFixed = priceHeadlineHeight + chartChromeHeight + chartBottomInset + sectionSpacing

        var chartHeight: CGFloat = 128
        var cardWidth: CGFloat = min(contentWidth * 0.92, 360)

        for _ in 0..<2 {
            let heroAvailable = viewportHeight - priceBlockFixed - chartHeight
            cardWidth = min(contentWidth * 0.92, max(120, heroAvailable) * (5.0 / 7.0), 360)
            let cardHeight = cardWidth * 7.0 / 5.0
            let remaining = viewportHeight - priceBlockFixed - cardHeight - sectionSpacing
            chartHeight = max(96, min(172, remaining))
        }

        return (cardWidth, chartHeight)
    }

    private func navigationChrome(owned: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            glassCircleActionButton(
                accessibilityLabel: "Back",
                systemImage: "chevron.left",
                diameter: chromeActionButtonDiameter,
                iconSize: chromeActionButtonIconSize,
                action: actions.onDismiss
            )

            headerTitleBlock
                .frame(maxWidth: .infinity, alignment: .leading)

            headerActionButtons(owned: owned)
        }
        .frame(height: chromeActionButtonDiameter)
    }

    private var headerTitleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(card.cardName)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .accessibilityAddTraits(.isHeader)

            if let setTitle = headerSetTitle {
                Text(setTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
    }

    private var headerSetTitle: String? {
        cleaned(set?.name) ?? cleaned(card.setCode)
    }

    private var swipeUpHint: some View {
        Text("Swipe up for details")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Swipe up for details")
    }

    private var swipeUpHintArea: some View {
        VStack(spacing: 8) {
            sectionDivider
            swipeUpHint
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: swipeHintHeight, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture(perform: revealDetails)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            revealDetails()
        }
    }

    private func revealDetails() {
        guard activePage != .details else { return }
        withAnimation(.smooth(duration: 0.28)) {
            activePage = .details
        }
    }

    private func landingPage(
        cardWidth: CGFloat,
        chartHeight: CGFloat,
        collectionItems: [CollectionItem],
        ledgerLines: [LedgerLine]
    ) -> some View {
        VStack(spacing: 6) {
            cardImage(width: cardWidth)
                .frame(maxWidth: .infinity)

            CardPricingPanel(
                card: card,
                useGlass: true,
                chartHeight: chartHeight,
                chartAccent: resolvedTypeAccent,
                onPriceResolved: { text, change in
                    resolvedPriceText = text
                    resolvedDailyChange = change
                }
            )

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private func detailsPage(
        topReservedHeight: CGFloat,
        owned: Bool,
        collectionItems: [CollectionItem],
        ledgerLines: [LedgerLine]
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionDivider
            expandedDetailsGrid

            if owned {
                sectionDivider
                collectionSection(collectionItems: collectionItems, ledgerLines: ledgerLines)
            }

            sectionDivider
            footerLinksSection

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
        .padding(.top, topReservedHeight)
        .padding(.bottom, 32)
    }

    private func detailsPageHeaderRow(collapsedCardHeight: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 12) {
            cardImage(width: collapsedCardWidth)

            collapsedPriceLabel
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: collapsedCardHeight, alignment: .top)
    }

    /// Mirrors the landing chart panel's market price using the value already resolved on
    /// page one — no second pricing panel, no reload from "—", no chart carried over.
    private var collapsedPriceLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Market Price")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(resolvedPriceText)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.numericText())

            if let dailyChange = resolvedDailyChange {
                HStack(spacing: 5) {
                    Image(systemName: dailyChange >= 0 ? "arrow.up" : "arrow.down")
                    Text("\(String(format: "%.1f%%", abs(dailyChange))) today")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(dailyChange >= 0 ? Self.priceUpColor : Self.priceDownColor)
            }
        }
    }

    private static let priceUpColor = Color(red: 0.28, green: 0.84, blue: 0.39)
    private static let priceDownColor = Color(red: 1.0, green: 0.36, blue: 0.34)

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

    private var expandedDetailsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Card Details")
                .font(.headline)
                .foregroundStyle(.primary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                spacing: 10
            ) {
                ForEach(expandedDetailFacts, id: \.0) { fact in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fact.0)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        detailFactValue(label: fact.0, value: fact.1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
                    .padding(12)
                    .glassInsetStyle(cornerRadius: 14)
                }
            }
        }
    }

    private var expandedDetailFacts: [(String, String)] {
        var output: [(String, String)] = []
        appendFact("Number", cleaned(card.printedNumber).map { "#\($0)" } ?? cleaned(card.cardNumber).map { "#\($0)" }, to: &output)
        appendFact("HP", card.hp.map(String.init), to: &output)
        appendFact("Rarity", cleaned(card.rarity), to: &output)
        appendFact("Weakness", cleaned(card.weakness), to: &output)
        appendFact("Set Name", cleaned(set?.name), to: &output)
        appendFact("Resistance", cleaned(card.resistance), to: &output)
        appendFact("Type", cleanedList(card.elementTypes), to: &output)
        appendFact("Retreat Cost", card.retreatCost.map(String.init), to: &output)
        return output
    }

    @ViewBuilder
    private func detailFactValue(label: String, value: String) -> some View {
        switch label {
        case "Type":
            let types = cleanedTypes(card.elementTypes)
            if types.isEmpty {
                Text("—")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            } else {
                HStack(spacing: 4) {
                    ForEach(Array(types.prefix(2)), id: \.self) { type in
                        PokemonTypeBadge(type: type, size: 18)
                    }
                }
            }
        case "Weakness", "Resistance":
            if let parsed = parseAffinity(value) {
                HStack(spacing: 4) {
                    PokemonTypeBadge(type: parsed.type, size: 18)
                    if let modifier = parsed.modifier {
                        Text(modifier)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                    }
                }
            } else {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        default:
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }

    private var footerLinksSection: some View {
        VStack(spacing: 0) {
            footerLinkRow(
                title: "View on eBay",
                subtitle: "See latest listings and sold items",
                systemImage: "bag",
                tint: Color(red: 0.89, green: 0.15, blue: 0.13),
                action: actions.onOpenEbay
            )
            sectionDivider
            footerLinkRow(
                title: "Recent Sales",
                subtitle: "Browse completed eBay sales",
                systemImage: "clock.arrow.circlepath",
                tint: services.theme.chartAccentColor,
                action: actions.onOpenEbay
            )
            if let onOpenSet = actions.onOpenSet {
                sectionDivider
                footerLinkRow(
                    title: "Set Information",
                    subtitle: cleaned(set?.name) ?? card.setCode,
                    systemImage: "square.stack.3d.up",
                    tint: Color(red: 0.36, green: 0.61, blue: 0.97),
                    action: onOpenSet
                )
            }
        }
    }

    private func footerLinkRow(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private static let wishlistGold = Color(red: 0.98, green: 0.78, blue: 0.18)

    @ViewBuilder
    private func headerActionButtons(owned: Bool) -> some View {
        let diameter = chromeActionButtonDiameter
        let iconSize = chromeActionButtonIconSize
        let spacing: CGFloat = 10

        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: spacing) {
                    headerActionButtonContent(
                        owned: owned,
                        diameter: diameter,
                        iconSize: iconSize,
                        spacing: spacing
                    )
                }
            } else {
                headerActionButtonContent(
                    owned: owned,
                    diameter: diameter,
                    iconSize: iconSize,
                    spacing: spacing
                )
            }
        }
    }

    @ViewBuilder
    private func headerActionButtonContent(
        owned: Bool,
        diameter: CGFloat,
        iconSize: CGFloat,
        spacing: CGFloat
    ) -> some View {
        HStack(spacing: spacing) {
            if let addToDeckAction {
                glassCircleActionButton(
                    accessibilityLabel: "Add to deck",
                    systemImage: "plus",
                    diameter: diameter,
                    iconSize: iconSize,
                    action: {
                        addToDeckAction(card, preferredVariantKey, 1)
                        Haptics.lightImpact()
                    }
                )
            } else if showsCollectionActions {
                addToCollectionGlassButton(isOwned: owned, diameter: diameter, iconSize: iconSize)
            }

            if showsWishlistAction {
                glassCircleActionButton(
                    accessibilityLabel: isWishlisted ? "Remove from wish list" : "Add to wish list",
                    systemImage: isWishlisted ? "star.fill" : "star",
                    diameter: diameter,
                    iconSize: iconSize,
                    foreground: isWishlisted ? Self.wishlistGold : .primary,
                    action: actions.onToggleWishlist
                )
            }

            glassCircleActionButton(
                accessibilityLabel: "Share",
                systemImage: "square.and.arrow.up",
                diameter: diameter,
                iconSize: iconSize,
                action: actions.onShare
            )
        }
    }

    @ViewBuilder
    private func addToCollectionGlassButton(
        isOwned: Bool,
        diameter: CGFloat,
        iconSize: CGFloat
    ) -> some View {
        let label = isOwned ? "Add copy to collection" : "Add to collection"
        if availableVariantKeys.count > 1 {
            Menu {
                ForEach(availableVariantKeys, id: \.self) { key in
                    Button(variantTitle(key)) {
                        actions.onAddToCollection(key)
                    }
                }
            } label: {
                glassCircleActionLabel(systemImage: "plus", diameter: diameter, iconSize: iconSize)
            }
            .accessibilityLabel(label)
        } else {
            glassCircleActionButton(
                accessibilityLabel: label,
                systemImage: "plus",
                diameter: diameter,
                iconSize: iconSize,
                action: { actions.onAddToCollection(preferredVariantKey) }
            )
        }
    }

    private func glassCircleActionButton(
        accessibilityLabel: String,
        systemImage: String,
        diameter: CGFloat,
        iconSize: CGFloat,
        foreground: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(foreground)
                .modifier(CardDetailActionCircleModifier(tint: actionTint))
        }
        .buttonStyle(.plain)
        .frame(width: diameter, height: diameter)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }

    private func glassCircleActionLabel(
        systemImage: String,
        diameter: CGFloat,
        iconSize: CGFloat,
        foreground: Color = .primary
    ) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(foreground)
            .modifier(CardDetailActionCircleModifier(tint: actionTint))
            .frame(width: diameter, height: diameter)
    }

    private var actionTint: Color {
        resolvedTypeAccent
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Collection")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                Text("Variant")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Qty")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .leading)
                Text("Paid")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Added")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 12)
            }
            .padding(.horizontal, 4)

            ForEach(groupedHoldings(collectionItems: collectionItems, ledgerLines: ledgerLines)) { group in
                let primaryLine = group.lines.first
                Button {
                    if let primaryLine {
                        actions.onOpenHolding(primaryLine)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(variantTitle(group.variantKey))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)

                        Text("\(group.totalQuantity)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, alignment: .leading)

                        Text(primaryLine?.priceText ?? "—")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)

                        Text(primaryLine?.date.formatted(date: .abbreviated, time: .omitted) ?? "—")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func detailSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
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
        Color(uiColor: .systemBackground)
            .overlay(accent.opacity(colorScheme == .dark ? 0.18 : 0.13))
    }
}

private struct CardDetailPageSnapBehavior: ScrollTargetBehavior {
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let pageHeight = context.containerSize.height
        guard pageHeight > 0 else { return }

        let proposedY = target.rect.origin.y
        // Only snap around the landing↔details boundary. Once the gesture lands at or
        // past the details-page top, leave it untouched so a tall details page (e.g. an
        // owned card with the "Your Collection" section) scrolls freely all the way to the
        // friend-trade row at the bottom instead of snapping back up.
        guard proposedY < pageHeight else { return }
        target.rect.origin.y = proposedY < pageHeight * 0.42 ? 0 : pageHeight
    }
}

private struct CardDetailActionCircleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let tint: Color

    private let visualDiameter: CGFloat = 40

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .frame(width: visualDiameter, height: visualDiameter)
                .background {
                    circleFill
                }
                .glassEffect(Glass.clear.tint(tint.opacity(colorScheme == .dark ? 0.22 : 0.12)).interactive(), in: Circle())
                .overlay {
                    circleRim
                }
                .shadow(color: shadowColor, radius: 12, y: 6)
                .contentShape(Circle())
        } else {
            content
                .frame(width: visualDiameter, height: visualDiameter)
                .background {
                    circleFill
                }
                .overlay {
                    circleRim
                }
                .shadow(color: shadowColor, radius: 12, y: 6)
                .contentShape(Circle())
        }
    }

    private var circleFill: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay {
                Circle()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.04 : 0.22))
            }
            .overlay {
                Circle()
                    .fill(tint.opacity(colorScheme == .dark ? 0.18 : 0.10))
            }
    }

    private var circleRim: some View {
        Circle()
            .strokeBorder(borderColor, lineWidth: 0.75)
            .overlay(alignment: .topLeading) {
                Circle()
                    .strokeBorder(.white.opacity(colorScheme == .dark ? 0.12 : 0.48), lineWidth: 1)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
    }

    private var borderColor: Color {
        colorScheme == .dark ? .white.opacity(0.14) : .black.opacity(0.06)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.22) : .black.opacity(0.10)
    }
}
