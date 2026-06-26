import SwiftData
import SwiftUI

/// A sliding segmented picker. `.accentTrack` is the filled glass track used across
/// collection/social; `.pillLabel` is the browse-style row of text tabs with a pill on
/// the active item only.
enum SlidingSegmentedPickerStyle {
    case accentTrack
    case pillLabel
}

struct SlidingSegmentedPicker<SelectionValue: Hashable & Identifiable>: View {
    @Binding var selection: SelectionValue
    let items: [SelectionValue]
    let title: (SelectionValue) -> String
    var style: SlidingSegmentedPickerStyle = .accentTrack

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppServices.self) private var services
    @Namespace private var namespace

    var body: some View {
        switch style {
        case .accentTrack:
            accentTrackPicker
        case .pillLabel:
            pillLabelPicker
        }
    }

    private var accentTrackPicker: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let isSelected = selection == item

                Button {
                    if selection != item {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selection = item
                        }
                        Haptics.lightImpact()
                    }
                } label: {
                    Text(title(item))
                        .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? selectedForegroundColor : .primary.opacity(0.6))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)
                        .background {
                            if isSelected {
                                Capsule()
                                    .bindrAccentFill(services.theme.accentColor)
                                    .matchedGeometryEffect(id: "highlight", in: namespace)
                                    .shadow(
                                        color: (services.theme.isGradientThemeSelected ? services.theme.secondaryAccentColor : services.theme.accentColor).opacity(0.22),
                                        radius: 4,
                                        x: 0,
                                        y: 2
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassSegmentedTrackStyle()
    }

    private var pillLabelPicker: some View {
        HStack(spacing: 20) {
            ForEach(items) { item in
                let isSelected = selection == item

                Button {
                    if selection != item {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            selection = item
                        }
                        Haptics.lightImpact()
                    }
                } label: {
                    Text(title(item))
                        .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? pillLabelSelectedForeground : pillLabelInactiveForeground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background {
                            if isSelected {
                                Capsule(style: .continuous)
                                    .fill(pillLabelSelectedBackground)
                                    .matchedGeometryEffect(id: "pillHighlight", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectedForegroundColor: Color {
        services.theme.backgroundStyle == .classic && colorScheme == .dark ? .black : .white
    }

    private var pillLabelSelectedForeground: Color {
        .primary
    }

    private var pillLabelInactiveForeground: Color {
        Color(uiColor: .secondaryLabel)
    }

    private var pillLabelSelectedBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color.black.opacity(0.07)
    }
}

// MARK: - Shared card grid cell

/// Card cell for browse/collection grids.
///
/// Requires services and colorScheme as plain stored properties — no @Environment.
/// iOS 26 corrupts the attribute graph when @Environment is accessed during ForEach
/// item-update passes or lazy-container sizing. Plain stored lets are safe everywhere.
struct CardGridCell: View {
    let card: Card
    @ObservationIgnored private let services: AppServices
    let colorScheme: ColorScheme
    let accentColor: Color
    var gridOptions = BrowseGridOptions()
    var setName: String? = nil
    var isOwned = false
    var isWishlisted = false
    var ownedCountBadge: Int? = nil
    var alwaysShowOwnedCountBadge = false
    var variantLabel: String? = nil
    var variantPricingKey: String? = nil
    var footnote: String? = nil
    var footnoteLeadingAvatarURL: URL? = nil
    var postPriceFootnote: String? = nil
    var overridePrice: Double? = nil
    var gradeLabel: String? = nil
    var precomputedPriceLine: String? = nil

    init(
        card: Card,
        services: AppServices,
        colorScheme: ColorScheme,
        accentColor: Color,
        gridOptions: BrowseGridOptions = BrowseGridOptions(),
        setName: String? = nil,
        isOwned: Bool = false,
        isWishlisted: Bool = false,
        ownedCountBadge: Int? = nil,
        alwaysShowOwnedCountBadge: Bool = false,
        variantLabel: String? = nil,
        variantPricingKey: String? = nil,
        footnote: String? = nil,
        footnoteLeadingAvatarURL: URL? = nil,
        postPriceFootnote: String? = nil,
        overridePrice: Double? = nil,
        gradeLabel: String? = nil,
        precomputedPriceLine: String? = nil
    ) {
        self.card = card
        self.services = services
        self.colorScheme = colorScheme
        self.accentColor = accentColor
        self.gridOptions = gridOptions
        self.setName = setName
        self.isOwned = isOwned
        self.isWishlisted = isWishlisted
        self.ownedCountBadge = ownedCountBadge
        self.alwaysShowOwnedCountBadge = alwaysShowOwnedCountBadge
        self.variantLabel = variantLabel
        self.variantPricingKey = variantPricingKey
        self.footnote = footnote
        self.footnoteLeadingAvatarURL = footnoteLeadingAvatarURL
        self.postPriceFootnote = postPriceFootnote
        self.overridePrice = overridePrice
        self.gradeLabel = gradeLabel
        self.precomputedPriceLine = precomputedPriceLine
    }

    private var resolvedColorScheme: ColorScheme { colorScheme }

    private var showsFooter: Bool {
        (gridOptions.showOwned && !(footnote?.isEmpty ?? true))
            || !(postPriceFootnote?.isEmpty ?? true)
    }

    private var visibleOwnedCountBadge: Int? {
        guard let ownedCountBadge else { return nil }
        if ownedCountBadge > 1 {
            return min(max(ownedCountBadge, 2), 999)
        }
        if (isOwned || alwaysShowOwnedCountBadge) && ownedCountBadge == 1 {
            return 1
        }
        return nil
    }

    private var wishlistBorderColor: Color {
        Color(red: 0.99, green: 0.72, blue: 0.22)
    }

    private var cardBorderColor: Color {
        if isOwned { return accentColor }
        if isWishlisted { return wishlistBorderColor }
        return .clear
    }

    private var cardBorderWidth: CGFloat {
        (isOwned || isWishlisted) ? 1.8 : 0
    }

    private var cardImageCornerRadius: CGFloat { 8 }

    private func safeImageURL(relativePath: String) -> URL? {
        AppConfiguration.resolvedImageURL(stored: relativePath)
    }

    private var trailingCardID: String {
        let number = card.cardNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return number.isEmpty ? card.setCode : number
    }

    private var offlineImageContext: OfflineImageContext {
        OfflineImageContext.snapshot(from: services)
    }

    private var resolvedImageURL: URL? {
        safeImageURL(relativePath: card.displayImageSrc)
    }

    private var imageLocalURL: URL? {
        guard let resolvedImageURL else { return nil }
        return offlineImageContext.localURL(for: resolvedImageURL)
    }

    private var footnoteAvatarLocalURL: URL? {
        guard let footnoteLeadingAvatarURL else { return nil }
        return offlineImageContext.localURL(for: footnoteLeadingAvatarURL)
    }

    var body: some View {
        CardGridCellLayout(
            card: card,
            cardName: card.cardName,
            services: services,
            gridOptions: gridOptions,
            setName: setName,
            isOwned: isOwned,
            isWishlisted: isWishlisted,
            variantLabel: variantLabel,
            variantPricingKey: variantPricingKey,
            footnote: footnote,
            footnoteLeadingAvatarURL: footnoteLeadingAvatarURL,
            footnoteAvatarLocalURL: footnoteAvatarLocalURL,
            postPriceFootnote: postPriceFootnote,
            overridePrice: overridePrice,
            gradeLabel: gradeLabel,
            precomputedPriceLine: precomputedPriceLine,
            showsFooter: showsFooter,
            visibleOwnedCountBadge: visibleOwnedCountBadge,
            cardBorderColor: cardBorderColor,
            cardBorderWidth: cardBorderWidth,
            cardImageCornerRadius: cardImageCornerRadius,
            trailingCardID: trailingCardID,
            accentColor: accentColor,
            colorScheme: resolvedColorScheme,
            imageURL: resolvedImageURL,
            imageLocalURL: imageLocalURL,
            imageReloadToken: offlineImageContext.gridReloadToken
        )
    }

    static func pokemonTypeColor(_ type: String) -> Color {
        switch type {
        case "Fire":       return Color(hex: "F26B3A")
        case "Water":      return Color(hex: "4A90E2")
        case "Grass":      return Color(hex: "5BB85B")
        case "Lightning":  return Color(hex: "F2C744")
        case "Psychic":    return Color(hex: "C25BB5")
        case "Fighting":   return Color(hex: "C24A3A")
        case "Darkness":   return Color(hex: "5B4A52")
        case "Metal":      return Color(hex: "8C95A8")
        case "Dragon":     return Color(hex: "7C5BC2")
        case "Fairy":      return Color(hex: "E58CB0")
        case "Colorless":  return Color(hex: "A8A89A")
        default:           return Color(hex: "A8A89A")
        }
    }
}

/// Renders the visual card tile with all computed values pre-resolved.
/// Keeping all layout work in a plain struct with no @Environment lookups
/// avoids the iOS 26 attribute graph crash that occurs when SwiftUI tries
/// to resolve environment values during LazyVStack row measurement.
private struct CardGridCellLayout: View {
    let card: Card
    let cardName: String
    let services: AppServices
    let gridOptions: BrowseGridOptions
    let setName: String?
    let isOwned: Bool
    let isWishlisted: Bool
    let variantLabel: String?
    let variantPricingKey: String?
    let footnote: String?
    var footnoteLeadingAvatarURL: URL? = nil
    let footnoteAvatarLocalURL: URL?
    let postPriceFootnote: String?
    let overridePrice: Double?
    let gradeLabel: String?
    let precomputedPriceLine: String?
    let showsFooter: Bool
    let visibleOwnedCountBadge: Int?
    let cardBorderColor: Color
    let cardBorderWidth: CGFloat
    let cardImageCornerRadius: CGFloat
    let trailingCardID: String
    let accentColor: Color
    let colorScheme: ColorScheme
    let imageURL: URL?
    let imageLocalURL: URL?
    let imageReloadToken: String

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.55)
    }

    private var tertiaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.38)
    }

    private var showsMetadataHeader: Bool {
        gridOptions.showCardName
            || (gridOptions.showSetName && !(setName?.isEmpty ?? true))
            || gridOptions.showSetID
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsMetadataHeader {
                metadataHeader
            }

            BrowseCardThumbnailView(
                imageURL: imageURL,
                imageLocalURL: imageLocalURL,
                imageReloadToken: imageReloadToken,
                isOwned: isOwned,
                isWishlisted: isWishlisted,
                ownedCountBadge: visibleOwnedCountBadge,
                accentColor: accentColor,
                colorScheme: colorScheme
            )
            .aspectRatio(5/7, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: cardImageCornerRadius, style: .continuous))
            .overlay {
                if isOwned || isWishlisted {
                    RoundedRectangle(cornerRadius: cardImageCornerRadius, style: .continuous)
                        .stroke(cardBorderColor, lineWidth: cardBorderWidth)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if gridOptions.showPricing {
                    bottomLeadingPriceOverlay
                }
            }

            if showsFooter {
                VStack(spacing: 3) {
                    if gridOptions.showOwned, let footnote, !footnote.isEmpty {
                        footnoteRow(footnote)
                    }
                    if let postPriceFootnote, !postPriceFootnote.isEmpty {
                        footerText(postPriceFootnote, color: secondaryTextColor)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, BindrSpacing.xs)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var metadataHeader: some View {
        VStack(alignment: .center, spacing: 1) {
            if gridOptions.showCardName {
                Text(cardName)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                if let variantLabel, !variantLabel.isEmpty {
                    Text(variantLabel)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.secondary)
                }
            }
            if gridOptions.showSetName, let setName, !setName.isEmpty {
                Text(setName)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
            }
            if gridOptions.showSetID {
                Text(trailingCardID)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.tertiary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var bottomLeadingPriceOverlay: some View {
        BrowseGridPriceText(
            services: services,
            accentColor: accentColor,
            card: card,
            overridePrice: overridePrice,
            gradeLabel: gradeLabel,
            precomputedPriceLine: precomputedPriceLine,
            variantKey: variantPricingKey,
            alignment: .leading,
            overlayTextColor: .white
        )
        .cardGridPriceBadgeStyle()
    }

    private func footerText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .foregroundStyle(color)
    }

    @ViewBuilder
    private func footnoteRow(_ text: String) -> some View {
        if let url = footnoteLeadingAvatarURL {
            HStack(spacing: 3) {
                GridCardThumbnailImage(
                    url: url,
                    localURL: footnoteAvatarLocalURL,
                    reloadToken: imageReloadToken,
                    targetSize: CGSize(width: 22, height: 22)
                )
                .frame(width: 11, height: 11)
                .clipShape(Circle())
                footerText(text, color: secondaryTextColor)
            }
        } else {
            footerText(text, color: secondaryTextColor)
        }
    }
}

private struct BrowseCardThumbnailView: View {
    let imageURL: URL?
    let imageLocalURL: URL?
    let imageReloadToken: String
    var isOwned = false
    var isWishlisted = false
    var ownedCountBadge: Int? = nil
    var accentColor: Color = .accentColor
    let colorScheme: ColorScheme

    var body: some View {
        GridCardThumbnailImage(
            url: imageURL,
            localURL: imageLocalURL,
            reloadToken: imageReloadToken
        )
            .overlay(alignment: .bottomTrailing) {
                if let ownedCountBadge, ownedCountBadge >= 1 {
                    ownedBadge(count: ownedCountBadge)
                } else if !isOwned && isWishlisted {
                    wishlistBadge
                }
            }
    }

    private func ownedBadge(count: Int) -> some View {
        ZStack {
            Circle()
                .fill(accentColor)
                .frame(width: 24, height: 24)
            Text("x\(count)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(6)
    }

    private var wishlistBadge: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color(red: 0.98, green: 0.78, blue: 0.18))
            .frame(width: 20, height: 20)
            .background(
                Circle()
                    .fill(Color.black.opacity(0.72))
            )
            .padding(6)
    }
}

/// Subtle spring scale on press for all card grid cells — gives a premium tactile feel.
struct CardCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private struct BrowseCardRow: Identifiable {
    let id: Int
    let card: Card
    let setName: String?
}

struct MasterSetVariantRow: Identifiable {
    let id: String
    let card: Card
    let variant: String
}

/// Multi-column card grid with lazy cell loading.
///
/// Uses native `LazyVGrid` so only visible cells are built. Earlier iOS 26 crashes during
/// `measureEstimates` were caused by `@Environment` / `@Observable` reads inside grid cells
/// and by hand-rolled `LazyVStack` row measurement — cells now receive plain stored values only.
struct EagerVGrid<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    let columns: Int
    let spacing: CGFloat
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        let cols = max(columns, 1)
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: CardGridLayout.columnSpacing), count: cols),
            spacing: spacing
        ) {
            ForEach(items) { item in
                cell(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private actor BrowseGridPriceLineCache {
    static let shared = BrowseGridPriceLineCache()
    private var cache: [String: String] = [:]
    private let maxEntries = 4000

    func value(for key: String) -> String? {
        cache[key]
    }

    func set(_ value: String, for key: String) {
        cache[key] = value
        if cache.count > maxEntries, let keyToRemove = cache.keys.first {
            cache.removeValue(forKey: keyToRemove)
        }
    }
}

private struct BrowseFeedSnapshot {
    var cards: [Card] = []
    var rows: [BrowseCardRow] = []
    var hasMoreCardsToLoad = false
}

enum BrowseHomeTab: String, CaseIterable, Identifiable {
    case cards
    case sets
    case pokemon
    case products

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cards: return "Cards"
        case .sets: return "Sets"
        case .pokemon: return "Pokemon"
        case .products: return "Products"
        }
    }
}

enum BrowseInlineDetailRoute: Hashable {
    case set(TCGSet)
    case dex(dexId: Int, displayName: String)

    var title: String {
        switch self {
        case .set(let set):
            return set.name
        case .dex(_, let displayName):
            return displayName
        }
    }
}


private struct BrowseCardGridButton: View {
    let row: BrowseCardRow
    let gridOptions: BrowseGridOptions
    let isOwned: Bool
    let isWishlisted: Bool
    let ownedCountBadge: Int?
    let isMultiSelectActive: Bool
    @ObservationIgnored private let services: AppServices
    let accentColor: Color
    let colorScheme: ColorScheme
    let precomputedPriceLine: String?
    let browseFeedCards: [Card]
    let onPresentCard: (Card, [Card]) -> Void
    @Binding var multiSelectedCardIDs: Set<String>
    let onQuickAddRequested: (Card, CardContextAction) -> Void
    let onSelectMultipleRequested: (Card) -> Void

    init(
        row: BrowseCardRow,
        gridOptions: BrowseGridOptions,
        isOwned: Bool,
        isWishlisted: Bool,
        ownedCountBadge: Int?,
        isMultiSelectActive: Bool,
        services: AppServices,
        accentColor: Color,
        colorScheme: ColorScheme,
        precomputedPriceLine: String? = nil,
        browseFeedCards: [Card],
        onPresentCard: @escaping (Card, [Card]) -> Void,
        multiSelectedCardIDs: Binding<Set<String>>,
        onQuickAddRequested: @escaping (Card, CardContextAction) -> Void,
        onSelectMultipleRequested: @escaping (Card) -> Void
    ) {
        self.row = row
        self.gridOptions = gridOptions
        self.isOwned = isOwned
        self.isWishlisted = isWishlisted
        self.ownedCountBadge = ownedCountBadge
        self.isMultiSelectActive = isMultiSelectActive
        self.services = services
        self.accentColor = accentColor
        self.colorScheme = colorScheme
        self.precomputedPriceLine = precomputedPriceLine
        self.browseFeedCards = browseFeedCards
        self.onPresentCard = onPresentCard
        self._multiSelectedCardIDs = multiSelectedCardIDs
        self.onQuickAddRequested = onQuickAddRequested
        self.onSelectMultipleRequested = onSelectMultipleRequested
    }

    private var isSelected: Bool {
        multiSelectedCardIDs.contains(row.card.masterCardId)
    }

    var body: some View {
        Button {
            if isMultiSelectActive {
                if isSelected {
                    multiSelectedCardIDs.remove(row.card.masterCardId)
                } else {
                    multiSelectedCardIDs.insert(row.card.masterCardId)
                    HapticManager.impact(.light)
                }
            } else {
                onPresentCard(row.card, browseFeedCards)
            }
        } label: {
            CardGridCell(
                card: row.card,
                services: services,
                colorScheme: colorScheme,
                accentColor: accentColor,
                gridOptions: gridOptions,
                setName: row.setName,
                isOwned: isOwned,
                isWishlisted: isWishlisted,
                ownedCountBadge: ownedCountBadge,
                precomputedPriceLine: precomputedPriceLine
            )
            .overlay(alignment: .topTrailing) {
                if isMultiSelectActive {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.blue : Color.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                        .padding(6)
                }
            }
        }
        .buttonStyle(CardCellButtonStyle())
        .contextMenu {
            Button {
                onQuickAddRequested(row.card, .collection)
            } label: {
                Label("Add to Collection", systemImage: "books.vertical")
            }
            Button {
                onQuickAddRequested(row.card, .wishlist)
            } label: {
                Label("Add to Wishlist", systemImage: "heart")
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

@MainActor
struct BrowseView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.presentCard) private var presentCard
    @Environment(\.presentCardAtIndex) private var presentCardAtIndex
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    let collectionItems: [CollectionItem]

    @Binding var filters: BrowseCardGridFilters
    @Binding var inlineDetailFilters: BrowseCardGridFilters
    @Binding var gridOptions: BrowseGridOptions
    @Binding var filterResultCount: Int
    @Binding var filterEnergyOptions: [String]
    @Binding var filterRarityOptions: [String]
    @Binding var filterTrainerTypeOptions: [String]
    @Binding var inlineDetailFilterResultCount: Int
    @Binding var inlineDetailFilterEnergyOptions: [String]
    @Binding var inlineDetailFilterRarityOptions: [String]
    @Binding var inlineDetailFilterTrainerTypeOptions: [String]
    @Binding var selectedTab: BrowseHomeTab
    @Binding var inlineDetailRoute: BrowseInlineDetailRoute?
    @Binding var isMultiSelectActive: Bool
    @Binding var multiSelectedCardIDs: Set<String>

    @State private var shuffledRefs: [CardRef] = []
    @State private var nextRefIndex = 0
    @State private var displayedCards: [Card] = []
    @State private var displayedRows: [BrowseCardRow] = []
    @State private var allBrowseFilterCards: [BrowseFilterCard] = []
    @State private var catalogOrderedRefs: [CardRef] = []
    @State private var catalogDisplayedCards: [Card] = []
    @State private var catalogDisplayedRows: [BrowseCardRow] = []
    @State private var browseFeedSnapshot = BrowseFeedSnapshot()
    @State private var catalogNextIndex = 0
    @State private var isLoadingInitial = true
    @State private var isLoadingMore = false
    @State private var isPreparingFilterCatalog = false
    /// Prevents concurrent full-filter-index loads (background warm vs active filter feed).
    @State private var isLoadingFullCatalog = false
    @State private var filterTask: Task<Void, Never>? = nil
    @State private var loadedBrand: TCGBrand?
    @State private var cachedSetNameByCode: [String: String] = [:]
    @Binding var query: String
    @State private var inlineDetailCards: [Card] = []
    @State private var inlineDetailPriceByCardID: [String: Double] = [:]
    @State private var inlineDetailMasterPriceByCardID: [String: Double] = [:]
    @State private var inlineDetailVariantPriceByCardID: [String: [String: Double]] = [:]
    @State private var masterSetVariantRows: [MasterSetVariantRow] = []
    @State private var inlineDetailSetTrendChanges: (change1d: Double?, change7d: Double?, change30d: Double?) = (nil, nil, nil)
    @State private var inlineDetailQuery = ""
    @State private var inlineDetailLoading = false
    @State private var ownedCardIDsCache: Set<String> = []
    @State private var isUsingCatalogFeedSelection = false
    @State private var isInlineDetailPresented = false
    @State private var isViewVisible = false
    @State private var visibleBrowseResultCount = 0
    @State private var isBrowseBodyReady = false
    @State private var currentBrand: TCGBrand = .pokemon
    @State private var lastAutoLoadRowCount = 0
    @State private var multiSelectCollectionPayload: MultiSelectCollectionPayload?
    @State private var wishlistAlertMessage: String?
    @State private var showWishlistAlert = false
    @State private var showWishlistPaywall = false
    @State private var setCompletionMode: SetCompletionMode = .full
    @State private var lastSelectedSetCodeInSetsTab: String?
    @State private var setsTabScrollRestore: SetsTabScrollRestore?
    @State private var setRestoreToken: Int = 0
    @State private var pendingCardContextRequest: CardContextActionRequest?
    @State private var cachedCollectionItemsTotalQuantity: Int = 0

    private var inlineDetailPriceCacheTaskKey: Int {
        var h = Hasher()
        h.combine(currentBrand.rawValue)
        h.combine(inlineDetailCards.count)
        h.combine(inlineDetailCards.first?.masterCardId)
        h.combine(inlineDetailCards.last?.masterCardId)
        return h.finalize()
    }

    private var collectionOwnershipSnapshotKey: Int {
        var h = Hasher()
        h.combine(collectionItems.count)
        // Use cached total to avoid O(n) reduce on every @Query-triggered body render.
        h.combine(cachedCollectionItemsTotalQuantity)
        return h.finalize()
    }

    private var safeColumnCount: Int {
        min(max(gridOptions.columnCount, 1), 4)
    }

    private var visibleWishlistedCardIDs: Set<String> {
        Set((services.wishlist?.items ?? []).compactMap { item in
            let cardID = item.cardID
            let itemBrand = TCGBrand.inferredFromMasterCardId(cardID)
            return itemBrand == services.brandSettings.selectedCatalogBrand ? cardID : nil
        })
    }

    @State private var ownedQuantityByCardID: [String: Int] = [:]
    // Keyed by "masterCardId::variantKey" for per-variant ownership in the master set grid.
    @State private var ownedQuantityByCardVariant: [String: Int] = [:]
    @State private var ownedCardVariantKeys: Set<String> = []
    @State private var browsePriceLineByCardID: [String: String] = [:]

    private var multiSelectedCards: [Card] {
        var cardsByMasterID: [String: Card] = [:]
        for card in browseFeedSnapshot.cards {
            cardsByMasterID[card.masterCardId] = card
        }
        for card in inlineDetailCards {
            cardsByMasterID[card.masterCardId] = card
        }
        return multiSelectedCardIDs.compactMap { cardsByMasterID[$0] }
    }

    private static let initialBatchSize = 36
    private static let catalogInitialBatchSize = 36
    private static let pageSize = 18
    private static let prefetchBuffer = 8
    private static let resultCountFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    private var browseGridPriceTaskKey: Int {
        var h = Hasher()
        h.combine(isViewVisible)
        h.combine(selectedTab.rawValue)
        h.combine(gridOptions.showPricing)
        h.combine(browseFeedSnapshot.cards.count)
        h.combine(browseFeedSnapshot.cards.first?.masterCardId)
        h.combine(browseFeedSnapshot.cards.last?.masterCardId)
        h.combine(services.priceDisplay.currency.rawValue)
        h.combine(services.pricing.usdToGbp)
        h.combine(services.pricing.pricingCacheGeneration)
        return h.finalize()
    }

    var body: some View {
        Group {
            ZStack(alignment: .bottom) {
                if isBrowseBodyReady {
                    browseBodyContent
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }

                if isMultiSelectActive && !multiSelectedCardIDs.isEmpty {
                    multiSelectActionBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .bindrPageBackground()
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isMultiSelectActive && !multiSelectedCardIDs.isEmpty)
        .sheet(item: $multiSelectCollectionPayload) { payload in
            MultiSelectAddToCollectionSheet(cards: payload.cards)
                .environment(services)
        }
        .sheet(item: $pendingCardContextRequest) { req in
            CardContextActionSheet(request: req)
                .environment(services)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showWishlistPaywall) {
            PaywallSheet()
                .environment(services)
        }
        .alert("Wishlist", isPresented: $showWishlistAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(wishlistAlertMessage ?? "")
        }
        .onAppear {
            isViewVisible = true
            isInlineDetailPresented = (inlineDetailRoute != nil)
            currentBrand = services.brandSettings.selectedCatalogBrand
            cachedCollectionItemsTotalQuantity = collectionItems.reduce(0, { $0 + $1.quantity })
            if isBrowseBodyReady == false {
                Task { @MainActor in
                    await Task.yield()
                    guard isViewVisible else { return }
                    isBrowseBodyReady = true
                }
            }
            let brandSnapshot = services.brandSettings.selectedCatalogBrand
            Task { @MainActor in
                await Task.yield()
                guard isViewVisible else { return }
                await scheduleOwnedCardIDsRefresh(for: brandSnapshot)
                await scheduleBrowseInitialization(for: brandSnapshot)
            }
        }
        .onDisappear {
            isViewVisible = false
        }
        .onChange(of: collectionItems) { _, newItems in
            cachedCollectionItemsTotalQuantity = newItems.reduce(0, { $0 + $1.quantity })
        }
        .onChange(of: services.brandSettings.selectedCatalogBrand) { _, newBrand in
            currentBrand = newBrand
            Task { @MainActor in
                await Task.yield()
                guard isViewVisible else { return }
                await scheduleOwnedCardIDsRefresh(for: newBrand)
                await scheduleBrowseInitialization(for: newBrand)
            }
        }
        .onChange(of: collectionOwnershipSnapshotKey) { _, _ in
            let brandSnapshot = currentBrand
            Task { @MainActor in
                await Task.yield()
                guard isViewVisible else { return }
                await scheduleOwnedCardIDsRefresh(for: brandSnapshot)
            }
        }
        .onChange(of: filters) { _, newFilters in
            guard !isInlineDetailPresented else { return }
            let shouldUseCatalogFeed = selectedTab == .cards
                && (!query.isEmpty || newFilters.hasActiveFieldFilters || newFilters.hasActiveSort)
            Task { @MainActor in
                await Task.yield()
                guard isViewVisible else { return }
                handleBrowseFiltersChanged(usingCatalogFeed: shouldUseCatalogFeed)
            }
        }
        .onChange(of: query) { _, newQuery in
            guard selectedTab == .cards else { return }
            let shouldUseCatalogFeed = !newQuery.isEmpty || filters.hasActiveFieldFilters || filters.hasActiveSort
            Task { @MainActor in
                await Task.yield()
                guard isViewVisible else { return }
                handleBrowseFiltersChanged(usingCatalogFeed: shouldUseCatalogFeed)
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            Task { @MainActor in
                await Task.yield()
                guard isViewVisible else { return }
                query = ""
                if tabSupportsInlineDetail(newValue) == false {
                    inlineDetailRoute = nil
                }
                if newValue != .cards {
                    isUsingCatalogFeedSelection = false
                    syncFilterMenuState(usingCatalogFeed: false)
                } else {
                    let shouldUseCatalogFeed = !query.isEmpty || filters.hasActiveFieldFilters || filters.hasActiveSort
                    handleBrowseFiltersChanged(usingCatalogFeed: shouldUseCatalogFeed)
                }
            }
        }
        .onChange(of: inlineDetailRoute) { _, newValue in
            Task { @MainActor in
                await Task.yield()
                guard isViewVisible else { return }
                isInlineDetailPresented = (newValue != nil)
                inlineDetailQuery = ""
                inlineDetailPriceByCardID = [:]
                inlineDetailMasterPriceByCardID = [:]
                inlineDetailVariantPriceByCardID = [:]
                inlineDetailSetTrendChanges = (nil, nil, nil)
                if selectedTab == .sets, newValue == nil, let setCode = lastSelectedSetCodeInSetsTab {
                    setsTabScrollRestore = .scrollToSetRow(setCode: setCode)
                    setRestoreToken += 1
                }
                await loadInlineDetailIfNeeded(route: newValue)
            }
        }
        .task(id: inlineDetailPriceCacheTaskKey) {
            await refreshInlineDetailPriceCache()
        }
        .task(id: browseGridPriceTaskKey) {
            await refreshBrowseGridPriceLines()
        }
        .onChange(of: inlineDetailFilters.sortBy) { _, sortBy in
            guard sortBy == .price else { return }
            Task { @MainActor in
                await refreshInlineDetailPriceCache()
            }
        }
        .onChange(of: setCompletionMode) { _, _ in
            guard inlineDetailRoute != nil else { return }
            Task { @MainActor in
                await rebuildMasterSetVariantRows()
                await refreshInlineDetailPriceCache()
            }
        }
    }

    @MainActor
    private func scheduleBrowseInitialization(for selectedBrand: TCGBrand) async {
        guard isViewVisible else { return }
        let selectedTabSnapshot = selectedTab
        let querySnapshot = query
        // Use the currently restored state so persisted filters/search apply
        // immediately after a cold launch.
        let filtersSnapshot = filters
        let ownedCardIDsSnapshot = ownedCardIDsCache
        let shouldUseCatalogFeedOnStartup = selectedTabSnapshot == .cards
            && (!querySnapshot.isEmpty || filtersSnapshot.hasActiveFieldFilters || filtersSnapshot.hasActiveSort)
        isUsingCatalogFeedSelection = shouldUseCatalogFeedOnStartup
        await initializeBrowseData(
            for: selectedBrand,
            selectedTabSnapshot: selectedTabSnapshot,
            querySnapshot: querySnapshot,
            filtersSnapshot: filtersSnapshot,
            ownedCardIDsSnapshot: ownedCardIDsSnapshot,
            shouldUseCatalogFeedOnStartup: shouldUseCatalogFeedOnStartup
        )
    }

    @MainActor
    private func scheduleOwnedCardIDsRefresh(for brand: TCGBrand) async {
        guard isViewVisible else { return }
        await Task.yield()
        guard isViewVisible else { return }
        var ids = Set<String>(minimumCapacity: collectionItems.count)
        var qty = [String: Int](minimumCapacity: collectionItems.count)
        var variantQty = [String: Int](minimumCapacity: collectionItems.count)
        for item in collectionItems {
            guard item.quantity > 0 else { continue }
            guard TCGBrand.inferredFromMasterCardId(item.cardID) == brand else { continue }
            ids.insert(item.cardID)
            qty[item.cardID, default: 0] += item.quantity
            variantQty["\(item.cardID)::\(item.variantKey)", default: 0] += item.quantity
        }
        ownedCardIDsCache = ids
        ownedQuantityByCardID = qty
        ownedQuantityByCardVariant = variantQty
        ownedCardVariantKeys = Set(variantQty.keys)
        if isInlineDetailPresented {
            syncFilterMenuState(usingCatalogFeed: false)
        } else {
            // Avoid re-entering the feed-selection decision path from the
            // ownership refresh task; preserve current feed mode and only
            // rebuild catalog results when that mode is already active.
            if isUsingCatalogFeedSelection {
                guard isViewVisible else { return }
                await ensureAllBrowseFilterCardsLoaded(showsPreparingBanner: false)
                await rebuildCatalogFeedIfNeeded(
                    selectedTab: selectedTab,
                    query: query,
                    filters: filters,
                    brand: currentBrand,
                    ownedCardIDs: ownedCardIDsCache,
                    shouldUseCatalogFeed: true
                )
            } else {
                syncFilterMenuState(usingCatalogFeed: false)
            }
        }
    }

    @ViewBuilder
    private var browseBodyContent: some View {
        if selectedTab == .cards {
            cardsTabScrollView
        } else {
            auxiliaryTabScrollView
        }
    }

    @MainActor
    private func initializeBrowseData(
        for selectedBrand: TCGBrand,
        selectedTabSnapshot: BrowseHomeTab,
        querySnapshot: String,
        filtersSnapshot: BrowseCardGridFilters,
        ownedCardIDsSnapshot: Set<String>,
        shouldUseCatalogFeedOnStartup: Bool
    ) async {
        guard isViewVisible else { return }
        if loadedBrand != selectedBrand {
            shuffledRefs = []
            nextRefIndex = 0
            displayedCards = []
            displayedRows = []
            allBrowseFilterCards = []
            catalogOrderedRefs = []
            catalogDisplayedCards = []
            catalogDisplayedRows = []
            browseFeedSnapshot = BrowseFeedSnapshot()
            lastAutoLoadRowCount = 0
            catalogNextIndex = 0
            isLoadingInitial = true

            let catalogJustWarmed = services.consumeLightBrowseTabEntryIfNeeded()
            if catalogJustWarmed {
                // Bootstrap already loaded sets + first browse page.
            } else {
                services.cardData.resetBrowseFeedSessionOnly()
                await services.cardData.loadSets(preferSyncedCatalog: true)
            }
            guard isViewVisible else { return }
            cachedSetNameByCode = firstValueMap(services.cardData.sets, key: \.setCode, value: \.name)
            loadedBrand = selectedBrand
        } else if cachedSetNameByCode.isEmpty, services.cardData.sets.isEmpty == false {
            cachedSetNameByCode = firstValueMap(services.cardData.sets, key: \.setCode, value: \.name)
        }

        await Task.yield()
        await Task.yield()
        guard isViewVisible else { return }
        await bootstrapFeed(forceReshuffle: false)
        guard isViewVisible else { return }
        if shouldUseCatalogFeedOnStartup {
            await ensureAllBrowseFilterCardsLoaded(
                showsPreparingBanner: true,
                usingCatalogFeed: true
            )
            guard isViewVisible else { return }
            await rebuildCatalogFeedIfNeeded(
                selectedTab: selectedTabSnapshot,
                query: querySnapshot,
                filters: filtersSnapshot,
                brand: selectedBrand,
                ownedCardIDs: ownedCardIDsSnapshot,
                shouldUseCatalogFeed: shouldUseCatalogFeedOnStartup
            )
        }
        // Default shuffled feed does not need the full catalog index — filter cards load
        // lazily when the user applies search or filters (`handleBrowseFiltersChanged`).
    }

    @ViewBuilder
    private var browseCardGrid: some View {
        let snapshot = browseFeedSnapshot
        let usesCatalogFeed = isUsingCatalogFeedSelection
        let ownedQuantities = ownedQuantityByCardID
        let wishlistedIDs = visibleWishlistedCardIDs
        let accentColor = services.theme.accentColor
        let priceLines = browsePriceLineByCardID
        VStack(spacing: 0) {
            EagerVGrid(items: snapshot.rows, columns: safeColumnCount, spacing: BindrSpacing.cardGrid) { row in
                BrowseCardGridButton(
                    row: row,
                    gridOptions: gridOptions,
                    isOwned: ownedCardIDsCache.contains(row.card.masterCardId),
                    isWishlisted: wishlistedIDs.contains(row.card.masterCardId),
                    ownedCountBadge: ownedQuantities[row.card.masterCardId],
                    isMultiSelectActive: isMultiSelectActive,
                    services: services,
                    accentColor: accentColor,
                    colorScheme: colorScheme,
                    precomputedPriceLine: gridOptions.showPricing ? (priceLines[row.card.masterCardId] ?? "") : nil,
                    browseFeedCards: snapshot.cards,
                    onPresentCard: presentCard,
                    multiSelectedCardIDs: $multiSelectedCardIDs,
                    onQuickAddRequested: beginQuickAdd(card:action:),
                    onSelectMultipleRequested: beginSelectMultiple(with:)
                )
                .onAppear {
                    guard snapshot.hasMoreCardsToLoad else { return }
                    guard row.id >= max(snapshot.rows.count - safeColumnCount, 0) else { return }
                    guard snapshot.rows.count != lastAutoLoadRowCount else { return }
                    lastAutoLoadRowCount = snapshot.rows.count
                    Task { await loadNextPageIfNeeded(usingCatalogFeed: usesCatalogFeed) }
                }
            }
            if isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
        }
        .environment(\.browseFeedCards, snapshot.cards)
        .padding(.horizontal, BindrSpacing.cardGridScreenInset)
        .padding(.bottom, isMultiSelectActive && !multiSelectedCardIDs.isEmpty ? 96 : 16)
        .onChange(of: snapshot.rows.count) { _, newValue in
            if newValue < lastAutoLoadRowCount {
                lastAutoLoadRowCount = 0
            }
        }
    }

    private var formattedResultCount: String {
        Self.resultCountFormatter.string(from: NSNumber(value: visibleBrowseResultCount)) ?? "\(visibleBrowseResultCount)"
    }

    private var browseSearchPlaceholder: String {
        if let inlineDetailRoute {
            switch inlineDetailRoute {
            case .set:
                return "Search \(formattedResultCount) cards in set"
            case .dex:
                return "Search \(formattedResultCount) cards for Pokémon"
            }
        }
        switch selectedTab {
        case .cards:
            return "Search \(formattedResultCount) cards"
        case .sets:
            return "Search sets"
        case .pokemon:
            return "Search Pokémon"
        case .products:
            return "Search products"
        }
    }

    @ViewBuilder
    private var browseTabsRow: some View {
        if isInlineDetailPresented {
            EmptyView()
        } else {
            SlidingSegmentedPicker(
                selection: $selectedTab,
                items: BrowseHomeTab.allCases,
                title: { $0.title },
                style: .pillLabel
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private var browseSetSummaryRow: some View {
        if !inlineDetailLoading {
            if case .set(let set) = inlineDetailRoute {
                setProgressBar(for: set, cards: inlineDetailCards)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            } else if case .dex(let dexId, let displayName) = inlineDetailRoute {
                dexProgressBar(dexId: dexId, displayName: displayName, cards: inlineDetailCards)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
    }

    private var browseSearchRow: some View {
        BrowseInlineSearchField(
            title: browseSearchPlaceholder,
            text: isInlineDetailPresented ? $inlineDetailQuery : $query
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var browseResultCountRow: some View {
        if selectedTab == .cards || isInlineDetailPresented {
            EmptyView()
        }
    }

    private var cardsTabScrollView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Keeps first row clear of the overlaid search bar; spacer scrolls away so cards can pass under the glass.
                Color.clear
                    .frame(height: rootFloatingChromeInset)
                browseTabsRow
                browseSearchRow
                browseSetSummaryRow
                browseResultCountRow
                activeTabContent
                if selectedTab == .cards && isPreparingFilterCatalog {
                    ProgressView("Preparing filters…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                if selectedTab == .cards && isLoadingMore {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var auxiliaryTabScrollView: some View {
        ScrollViewReader { proxy in
            Group {
                if isInlineDetailPresented, inlineDetailRoute != nil {
                    auxiliaryInlineDetailScrollView
                } else {
                    auxiliaryTabListScrollView(proxy: proxy)
                }
            }
        }
    }

    /// Sets / Pokémon list browsing — scroll position is independent from inline set/dex grids.
    private func auxiliaryTabListScrollView(proxy: ScrollViewProxy) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: rootFloatingChromeInset)
                    .id(browseAuxTopAnchorID())
                browseTabsRow
                browseSearchRow
                browseSetSummaryRow
                browseResultCountRow
                activeTabContent
            }
            .scrollTargetLayout()
        }
        .onChange(of: setRestoreToken) { _, _ in
            guard let restore = setsTabScrollRestore else { return }
            setsTabScrollRestore = nil
            Task { @MainActor in
                guard case .scrollToSetRow(let setCode) = restore else { return }
                let rowID = browseSetRowScrollID(setCode: setCode)
                for attempt in 0..<6 {
                    if attempt > 0 {
                        try? await Task.sleep(for: .milliseconds(40))
                    }
                    await Task.yield()
                    proxy.scrollTo(rowID, anchor: .center)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Inline set/dex card grid — own `ScrollView` so grid scrolling does not move the sets list underneath.
    private var auxiliaryInlineDetailScrollView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Spacer scrolls away so cards pass under the floating glass chrome, matching the Cards tab.
                Color.clear
                    .frame(height: rootFloatingChromeInset)
                browseSearchRow
                browseSetSummaryRow
                browseResultCountRow
                if let inlineDetailRoute {
                    inlineDetailContent(route: inlineDetailRoute)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var activeTabContent: some View {
        switch selectedTab {
        case .cards:
            browseCardsContent
        case .sets:
            BrowseSetsTabContent(query: query, setCompletionMode: $setCompletionMode) { set in
                HapticManager.impact(.light)
                lastSelectedSetCodeInSetsTab = set.setCode
                inlineDetailRoute = .set(set)
            }
        case .pokemon:
            BrowsePokemonTabContent(query: query) { route in
                HapticManager.impact(.light)
                inlineDetailRoute = route
            }
        case .products:
            BrowseProductsTabContent(query: query, filters: filters, gridOptions: gridOptions)
        }
    }

    @ViewBuilder
    private func inlineDetailContent(route: BrowseInlineDetailRoute) -> some View {
        let filteredCards = filteredInlineDetailCards
        let isSetRoute: Bool = { if case .set = route { return true }; return false }()
        let isDexRoute: Bool = { if case .dex = route { return true }; return false }()
        let useMasterGrid = setCompletionMode.usesVariantGrid && (isSetRoute || isDexRoute)
        let allVariantRows = useMasterGrid ? masterSetVariantRows : []
        let variantOwnedQuantities = ownedQuantityByCardVariant
        let variantOwnedKeys = ownedCardVariantKeys
        let variantRows: [MasterSetVariantRow] = {
            if inlineDetailFilters.ownedOnly {
                return allVariantRows.filter { variantOwnedKeys.contains("\($0.card.masterCardId)::\($0.variant)") }
            }
            if inlineDetailFilters.hideOwned {
                return allVariantRows.filter { !variantOwnedKeys.contains("\($0.card.masterCardId)::\($0.variant)") }
            }
            return allVariantRows
        }()
        let ownedQuantities = ownedQuantityByCardID
        let wishlistedIDs = visibleWishlistedCardIDs
        let accentColor = services.theme.accentColor
        if inlineDetailLoading {
            ProgressView("Loading cards…")
                .frame(maxWidth: .infinity, minHeight: 280)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        } else if filteredCards.isEmpty && !isSetRoute && !isDexRoute {
            ContentUnavailableView(
                inlineDetailCards.isEmpty ? "No cards found" : "No matching cards",
                systemImage: "magnifyingglass",
                description: Text(inlineDetailCards.isEmpty ? "No cards were found for \(route.title)." : "Try a different card name or number.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        } else {
            VStack(spacing: 0) {
                let showHideOwnedToggle: Bool = { if case .set = route { return true }; if case .dex = route { return true }; return false }()
                if showHideOwnedToggle {
                    Toggle("Hide owned cards", isOn: $inlineDetailFilters.hideOwned)
                        .font(.caption.weight(.semibold))
                        .toggleStyle(.switch)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

                if useMasterGrid {
                    let masterGridPresentationCards = variantRows.map(\.card)
                    EagerVGrid(items: variantRows.indexedIdentifiedValues, columns: safeColumnCount, spacing: BindrSpacing.cardGrid) { indexedRow in
                        let row = indexedRow.value
                        let variantCompositeKey = "\(row.card.masterCardId)::\(row.variant)"
                        Button {
                            presentCardAtIndex(masterGridPresentationCards, indexedRow.index)
                        } label: {
                            CardGridCell(
                                card: row.card,
                                services: services,
                                colorScheme: colorScheme,
                                accentColor: accentColor,
                                gridOptions: gridOptions,
                                setName: cachedSetNameByCode[row.card.setCode],
                                isOwned: variantOwnedKeys.contains(variantCompositeKey),
                                isWishlisted: wishlistedIDs.contains(row.card.masterCardId),
                                ownedCountBadge: variantOwnedQuantities[variantCompositeKey],
                                variantLabel: variantTitle(row.variant),
                                variantPricingKey: row.variant
                            )
                        }
                        .buttonStyle(CardCellButtonStyle())
                    }
                    .padding(.horizontal, BindrSpacing.cardGridScreenInset)
                    .padding(.bottom, 16)
                } else {
                    EagerVGrid(items: filteredCards.indexedIdentifiedValues, columns: safeColumnCount, spacing: BindrSpacing.cardGrid) { indexedCard in
                        let card = indexedCard.value
                        Button {
                            if isMultiSelectActive {
                                toggleMultiSelectCardID(card.masterCardId)
                            } else {
                                presentCard(card, filteredCards)
                            }
                        } label: {
                            CardGridCell(
                                card: card,
                                services: services,
                                colorScheme: colorScheme,
                                accentColor: accentColor,
                                gridOptions: gridOptions,
                                setName: cachedSetNameByCode[card.setCode],
                                isOwned: ownedCardIDsCache.contains(card.masterCardId),
                                isWishlisted: wishlistedIDs.contains(card.masterCardId),
                                ownedCountBadge: ownedQuantities[card.masterCardId]
                            )
                            .overlay(alignment: .topTrailing) {
                                if isMultiSelectActive {
                                    Image(systemName: multiSelectedCardIDs.contains(card.masterCardId) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(multiSelectedCardIDs.contains(card.masterCardId) ? Color.blue : Color.white)
                                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                                        .padding(6)
                                }
                            }
                        }
                        .buttonStyle(CardCellButtonStyle())
                        .contextMenu {
                            Button {
                                beginQuickAdd(card: card, action: .collection)
                            } label: {
                                Label("Add to Collection", systemImage: "books.vertical")
                            }
                            Button {
                                beginQuickAdd(card: card, action: .wishlist)
                            } label: {
                                Label("Add to Wishlist", systemImage: "heart")
                            }
                        }
                        .onAppear {
                            guard indexedCard.index.isMultiple(of: max(safeColumnCount, 1)) else { return }
                            ImagePrefetcher.shared.prefetchCardWindow(filteredCards, startingAt: indexedCard.index + 1)
                        }
                    }
                    .padding(.horizontal, BindrSpacing.cardGridScreenInset)
                    .padding(.bottom, isMultiSelectActive && !multiSelectedCardIDs.isEmpty ? 96 : 16)
                }
            }
        }
    }

    private var filteredInlineDetailCards: [Card] {
        var filters = inlineDetailFilters
        if setCompletionMode.usesVariantGrid {
            // Master/grand-master grids apply owned filters per variant slot, not per card.
            filters.hideOwned = false
            filters.ownedOnly = false
        }
        let filtered = filterBrowseCards(
            inlineDetailCards,
            query: inlineDetailQuery,
            filters: filters,
            ownedCardIDs: ownedCardIDsCache,
            brand: currentBrand,
            sets: services.cardData.sets,
            priceByCardID: inlineDetailPriceByCardID
        )
        if case .some(.set(_)) = inlineDetailRoute, inlineDetailFilters.sortBy == .cardNumber {
            return Array(filtered.reversed())
        }
        return filtered
    }

    private func toggleMultiSelectCardID(_ masterCardID: String) {
        if multiSelectedCardIDs.contains(masterCardID) {
            multiSelectedCardIDs.remove(masterCardID)
        } else {
            multiSelectedCardIDs.insert(masterCardID)
            HapticManager.impact(.light)
        }
    }

    private var multiSelectActionBar: some View {
        HStack(spacing: 8) {
            multiSelectActionButton(
                title: "Add to Collection",
                systemImage: "plus.circle.fill",
                tint: Color(red: 0.28, green: 0.84, blue: 0.39)
            ) {
                guard !multiSelectedCards.isEmpty else { return }
                multiSelectCollectionPayload = MultiSelectCollectionPayload(cards: multiSelectedCards)
            }

            multiSelectActionButton(
                title: "Wish List",
                systemImage: "star",
                tint: Color(red: 0.99, green: 0.72, blue: 0.22)
            ) {
                addSelectedToWishlist()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .safeAreaPadding(.bottom, 0)
    }

    private func multiSelectActionButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(
                                colorScheme == .dark
                                    ? Color.black.opacity(0.30)
                                    : Color.black.opacity(0.12)
                            )
                    }
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.10), lineWidth: 0.8)
                    )
            }
            .accessibilityLabel(title)
        }
        .buttonStyle(.plain)
    }

    private func addSelectedToWishlist() {
        guard let wl = services.wishlist else {
            wishlistAlertMessage = "Wishlist isn't available yet. Try again in a moment."
            showWishlistAlert = true
            return
        }
        var addedCount = 0
        for card in multiSelectedCards {
            do {
                try wl.addItem(cardID: card.masterCardId, variantKey: "normal", notes: "")
                addedCount += 1
            } catch let error as WishlistError {
                switch error {
                case .limitReached:
                    showWishlistPaywall = true
                    return
                case .alreadyExists:
                    break
                case .saveFailed:
                    break
                }
            } catch {
                break
            }
        }
        if addedCount > 0 {
            HapticManager.notification(.success)
        }
    }

    private func beginSelectMultiple(with card: Card) {
        if !isMultiSelectActive {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isMultiSelectActive = true
            }
        }
        multiSelectedCardIDs.insert(card.masterCardId)
        HapticManager.impact(.light)
    }

    private func beginQuickAdd(card: Card, action: CardContextAction) {
        if action == .wishlist {
            addCardToWishlist(card)
            return
        }
        Task {
            var keys = await services.pricing.variantKeys(for: card)
            if keys.isEmpty, let variants = card.pricingVariants, !variants.isEmpty {
                keys = variants
            }
            if keys.isEmpty { keys = ["normal"] }
            let sortedKeys = Array(Set(keys)).sorted()
            await MainActor.run {
                pendingCardContextRequest = CardContextActionRequest(
                    card: card,
                    availableVariantKeys: sortedKeys,
                    initialVariantKey: sortedKeys.first ?? "normal",
                    initialAction: action
                )
            }
        }
    }

    private func addCardToWishlist(_ card: Card) {
        guard let wl = services.wishlist else {
            wishlistAlertMessage = "Wishlist isn't available yet. Try again in a moment."
            showWishlistAlert = true
            return
        }
        do {
            try wl.addItem(cardID: card.masterCardId, variantKey: "normal", notes: "")
            HapticManager.notification(.success)
        } catch let error as WishlistError {
            switch error {
            case .limitReached:
                showWishlistPaywall = true
            case .alreadyExists:
                break
            case .saveFailed:
                wishlistAlertMessage = "Couldn’t add card to wishlist. Please try again."
                showWishlistAlert = true
            }
        } catch {
            wishlistAlertMessage = "Couldn’t add card to wishlist. Please try again."
            showWishlistAlert = true
        }
    }

    private func variantTitle(_ key: String) -> String {
        let spaced = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spaced.isEmpty else { return "Normal" }
        return spaced
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    @MainActor
    private func refreshInlineDetailPriceCache() async {
        guard isInlineDetailPresented, !inlineDetailCards.isEmpty else {
            inlineDetailPriceByCardID = [:]
            inlineDetailMasterPriceByCardID = [:]
            inlineDetailVariantPriceByCardID = [:]
            return
        }
        var next: [String: Double] = [:]
        var nextMaster: [String: Double] = [:]
        var nextVariantPrices: [String: [String: Double]] = [:]
        next.reserveCapacity(inlineDetailCards.count)
        nextMaster.reserveCapacity(inlineDetailCards.count)
        nextVariantPrices.reserveCapacity(inlineDetailCards.count)
        for card in inlineDetailCards {
            guard let entry = await services.pricing.pricing(for: card) else { continue }
            let variantPrices = services.variantsCatalog.variantPriceMap(for: entry)
            if !variantPrices.isEmpty {
                nextVariantPrices[card.masterCardId] = variantPrices
            }
            if let usd = services.variantsCatalog.fullSetSlotMarketUSD(for: entry) {
                next[card.masterCardId] = usd
            }
            if setCompletionMode.usesVariantGrid {
                let keys = await services.pricing.variantKeys(for: card)
                let eligible = services.variantsCatalog.eligibleVariantKeys(
                    from: keys,
                    card: card,
                    mode: setCompletionMode
                )
                let masterUSD = services.variantsCatalog.marketUSD(
                    for: entry,
                    mode: setCompletionMode,
                    eligibleVariantKeys: eligible
                )
                if masterUSD > 0 {
                    nextMaster[card.masterCardId] = masterUSD
                }
            } else {
                let masterUSD = allVariantsMarketUSDForEntry(entry)
                if masterUSD > 0 {
                    nextMaster[card.masterCardId] = masterUSD
                }
            }
        }
        inlineDetailPriceByCardID = next
        inlineDetailMasterPriceByCardID = nextMaster
        inlineDetailVariantPriceByCardID = nextVariantPrices
        await refreshInlineDetailSetTrends()
    }

    private func inlineDetailCollectedValueUSD(
        cards: [Card],
        ownedVariantsByCardID: [String: Set<String>]
    ) -> Double {
        cards.reduce(0) { partial, card in
            let ownedVariants = ownedVariantsByCardID[card.masterCardId] ?? []
            guard !ownedVariants.isEmpty else { return partial }
            let variantPrices = inlineDetailVariantPriceByCardID[card.masterCardId] ?? [:]
            return partial + services.variantsCatalog.collectedMarketUSD(
                variantPriceMap: variantPrices,
                ownedVariantKeys: ownedVariants,
                mode: setCompletionMode
            )
        }
    }

    private func allVariantsMarketUSDForEntry(_ entry: CardPricingEntry) -> Double {
        if let scrydex = entry.scrydex, !scrydex.isEmpty {
            return scrydex.values.compactMap { $0.marketEstimateUSD() }.filter { $0 > 0 }.reduce(0, +)
        }
        return entry.tcgplayerMarketEstimateUSD() ?? 0
    }

    private func refreshInlineDetailSetTrends() async {
        let cards = inlineDetailCards
        guard !cards.isEmpty else { return }
        var sum1d = 0.0; var count1d = 0
        var sum7d = 0.0; var count7d = 0
        var sum30d = 0.0; var count30d = 0
        for card in cards {
            guard let trends = await services.pricing.priceTrends(for: card) else { continue }
            let candidates = ["holofoil", "normal", trends.variant]
            var resolved: (change1d: Double?, change7d: Double?, change30d: Double?) = (trends.change1d, trends.change7d, trends.change30d)
            for variant in candidates {
                let c = trends.changes(for: variant, grade: "raw")
                if c.change1d != nil || c.change7d != nil || c.change30d != nil { resolved = c; break }
            }
            if let v = resolved.change1d { sum1d += v; count1d += 1 }
            if let v = resolved.change7d { sum7d += v; count7d += 1 }
            if let v = resolved.change30d { sum30d += v; count30d += 1 }
        }
        inlineDetailSetTrendChanges = (
            change1d: count1d > 0 ? sum1d / Double(count1d) : nil,
            change7d: count7d > 0 ? sum7d / Double(count7d) : nil,
            change30d: count30d > 0 ? sum30d / Double(count30d) : nil
        )
    }

    @ViewBuilder
    private var browseCardsContent: some View {
        if isLoadingInitial {
            ProgressView("Loading cards…")
                .frame(maxWidth: .infinity, minHeight: 280)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        } else if displayedCards.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No cards in the catalog yet.")
                    .foregroundStyle(.secondary)
                if let err = services.cardData.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Pull to refresh after your catalog syncs, or check BINDR_R2_BASE_URL in Info.plist.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 280, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        } else {
            browseCardGrid
        }
    }

    @MainActor
    private func bootstrapFeed(forceReshuffle: Bool) async {
        guard isViewVisible else { return }
        if !forceReshuffle && !displayedCards.isEmpty { return }
        ImagePrefetcher.shared.cancelAll()
        isLoadingInitial = true
        let refs = await services.cardData.browseFeedCardRefs(forceReshuffle: forceReshuffle)
        guard isViewVisible else { return }
        shuffledRefs = refs
        nextRefIndex = 0
        displayedCards = []
        guard !refs.isEmpty else { isLoadingInitial = false; return }
        let firstEnd = min(Self.initialBatchSize, refs.count)
        let batch = Array(refs[..<firstEnd])
        nextRefIndex = firstEnd
        displayedCards = await services.cardData.cardsInOrder(refs: batch)
        guard isViewVisible else { return }
        displayedRows = buildBrowseRows(from: displayedCards)
        allBrowseFilterCards = []
        catalogOrderedRefs = []
        catalogDisplayedCards = []
        catalogDisplayedRows = []
        catalogNextIndex = 0
        refreshBrowseFeedSnapshot(usingCatalogFeed: false)
        isLoadingInitial = false
        ImagePrefetcher.shared.prefetchCardWindow(displayedCards, startingAt: 0, count: 12)
        prefetchNextWindow(usingCatalogFeed: false)
        syncFilterMenuState(usingCatalogFeed: false)
    }

    @MainActor
    private func loadNextPageIfNeeded(usingCatalogFeed: Bool) async {
        guard isViewVisible else { return }
        guard !isLoadingMore else { return }
        if usingCatalogFeed {
            guard catalogNextIndex < catalogOrderedRefs.count else { return }
            isLoadingMore = true
            let end = min(catalogNextIndex + Self.pageSize, catalogOrderedRefs.count)
            let batch = Array(catalogOrderedRefs[catalogNextIndex..<end])
            catalogNextIndex = end
            let more = await services.cardData.cardsInOrder(refs: batch)
            guard isViewVisible else { return }
            catalogDisplayedCards.append(contentsOf: more)
            catalogDisplayedRows = buildBrowseRows(from: catalogDisplayedCards)
            refreshBrowseFeedSnapshot(usingCatalogFeed: true)
            isLoadingMore = false
            syncFilterMenuState(usingCatalogFeed: true)
            return
        }
        guard nextRefIndex < shuffledRefs.count else { return }
        isLoadingMore = true
        let end = min(nextRefIndex + Self.pageSize, shuffledRefs.count)
        let batch = Array(shuffledRefs[nextRefIndex..<end])
        nextRefIndex = end
        let more = await services.cardData.cardsInOrder(refs: batch)
        guard isViewVisible else { return }
        displayedCards.append(contentsOf: more)
        displayedRows = buildBrowseRows(from: displayedCards)
        refreshBrowseFeedSnapshot(usingCatalogFeed: false)
        isLoadingMore = false
        prefetchNextWindow(usingCatalogFeed: false)
        syncFilterMenuState(usingCatalogFeed: false)
    }

    private func prefetchNextWindow(usingCatalogFeed: Bool) {
        guard usingCatalogFeed == false else { return }
        let end = min(nextRefIndex + Self.pageSize, shuffledRefs.count)
        guard nextRefIndex < end else { return }
        let upcoming = Array(shuffledRefs[nextRefIndex..<end])
        Task(priority: .low) {
            let cards = await services.cardData.cardsInOrder(refs: upcoming)
            let urls = cards.map { AppConfiguration.imageURL(relativePath: $0.displayImageSrc) }
            ImagePrefetcher.shared.prefetch(urls)
        }
    }

    @MainActor
    private func ensureAllBrowseFilterCardsLoaded(
        showsPreparingBanner: Bool = true,
        usingCatalogFeed: Bool? = nil
    ) async {
        guard isViewVisible else { return }
        if !allBrowseFilterCards.isEmpty { return }
        
        // Wait if another load is already in progress
        while isLoadingFullCatalog {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        
        // Re-check in case it finished while we were waiting
        if !allBrowseFilterCards.isEmpty { return }
        
        isLoadingFullCatalog = true
        if showsPreparingBanner {
            isPreparingFilterCatalog = true
        }
        
        defer {
            isLoadingFullCatalog = false
            if showsPreparingBanner {
                isPreparingFilterCatalog = false
            }
        }
        
        let loaded = await services.cardData.loadAllBrowseFilterCards()
        guard isViewVisible && !Task.isCancelled else { return }
        allBrowseFilterCards = loaded
        syncFilterMenuState(usingCatalogFeed: usingCatalogFeed)
    }

    @MainActor
    private func rebuildCatalogFeedIfNeeded(
        selectedTab: BrowseHomeTab,
        query: String,
        filters: BrowseCardGridFilters,
        brand: TCGBrand,
        ownedCardIDs: Set<String>,
        shouldUseCatalogFeed: Bool
    ) async {
        guard isViewVisible else { return }
        if shouldUseCatalogFeed == false {
            isUsingCatalogFeedSelection = false
            catalogOrderedRefs = []
            catalogDisplayedCards = []
            catalogDisplayedRows = []
            catalogNextIndex = 0
            // Reset infinite-scroll latch when switching feed modes after a filter/query change.
            lastAutoLoadRowCount = 0
            refreshBrowseFeedSnapshot(usingCatalogFeed: false)
            syncFilterMenuState(usingCatalogFeed: false)
            return
        }
        let ordered = await orderedFilteredRefs(
            from: allBrowseFilterCards,
            query: query,
            filters: filters,
            brand: brand,
            ownedCardIDs: ownedCardIDs
        )
        guard isViewVisible && !Task.isCancelled else { return }
        isUsingCatalogFeedSelection = true
        catalogOrderedRefs = ordered
        let initialEnd = min(Self.catalogInitialBatchSize, ordered.count)
        let initialRefs = Array(ordered.prefix(initialEnd))
        let initialCards = await services.cardData.cardsInOrder(refs: initialRefs)
        guard isViewVisible && !Task.isCancelled else { return }
        catalogDisplayedCards = initialCards
        catalogDisplayedRows = buildBrowseRows(from: catalogDisplayedCards)
        catalogNextIndex = initialEnd
        // New filtered dataset can have the same initial count as the previous one (e.g. 36).
        // Clear the latch so bottom-row onAppear can request the next page.
        lastAutoLoadRowCount = 0
        refreshBrowseFeedSnapshot(usingCatalogFeed: true)
        syncFilterMenuState(usingCatalogFeed: true)
    }

    @MainActor
    private func handleBrowseFiltersChanged(usingCatalogFeed: Bool? = nil) {
        if isInlineDetailPresented {
            syncFilterMenuState(usingCatalogFeed: false)
            return
        }
        let selectedTabSnapshot = selectedTab
        let querySnapshot = query
        let filtersSnapshot = filters
        let brandSnapshot = currentBrand
        let ownedCardIDsSnapshot = ownedCardIDsCache

        let isUsingCatalogFeed = usingCatalogFeed ?? (!querySnapshot.isEmpty || filtersSnapshot.hasActiveFieldFilters || filtersSnapshot.hasActiveSort)
        self.isUsingCatalogFeedSelection = isUsingCatalogFeed

        if isUsingCatalogFeed {
            filterTask?.cancel()
            filterTask = Task { @MainActor in
                await ensureAllBrowseFilterCardsLoaded(showsPreparingBanner: true)
                if Task.isCancelled { return }
                await rebuildCatalogFeedIfNeeded(
                    selectedTab: selectedTabSnapshot,
                    query: querySnapshot,
                    filters: filtersSnapshot,
                    brand: brandSnapshot,
                    ownedCardIDs: ownedCardIDsSnapshot,
                    shouldUseCatalogFeed: isUsingCatalogFeed
                )
            }
        } else {
            filterTask?.cancel()
            catalogOrderedRefs = []
            catalogDisplayedCards = []
            catalogDisplayedRows = []
            catalogNextIndex = 0
            refreshBrowseFeedSnapshot(usingCatalogFeed: false)
            syncFilterMenuState(usingCatalogFeed: false)
        }
    }

    private func refreshBrowseFeedSnapshot(usingCatalogFeed: Bool) {
        if usingCatalogFeed {
            browseFeedSnapshot = BrowseFeedSnapshot(
                cards: catalogDisplayedCards,
                rows: catalogDisplayedRows,
                hasMoreCardsToLoad: catalogNextIndex < catalogOrderedRefs.count
            )
        } else {
            browseFeedSnapshot = BrowseFeedSnapshot(
                cards: displayedCards,
                rows: displayedRows,
                hasMoreCardsToLoad: nextRefIndex < shuffledRefs.count
            )
        }
    }

    private func buildBrowseRows(from cards: [Card]) -> [BrowseCardRow] {
        let setNames = cachedSetNameByCode
        var rows: [BrowseCardRow] = []
        rows.reserveCapacity(cards.count)
        for (index, card) in cards.enumerated() {
            rows.append(
                BrowseCardRow(
                    id: index,
                    card: card,
                    setName: setNames[card.setCode]
                )
            )
        }
        return rows
    }

    private func orderedFilteredRefs(
        from cards: [BrowseFilterCard],
        query: String,
        filters: BrowseCardGridFilters,
        brand: TCGBrand,
        ownedCardIDs: Set<String>
    ) async -> [CardRef] {
        let filtered = filterCards(
            cards,
            query: query,
            filters: filters,
            brand: brand,
            ownedCardIDs: ownedCardIDs
        )
        switch filters.sortBy {
        case .random, .acquiredDateNewest:
            let filteredIDs = Set(filtered.map(\.masterCardId))
            let shuffled = shuffledRefs.filter { filteredIDs.contains($0.masterCardId) }
            let covered = Set(shuffled.map(\.masterCardId))
            let remainder = Array(filtered.lazy.filter { !covered.contains($0.masterCardId) }.map(\.ref))
            return shuffled + remainder
        case .newestSet:
            return sortBrowseFilterCardsByReleaseDateNewestFirst(filtered, sets: services.cardData.sets).map(\.ref)
        case .cardName:
            return filtered
                .sorted { $0.cardName.localizedCaseInsensitiveCompare($1.cardName) == .orderedAscending }
                .map(\.ref)
        case .cardNumber:
            return filtered.sorted {
                if $0.setCode != $1.setCode {
                    return compareReleaseDateNewestFirst(lhsSetCode: $0.setCode, rhsSetCode: $1.setCode)
                }
                return $0.cardNumber.localizedStandardCompare($1.cardNumber) == .orderedAscending
            }.map(\.ref)
        case .price:
            let refs = filtered.map(\.ref)
            let cards = await services.cardData.cardsInOrder(refs: refs)
            // Batch pricing lookups 8 at a time to avoid spawning 500+ concurrent tasks
            // which saturates the thread pool and heats the device.
            var pricedCards: [(card: Card, price: Double?)] = []
            pricedCards.reserveCapacity(cards.count)
            let batchSize = 8
            var offset = 0
            while offset < cards.count {
                guard !Task.isCancelled else { break }
                let batch = Array(cards[offset..<min(offset + batchSize, cards.count)])
                let batchResults: [(Card, Double?)] = await withTaskGroup(of: (Card, Double?).self) { group in
                    for card in batch {
                        group.addTask {
                            if Task.isCancelled { return (card, nil) }
                            let entry = await services.pricing.pricing(for: card)
                            return (card, browseMarketPriceUSD(for: entry))
                        }
                    }
                    var r: [(Card, Double?)] = []
                    for await result in group { r.append(result) }
                    return r
                }
                pricedCards.append(contentsOf: batchResults)
                offset += batchSize
            }
            return pricedCards.sorted { lhs, rhs in
                switch (lhs.price, rhs.price) {
                case let (l?, r?):
                    if l != r { return l > r }
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    break
                }
                if lhs.card.cardName != rhs.card.cardName {
                    return lhs.card.cardName.localizedCaseInsensitiveCompare(rhs.card.cardName) == .orderedAscending
                }
                if lhs.card.setCode != rhs.card.setCode {
                    return compareReleaseDateNewestFirst(lhsSetCode: lhs.card.setCode, rhsSetCode: rhs.card.setCode)
                }
                return lhs.card.cardNumber.localizedStandardCompare(rhs.card.cardNumber) == .orderedAscending
            }.map { CardRef(masterCardId: $0.card.masterCardId, setCode: $0.card.setCode) }
        }
    }

    private func filterCards(
        _ cards: [BrowseFilterCard],
        query: String,
        filters: BrowseCardGridFilters,
        brand: TCGBrand,
        ownedCardIDs: Set<String>
    ) -> [BrowseFilterCard] {
        let normalizedQuery = normalizedBrowseSearchText(query)
        let setReleaseDateByCode = firstValueMap(services.cardData.sets, key: \.setCode) { $0.releaseDate ?? "" }
        let setSeriesNameByCode = seriesNameBySetCode(from: services.cardData.sets)
        let normalizedWeaknessTypes = normalizedBrowseFilterTokens(filters.weaknessTypes)
        let normalizedResistanceTypes = normalizedBrowseFilterTokens(filters.resistanceTypes)
        let normalizedSubtypeTokens = Set(filters.pokemonSubtypes.map(normalizedBrowseSearchText).filter { !$0.isEmpty })

        // Pre-normalize searchable fields once per card rather than once per comparison.
        struct NormalizedFilterCardFields {
            let name: String
            let number: String
            let setCode: String
            let subtype: String
            let subtypes: [String]
        }
        let normalizedFields: [String: NormalizedFilterCardFields] = normalizedQuery.isEmpty ? [:] : {
            var dict = [String: NormalizedFilterCardFields](minimumCapacity: cards.count)
            for card in cards {
                dict[card.masterCardId] = NormalizedFilterCardFields(
                    name: normalizedBrowseSearchText(card.cardName),
                    number: normalizedBrowseSearchText(card.cardNumber),
                    setCode: normalizedBrowseSearchText(card.setCode),
                    subtype: normalizedBrowseSearchText(card.subtype),
                    subtypes: (card.subtypes ?? []).map(normalizedBrowseSearchText)
                )
            }
            return dict
        }()

        return cards.filter { card in
            let matchesQuery: Bool
            if normalizedQuery.isEmpty {
                matchesQuery = true
            } else if let f = normalizedFields[card.masterCardId] {
                matchesQuery = f.name.contains(normalizedQuery)
                    || f.number.contains(normalizedQuery)
                    || f.setCode.contains(normalizedQuery)
                    || f.subtype.contains(normalizedQuery)
                    || f.subtypes.contains { $0.contains(normalizedQuery) }
            } else {
                matchesQuery = false
            }
            guard matchesQuery else { return false }

            if cardMatchesSeriesNamesFilter(
                setCode: card.setCode,
                selectedSeriesNames: filters.seriesNames,
                seriesNameBySetCode: setSeriesNameByCode
            ) == false {
                return false
            }
            if brand == .pokemon,
               filters.cardTypes.isEmpty == false,
               filters.cardTypes.contains(resolvedCardType(for: card, brand: brand)) == false {
                return false
            }
            if filters.rarePlusOnly && isCommonOrUncommon(card.rarity) {
                return false
            }
            if filters.hideOwned && ownedCardIDs.contains(card.masterCardId) {
                return false
            }
            if filters.ownedOnly && !ownedCardIDs.contains(card.masterCardId) {
                return false
            }
            if brand == .pokemon,
               filters.legalities.isEmpty == false,
               pokemonCardMatchesLegalityFilters(
                    selectedLegalityFilters: filters.legalities,
                    setCode: card.setCode,
                    releaseDate: setReleaseDateByCode[card.setCode],
                    category: card.category,
                    energyType: card.energyType,
                    regulationMark: card.regulationMark,
                    cardName: card.cardName
               ) == false {
                return false
            }
            if filters.energyTypes.isEmpty == false {
                let energies = Set(resolvedEnergyTypes(for: card))
                if energies.isDisjoint(with: filters.energyTypes) {
                    return false
                }
            }
            if filters.rarities.isEmpty == false {
                let rarity = trimmedValue(card.rarity)
                if rarity.isEmpty || filters.rarities.contains(rarity) == false {
                    return false
                }
            }
            if filters.trainerTypes.isEmpty == false {
                let trainerType = trimmedValue(card.trainerType)
                if trainerType.isEmpty || filters.trainerTypes.contains(trainerType) == false {
                    return false
                }
            }
            if brand == .pokemon,
               browseTextContainsAnyToken(card.weakness, normalizedTokens: normalizedWeaknessTypes) == false {
                return false
            }
            if brand == .pokemon,
               browseTextContainsAnyToken(card.resistance, normalizedTokens: normalizedResistanceTypes) == false {
                return false
            }
            if brand == .pokemon,
               filters.pokemonSubtypes.isEmpty == false {
                guard resolvedCardType(for: card, brand: brand) == .pokemon else {
                    return false
                }
                guard cardMatchesPokemonSubtypeFilters(card, precomputedSelectedTokens: normalizedSubtypeTokens) else {
                    return false
                }
            }
            if let abilityPresence = filters.abilityPresence {
                let hasAbilities = (card.abilities?.isEmpty == false)
                if abilityPresence == .yes, hasAbilities == false { return false }
                if abilityPresence == .no, hasAbilities == true { return false }
            }
            return true
        }
    }

    private func resolvedCardType(for card: BrowseFilterCard, brand: TCGBrand) -> BrowseCardTypeFilter {
        let category = card.category?.lowercased() ?? ""
        if category.contains("trainer") || card.trainerType != nil {
            return .trainer
        }
        if category.contains("energy") || card.energyType != nil {
            return .energy
        }
        return .pokemon
    }

    private func resolvedEnergyTypes(for card: BrowseFilterCard) -> [String] {
        var values = Set<String>()
        if let energyType = card.energyType {
            let trimmed = trimmedValue(energyType)
            if !trimmed.isEmpty {
                values.insert(trimmed)
            }
        }
        for type in card.elementTypes ?? [] {
            let trimmed = trimmedValue(type)
            if !trimmed.isEmpty {
                values.insert(trimmed)
            }
        }
        return Array(values)
    }

    private func cardMatchesPokemonSubtypeFilters(_ card: BrowseFilterCard, precomputedSelectedTokens: Set<String>) -> Bool {
        guard !precomputedSelectedTokens.isEmpty else { return true }

        let cardSubtypeTokens = Set(([card.stage, card.subtype] + (card.subtypes ?? []))
            .map(normalizedBrowseSearchText)
            .filter { !$0.isEmpty })
        guard !cardSubtypeTokens.isEmpty else { return false }

        func compact(_ token: String) -> String {
            token.replacingOccurrences(of: " ", with: "")
        }

        return precomputedSelectedTokens.contains { selected in
            let compactSelected = compact(selected)
            return cardSubtypeTokens.contains { token in
                token == selected
                    || token.contains(selected)
                    || compact(token) == compactSelected
                    || compact(token).contains(compactSelected)
            }
        }
    }

    private func resolvedEnergyTypes(for card: Card) -> [String] {
        var values = Set<String>()
        if let energyType = card.energyType {
            let trimmed = trimmedValue(energyType)
            if !trimmed.isEmpty {
                values.insert(trimmed)
            }
        }
        for type in card.elementTypes ?? [] {
            let trimmed = trimmedValue(type)
            if !trimmed.isEmpty {
                values.insert(trimmed)
            }
        }
        return Array(values)
    }

    private func isCommonOrUncommon(_ rarity: String?) -> Bool {
        let normalized = rarity?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let lettersOnly = String(normalized.unicodeScalars.filter(CharacterSet.letters.contains))
        return normalized.contains("common")
            || lettersOnly == "rare"
            || normalized == "rare holo"
    }

    private func trimmedValue(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func compareReleaseDateNewestFirst(lhsSetCode: String, rhsSetCode: String) -> Bool {
        let dates = firstValueMap(services.cardData.sets, key: \.setCode) { $0.releaseDate ?? "" }
        let lhs = dates[lhsSetCode] ?? ""
        let rhs = dates[rhsSetCode] ?? ""
        if lhs != rhs {
            return lhs > rhs
        }
        return lhsSetCode.localizedStandardCompare(rhsSetCode) == .orderedAscending
    }

    @MainActor
    private func syncFilterMenuState(usingCatalogFeed: Bool? = nil) {
        if isInlineDetailPresented {
            let inlineCount = filteredInlineDetailCards.count
            visibleBrowseResultCount = inlineCount
            filterResultCount = inlineCount
            filterEnergyOptions = cardEnergyOptions(inlineDetailCards)
            filterRarityOptions = cardRarityOptions(inlineDetailCards)
            filterTrainerTypeOptions = cardTrainerTypeOptions(inlineDetailCards)
            inlineDetailFilterResultCount = inlineCount
            return
        }
        let isUsingCatalogFeed = usingCatalogFeed ?? isUsingCatalogFeedSelection
        let hasCardFeedFilters = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || filters.hasActiveFieldFilters
            || filters.hasActiveSort
        let count: Int
        if selectedTab != .cards {
            count = 0
        } else if isUsingCatalogFeed {
            count = catalogOrderedRefs.count
        } else if hasCardFeedFilters == false, shuffledRefs.isEmpty == false {
            // No filters/search: show total available browse feed size, not just current page.
            count = shuffledRefs.count
        } else {
            count = browseFeedSnapshot.cards.count
        }
        visibleBrowseResultCount = count
        filterResultCount = count
        if allBrowseFilterCards.isEmpty {
            filterEnergyOptions = cardEnergyOptions(browseFeedSnapshot.cards)
            filterRarityOptions = cardRarityOptions(browseFeedSnapshot.cards)
            filterTrainerTypeOptions = []
        } else {
            filterEnergyOptions = browseFilterEnergyOptions(allBrowseFilterCards)
            filterRarityOptions = browseFilterRarityOptions(allBrowseFilterCards)
            filterTrainerTypeOptions = browseFilterTrainerTypeOptions(allBrowseFilterCards)
        }
    }

    @MainActor
    private func refreshBrowseGridPriceLines() async {
        guard isViewVisible, selectedTab == .cards, gridOptions.showPricing else {
            browsePriceLineByCardID = [:]
            return
        }
        let cards = browseFeedSnapshot.cards
        guard !cards.isEmpty else {
            browsePriceLineByCardID = [:]
            return
        }

        let currency = services.priceDisplay.currency
        let fx = services.pricing.usdToGbp
        await services.pricing.prefetchPokemonCardPricing(forSetCodes: [])
        await services.pricing.indexPricingForCards(cards)
        guard isViewVisible, !Task.isCancelled else { return }

        var next = browsePriceLineByCardID
        next.reserveCapacity(cards.count)
        let visibleIDs = Set(cards.map(\.masterCardId))
        next = next.filter { visibleIDs.contains($0.key) }

        for card in cards {
            guard !Task.isCancelled else { return }
            if let entry = services.pricing.cachedPricingEntry(for: card),
               let line = browseMarketPriceLine(for: entry, currency: currency, usdToGbp: fx) {
                next[card.masterCardId] = line
            } else if services.pricing.isPricingIndexed(for: card) {
                next[card.masterCardId] = "—"
            }
        }

        browsePriceLineByCardID = next
    }

    private func tabSupportsInlineDetail(_ tab: BrowseHomeTab) -> Bool {
        switch tab {
        case .sets, .pokemon:
            return true
        case .cards, .products:
            return false
        }
    }

    @MainActor
    private func loadInlineDetailIfNeeded(route: BrowseInlineDetailRoute?) async {
        guard let route else {
            inlineDetailCards = []
            inlineDetailLoading = false
            syncFilterMenuState(usingCatalogFeed: false)
            return
        }

        inlineDetailLoading = true
        defer { inlineDetailLoading = false }

        switch route {
        case .set(let set):
            let loaded = await services.cardData.loadCards(forSetCode: set.setCode)
            inlineDetailCards = sortCardsByLocalIdHighestFirst(loaded)
        case .dex(let dexId, _):
            inlineDetailCards = await services.cardData.cards(matchingNationalDex: dexId)
        }

        ImagePrefetcher.shared.prefetchCardWindow(inlineDetailCards, startingAt: 0, count: 12)
        syncFilterMenuState(usingCatalogFeed: false)
        await rebuildMasterSetVariantRows()
    }

    @MainActor
    private func rebuildMasterSetVariantRows() async {
        let isSetOrDex: Bool = {
            if case .set = inlineDetailRoute { return true }
            if case .dex = inlineDetailRoute { return true }
            return false
        }()
        guard isSetOrDex, setCompletionMode.usesVariantGrid else {
            masterSetVariantRows = []
            return
        }
        var rows: [MasterSetVariantRow] = []
        for card in inlineDetailCards {
            let keys = await services.pricing.variantKeys(for: card)
            let eligible = services.variantsCatalog.eligibleVariantKeys(
                from: keys,
                card: card,
                mode: setCompletionMode
            )
            for key in eligible {
                rows.append(MasterSetVariantRow(id: "\(card.masterCardId)::\(key)", card: card, variant: key))
            }
        }
        masterSetVariantRows = rows
    }

    private func setModeChip(label: String, mode: SetCompletionMode) -> some View {
        let isSelected = setCompletionMode == mode
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                setCompletionMode = mode
            }
            Haptics.lightImpact()
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? .white : .primary.opacity(0.85))
                .glassFilterChipStyle(isSelected: isSelected, accentColor: services.theme.accentColor)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var setsInDisplayOrder: [TCGSet] {
        services.cardData.allSetsSortedByReleaseDateNewestFirst()
    }

    private func adjacentSet(to set: TCGSet, offset: Int) -> TCGSet? {
        let sets = setsInDisplayOrder
        guard let index = sets.firstIndex(where: { $0.setCode == set.setCode }) else { return nil }
        let targetIndex = index + offset
        guard sets.indices.contains(targetIndex) else { return nil }
        return sets[targetIndex]
    }

    private func navigateToAdjacentSet(from set: TCGSet, offset: Int) {
        guard let target = adjacentSet(to: set, offset: offset) else { return }
        Haptics.lightImpact()
        lastSelectedSetCodeInSetsTab = target.setCode
        inlineDetailRoute = .set(target)
    }

    private func adjacentPokemon(to dexId: Int, offset: Int) -> NationalDexPokemon? {
        let all = services.cardData.nationalDexPokemonSorted()
        guard let index = all.firstIndex(where: { $0.nationalDexNumber == dexId }) else { return nil }
        let targetIndex = index + offset
        guard all.indices.contains(targetIndex) else { return nil }
        return all[targetIndex]
    }

    private func navigateToAdjacentPokemon(from dexId: Int, offset: Int) {
        guard let target = adjacentPokemon(to: dexId, offset: offset) else { return }
        Haptics.lightImpact()
        inlineDetailRoute = .dex(dexId: target.nationalDexNumber, displayName: target.displayName)
    }

    @ViewBuilder
    private func setSummaryInlineNavigation(for set: TCGSet) -> some View {
        HStack {
            setAdjacentSetArrow(
                label: "Previous set",
                systemImage: "chevron.left",
                enabled: adjacentSet(to: set, offset: -1) != nil,
                controlSize: 32
            ) {
                navigateToAdjacentSet(from: set, offset: -1)
            }

            Spacer(minLength: 8)

            SetLogoAsyncImage(
                logoSrc: set.logoSrc,
                height: 32,
                brand: services.brandSettings.selectedCatalogBrand
            )
            .frame(maxWidth: 120)

            Spacer(minLength: 8)

            setAdjacentSetArrow(
                label: "Next set",
                systemImage: "chevron.right",
                enabled: adjacentSet(to: set, offset: 1) != nil,
                controlSize: 32
            ) {
                navigateToAdjacentSet(from: set, offset: 1)
            }
        }
    }

    @ViewBuilder
    private func dexSummaryInlineNavigation(for dexId: Int) -> some View {
        let pokemon = services.cardData.nationalDexPokemon.first { $0.nationalDexNumber == dexId }
        HStack {
            setAdjacentSetArrow(
                label: "Previous Pokémon",
                systemImage: "chevron.left",
                enabled: adjacentPokemon(to: dexId, offset: -1) != nil,
                controlSize: 32
            ) {
                navigateToAdjacentPokemon(from: dexId, offset: -1)
            }

            Spacer(minLength: 8)

            if let pokemon {
                CachedAsyncImage(
                    url: AppConfiguration.pokemonArtURL(imageFileName: pokemon.imageUrl)
                ) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .frame(width: 56, height: 56)
            }

            Spacer(minLength: 8)

            setAdjacentSetArrow(
                label: "Next Pokémon",
                systemImage: "chevron.right",
                enabled: adjacentPokemon(to: dexId, offset: 1) != nil,
                controlSize: 32
            ) {
                navigateToAdjacentPokemon(from: dexId, offset: 1)
            }
        }
    }

    private func setAdjacentSetArrow(
        label: String,
        systemImage: String,
        enabled: Bool,
        controlSize: CGFloat = 44,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard enabled else { return }
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: controlSize >= 40 ? 17 : 14, weight: .medium))
                .foregroundStyle(enabled ? Color.primary : Color.primary.opacity(0.28))
                .modifier(ChromeGlassCircleGlyphModifier())
        }
        .buttonStyle(.plain)
        .frame(width: controlSize, height: controlSize)
        .contentShape(Rectangle())
        .accessibilityLabel(label)
        .disabled(!enabled)
    }

    private func setProgressBar(for set: TCGSet, cards: [Card]) -> some View {
        let priceDict = setCompletionMode.usesVariantGrid ? inlineDetailMasterPriceByCardID : inlineDetailPriceByCardID
        let total = setCompletionMode.usesVariantGrid
            ? (masterSetVariantRows.count > 0 ? masterSetVariantRows.count : set.cardCountTotal ?? cards.count)
            : (set.cardCountTotal ?? cards.count)
        var ownedVariantsByCardID: [String: Set<String>] = [:]
        for item in collectionItems where item.quantity > 0 {
            let brand = TCGBrand.inferredFromMasterCardId(item.cardID)
            guard brand == services.brandSettings.selectedCatalogBrand else { continue }
            let variant = item.variantKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalized = variant.isEmpty ? "normal" : variant
            guard !services.variantsCatalog.isChampionshipVariant(normalized) else { continue }
            ownedVariantsByCardID[item.cardID, default: []].insert(normalized)
        }
        let ownedCardIDs = Set(ownedVariantsByCardID.keys)
        let owned: Int = {
            switch setCompletionMode {
            case .full:
                return cards.filter { ownedCardIDs.contains($0.masterCardId) }.count
            case .master, .grandMaster:
                return cards.reduce(0) { partial, card in
                    let ownedVariants = ownedVariantsByCardID[card.masterCardId] ?? []
                    let counted = ownedVariants.filter { services.variantsCatalog.includesVariant($0, mode: setCompletionMode) }.count
                    return partial + counted
                }
            }
        }()
        let progress = total > 0 ? min(CGFloat(owned) / CGFloat(total), 1) : 0
        let currency = services.priceDisplay.currency
        let fx = services.pricing.usdToGbp
        let totalValue = priceDict.values.reduce(0, +)
        let ownedValue = inlineDetailCollectedValueUSD(
            cards: cards,
            ownedVariantsByCardID: ownedVariantsByCardID
        )
        let remainingValue = max(totalValue - ownedValue, 0)
        let hasPrices = totalValue > 0
        let trends = inlineDetailSetTrendChanges

        return VStack(spacing: 14) {
            setSummaryInlineNavigation(for: set)

            HStack(spacing: 8) {
                setModeChip(label: SetCompletionMode.full.chipLabel, mode: .full)
                setModeChip(label: SetCompletionMode.master.chipLabel, mode: .master)
                setModeChip(label: SetCompletionMode.grandMaster.chipLabel, mode: .grandMaster)
                Spacer(minLength: 0)
            }

            // Header
            HStack(alignment: .firstTextBaseline) {
                Text(setCompletionMode.completionTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(owned)")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(services.theme.accentColor)
                    Text("/ \(total)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [services.theme.accentColor, services.theme.accentColor.opacity(0.7)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: max(geo.size.width * progress, 8))
                        .shadow(color: services.theme.accentColor.opacity(0.3), radius: 4)
                        .overlay {
                            Capsule().stroke(
                                LinearGradient(colors: [.white.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom),
                                lineWidth: 1
                            )
                        }
                }
            }
            .frame(height: 10)

            // Value row
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(setCompletionMode.valueCaption)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(hasPrices ? currency.format(amountUSD: totalValue, usdToGbp: fx) : "—")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Spacer()
                VStack(alignment: .center, spacing: 2) {
                    Text("COLLECTED")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(hasPrices ? currency.format(amountUSD: ownedValue, usdToGbp: fx) : "—")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("TO COMPLETE")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(hasPrices ? currency.format(amountUSD: remainingValue, usdToGbp: fx) : "—")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(hasPrices ? services.theme.accentColor : .secondary)
                }
            }

            // Trend badges
            HStack(spacing: 8) {
                Spacer()
                inlineTrendBadge(label: "1D", value: trends.change1d)
                inlineTrendBadge(label: "7D", value: trends.change7d)
                inlineTrendBadge(label: "30D", value: trends.change30d)
                if trends.change1d == nil && trends.change7d == nil && trends.change30d == nil {
                    Text("Loading trends…")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
        .padding(16)
        .glassCardStyle(cornerRadius: 16, interactive: false)
    }

    private func dexProgressBar(dexId: Int, displayName: String, cards: [Card]) -> some View {
        let priceDict = setCompletionMode.usesVariantGrid ? inlineDetailMasterPriceByCardID : inlineDetailPriceByCardID
        var ownedVariantsByCardID: [String: Set<String>] = [:]
        for item in collectionItems where item.quantity > 0 {
            let brand = TCGBrand.inferredFromMasterCardId(item.cardID)
            guard brand == services.brandSettings.selectedCatalogBrand else { continue }
            let variant = item.variantKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalized = variant.isEmpty ? "normal" : variant
            guard !services.variantsCatalog.isChampionshipVariant(normalized) else { continue }
            ownedVariantsByCardID[item.cardID, default: []].insert(normalized)
        }
        let ownedCardIDs = Set(ownedVariantsByCardID.keys)
        let displayTotal = setCompletionMode.usesVariantGrid
            ? (masterSetVariantRows.count > 0 ? masterSetVariantRows.count : cards.count)
            : cards.count
        let owned: Int = {
            switch setCompletionMode {
            case .full:
                return cards.filter { ownedCardIDs.contains($0.masterCardId) }.count
            case .master, .grandMaster:
                return cards.reduce(0) { partial, card in
                    let ownedVariants = ownedVariantsByCardID[card.masterCardId] ?? []
                    let counted = ownedVariants.filter { services.variantsCatalog.includesVariant($0, mode: setCompletionMode) }.count
                    return partial + counted
                }
            }
        }()
        let progress = displayTotal > 0 ? min(CGFloat(owned) / CGFloat(displayTotal), 1) : 0
        let currency = services.priceDisplay.currency
        let fx = services.pricing.usdToGbp
        let totalValue = priceDict.values.reduce(0, +)
        let ownedValue = inlineDetailCollectedValueUSD(
            cards: cards,
            ownedVariantsByCardID: ownedVariantsByCardID
        )
        let remainingValue = max(totalValue - ownedValue, 0)
        let hasPrices = totalValue > 0
        let trends = inlineDetailSetTrendChanges

        return VStack(spacing: 14) {
            dexSummaryInlineNavigation(for: dexId)

            HStack(spacing: 8) {
                setModeChip(label: SetCompletionMode.full.chipLabel, mode: .full)
                setModeChip(label: SetCompletionMode.master.chipLabel, mode: .master)
                setModeChip(label: SetCompletionMode.grandMaster.chipLabel, mode: .grandMaster)
                Spacer(minLength: 0)
            }

            // Header
            HStack(alignment: .firstTextBaseline) {
                Text(setCompletionMode.dexCompletionTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(owned)")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(services.theme.accentColor)
                    Text("/ \(displayTotal)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [services.theme.accentColor, services.theme.accentColor.opacity(0.7)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: max(geo.size.width * progress, 8))
                        .shadow(color: services.theme.accentColor.opacity(0.3), radius: 4)
                        .overlay {
                            Capsule().stroke(
                                LinearGradient(colors: [.white.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom),
                                lineWidth: 1
                            )
                        }
                }
            }
            .frame(height: 10)

            // Value row
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(setCompletionMode.dexValueCaption)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(hasPrices ? currency.format(amountUSD: totalValue, usdToGbp: fx) : "—")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Spacer()
                VStack(alignment: .center, spacing: 2) {
                    Text("COLLECTED")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(hasPrices ? currency.format(amountUSD: ownedValue, usdToGbp: fx) : "—")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("TO COMPLETE")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(hasPrices ? currency.format(amountUSD: remainingValue, usdToGbp: fx) : "—")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(hasPrices ? services.theme.accentColor : .secondary)
                }
            }

            // Trend badges
            HStack(spacing: 8) {
                Spacer()
                inlineTrendBadge(label: "1D", value: trends.change1d)
                inlineTrendBadge(label: "7D", value: trends.change7d)
                inlineTrendBadge(label: "30D", value: trends.change30d)
                if trends.change1d == nil && trends.change7d == nil && trends.change30d == nil {
                    Text("Loading trends…")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
        .padding(16)
        .glassCardStyle(cornerRadius: 16, interactive: false)
    }

    @ViewBuilder
    private func inlineTrendBadge(label: String, value: Double?) -> some View {
        if let value {
            let isUp = value >= 0
            let tint: Color = isUp ? Color(red: 0.2, green: 0.78, blue: 0.35) : Color(red: 0.95, green: 0.27, blue: 0.27)
            HStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint.opacity(0.8))
                Image(systemName: isUp ? "arrow.up" : "arrow.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(tint)
                Text(String(format: "%.1f%%", abs(value)))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.12)))
        }
    }

    private func progressCapsule(progress: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
                Capsule()
                    .fill(LinearGradient(
                        colors: [services.theme.accentColor, services.theme.accentColor.opacity(0.7)],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: max(geo.size.width * progress, 8))
                    .shadow(color: services.theme.accentColor.opacity(0.3), radius: 4, x: 0, y: 0)
                    .overlay {
                        Capsule().stroke(
                            LinearGradient(colors: [.white.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom),
                            lineWidth: 1
                        )
                    }
            }
        }
        .frame(height: 8)
    }
}

private enum SetsTabScrollRestore: Equatable {
    case scrollToSetRow(setCode: String)
}

private func browseSetRowScrollID(setCode: String) -> String {
    "browse-set-row-\(setCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
}

private func browseAuxTopAnchorID() -> String {
    "browse-aux-top-anchor"
}

private struct BrowseSetsTabContent: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    @Query private var collectionItems: [CollectionItem]

    let query: String
    @Binding var setCompletionMode: SetCompletionMode
    let onSelectSet: (TCGSet) -> Void

    @State private var uniqueCollectedCountBySetCode: [String: Int] = [:]
    /// Master-set collected counts: each owned card+variant combination counts separately.
    @State private var variantCollectedCountBySetCode: [String: Int] = [:]
    @State private var grandMasterCollectedCountBySetCode: [String: Int] = [:]
    @State private var variantSlotTotalBySetCode: [String: Int] = [:]
    @State private var grandMasterSlotTotalBySetCode: [String: Int] = [:]
    @State private var setMarketValueUSDByKey: [String: Double] = [:]
    @State private var loadedSetMarketValueKeys: Set<String> = []
    @State private var loadingSetMarketValueKeys: Set<String> = []

    @State private var filteredSets: [TCGSet] = []
    @State private var groupedSets: [(title: String, sets: [TCGSet])] = []

    private func rebuildSetGroups() {
        let allSets = services.cardData.allSetsSortedByReleaseDateNewestFirst()
        let normalizedQuery = normalizedBrowseSearchText(query)
        let filtered: [TCGSet]
        if normalizedQuery.isEmpty {
            filtered = allSets
        } else {
            filtered = allSets.filter { set in
                normalizedBrowseSearchText(set.name).contains(normalizedQuery)
                    || normalizedBrowseSearchText(set.setCode).contains(normalizedQuery)
                    || normalizedBrowseSearchText(set.seriesName).contains(normalizedQuery)
            }
        }
        filteredSets = filtered
        let grouped = Dictionary(grouping: filtered, by: browseSeriesTitle(for:))
        groupedSets = grouped
            .map { (title: $0.key, sets: sortSetsNewestFirst($0.value)) }
            .sorted { lhs, rhs in
                let lhsNewest = lhs.sets.map(\.releaseDate).compactMap { $0 }.max() ?? ""
                let rhsNewest = rhs.sets.map(\.releaseDate).compactMap { $0 }.max() ?? ""
                if lhsNewest != rhsNewest { return lhsNewest > rhsNewest }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private var collectionProgressTaskKey: Int {
        var h = Hasher()
        h.combine(services.brandSettings.selectedCatalogBrand.rawValue)
        h.combine(services.collectionInventoryRevision)
        // sets.count is sufficient to detect catalog load completion — individual
        // set codes don't need to be hashed since a count change means reload anyway.
        h.combine(services.cardData.sets.count)
        // collectionInventoryRevision already tracks quantity changes — count alone
        // is enough here to avoid an O(n) reduce on every @Query-triggered body render.
        h.combine(collectionItems.count)
        return h.finalize()
    }

    private var setLogoPrefetchTaskKey: Int {
        var h = Hasher()
        h.combine(filteredSets.count)
        h.combine(filteredSets.first?.setCode)
        h.combine(filteredSets.last?.setCode)
        return h.finalize()
    }

    var body: some View {
        Group {
            setCompletionModeChipBar

            if filteredSets.isEmpty {
                ContentUnavailableView(
                    "No matching sets",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different set name or code.")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            } else {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(groupedSets, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.primary)
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 1)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                        LazyVStack(spacing: 0) {
                            ForEach(group.sets) { set in
                                Button {
                                    onSelectSet(set)
                                } label: {
                                    HStack(spacing: 14) {
                                        SetLogoAsyncImage(
                                            logoSrc: set.logoSrc,
                                            height: 44,
                                            brand: services.brandSettings.selectedCatalogBrand
                                        )
                                        .frame(width: 80)

                                        VStack(alignment: .leading, spacing: 2) {
                                            let progress = setProgress(for: set)
                                            HStack(alignment: .top, spacing: 8) {
                                                Text(set.name)
                                                    .font(.subheadline.weight(.medium))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(2)
                                                Spacer(minLength: 6)
                                                Text(setCompletionMode.listValueLabel)
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            if let total = progress.total, total > 0 {
                                                ProgressView(value: min(Double(progress.collected), Double(total)), total: Double(total))
                                                    .progressViewStyle(.linear)
                                                    .tint(.accentColor)
                                                    .padding(.top, 2)
                                                HStack(spacing: 8) {
                                                    Text("\(progress.collected) out of \(total) collected")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                    Spacer(minLength: 6)
                                                    Text(setMarketValueText(for: set))
                                                        .font(.caption2.weight(.semibold))
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                }
                                            } else {
                                                HStack(spacing: 8) {
                                                    Text("\(progress.collected) collected")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                    Spacer(minLength: 6)
                                                    Text(setMarketValueText(for: set))
                                                        .font(.caption2.weight(.semibold))
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                }
                                            }
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .id(browseSetRowScrollID(setCode: set.setCode))
                                .buttonStyle(.plain)
                                .task(id: setMarketValueTaskID(for: set)) {
                                    await ensureSetMarketValueLoaded(for: set)
                                }

                                Divider()
                                    .padding(.leading, 124)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .task(id: collectionProgressTaskKey) {
            await refreshCollectedCounts()
        }
        .task(id: variantSlotTotalsTaskKey) {
            await refreshVariantSlotTotals()
        }
        .task(id: setLogoPrefetchTaskKey) {
            prefetchSetLogos()
        }
        .onAppear { rebuildSetGroups() }
        .onChange(of: query) { _, _ in rebuildSetGroups() }
        .onChange(of: services.cardData.sets.count) { _, _ in rebuildSetGroups() }
    }

    private func browseSeriesTitle(for set: TCGSet) -> String {
        let title = set.seriesName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (title?.isEmpty == false ? title! : "Other")
    }

    private func sortSetsNewestFirst(_ sets: [TCGSet]) -> [TCGSet] {
        sets.sorted { lhs, rhs in
            let ld = lhs.releaseDate ?? ""
            let rd = rhs.releaseDate ?? ""
            if ld != rd { return ld > rd }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var variantSlotTotalsTaskKey: String {
        "\(services.brandSettings.selectedCatalogBrand.rawValue)|\(setCompletionMode.rawValue)|\(services.cardData.sets.count)"
    }

    private func setMarketValueTaskID(for set: TCGSet) -> String {
        "\(services.brandSettings.selectedCatalogBrand.rawValue)|\(set.setCode.lowercased())|\(setCompletionMode.rawValue)"
    }

    private func setMarketValueKey(for set: TCGSet) -> String {
        setMarketValueTaskID(for: set)
    }

    private func setMarketValueText(for set: TCGSet) -> String {
        let key = setMarketValueKey(for: set)
        if let usd = setMarketValueUSDByKey[key] {
            return services.priceDisplay.currency.format(amountUSD: usd, usdToGbp: services.pricing.usdToGbp)
        }
        if loadedSetMarketValueKeys.contains(key) {
            return "—"
        }
        return "…"
    }

    @MainActor
    private func ensureSetMarketValueLoaded(for set: TCGSet) async {
        let key = setMarketValueKey(for: set)
        if loadedSetMarketValueKeys.contains(key) || loadingSetMarketValueKeys.contains(key) {
            return
        }
        loadingSetMarketValueKeys.insert(key)
        defer { loadingSetMarketValueKeys.remove(key) }

        let cards = await services.cardData.loadCards(forSetCode: set.setCode)
        var totalUSD = 0.0
        var pricedCardCount = 0

        for card in cards {
            guard let entry = await services.pricing.pricing(for: card) else { continue }
            if setCompletionMode.usesVariantGrid {
                let keys = await services.pricing.variantKeys(for: card)
                let eligible = services.variantsCatalog.eligibleVariantKeys(
                    from: keys,
                    card: card,
                    mode: setCompletionMode
                )
                let variantTotal = services.variantsCatalog.marketUSD(
                    for: entry,
                    mode: setCompletionMode,
                    eligibleVariantKeys: eligible
                )
                if variantTotal > 0 {
                    totalUSD += variantTotal
                    pricedCardCount += 1
                }
            } else {
                if let browseUSD = services.variantsCatalog.fullSetSlotMarketUSD(for: entry) {
                    totalUSD += browseUSD
                    pricedCardCount += 1
                }
            }
        }

        if pricedCardCount > 0 {
            setMarketValueUSDByKey[key] = totalUSD
        } else {
            setMarketValueUSDByKey.removeValue(forKey: key)
        }
        loadedSetMarketValueKeys.insert(key)
    }

    private func allVariantsMarketUSD(for entry: CardPricingEntry) -> Double {
        if let scrydex = entry.scrydex, !scrydex.isEmpty {
            return scrydex.values
                .compactMap { $0.marketEstimateUSD() }
                .filter { $0 > 0 }
                .reduce(0, +)
        }
        return entry.tcgplayerMarketEstimateUSD() ?? 0
    }

    @MainActor
    private func refreshCollectedCounts() async {
        let activeSetCodes = Set(services.cardData.sets.map { $0.setCode.lowercased() })
        var uniqueCardKeysBySetCode: [String: Set<String>] = [:]
        var masterVariantKeysBySetCode: [String: Set<String>] = [:]
        var grandMasterVariantKeysBySetCode: [String: Set<String>] = [:]

        for item in collectionItems where item.quantity > 0 {
            guard let identity = await resolveCollectionCardIdentity(
                for: item.cardID,
                activeSetCodes: activeSetCodes
            ) else { continue }
            uniqueCardKeysBySetCode[identity.setCode, default: []].insert(identity.uniqueCardKey)

            let variant = item.variantKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let variantToken = variant.isEmpty ? "normal" : variant
            guard !services.variantsCatalog.isChampionshipVariant(variantToken) else { continue }

            if services.variantsCatalog.includesVariant(variantToken, mode: .master) {
                masterVariantKeysBySetCode[identity.setCode, default: []]
                    .insert("\(identity.uniqueCardKey)::\(variantToken)")
            }
            if services.variantsCatalog.includesVariant(variantToken, mode: .grandMaster) {
                grandMasterVariantKeysBySetCode[identity.setCode, default: []]
                    .insert("\(identity.uniqueCardKey)::\(variantToken)")
            }
        }

        uniqueCollectedCountBySetCode = uniqueCardKeysBySetCode.mapValues(\.count)
        variantCollectedCountBySetCode = masterVariantKeysBySetCode.mapValues(\.count)
        grandMasterCollectedCountBySetCode = grandMasterVariantKeysBySetCode.mapValues(\.count)
    }

    @MainActor
    private func refreshVariantSlotTotals() async {
        guard setCompletionMode != .full else { return }
        var nextTotals: [String: Int] = [:]
        for set in services.cardData.sets {
            let setCode = set.setCode.lowercased()
            let total = await services.variantsCatalog.variantSlotCount(
                forSetCode: set.setCode,
                mode: setCompletionMode,
                cardData: services.cardData,
                pricing: services.pricing
            )
            nextTotals[setCode] = total
        }
        switch setCompletionMode {
        case .full:
            break
        case .master:
            variantSlotTotalBySetCode = nextTotals
        case .grandMaster:
            grandMasterSlotTotalBySetCode = nextTotals
        }
    }

    private func resolveCollectionCardIdentity(
        for cardID: String,
        activeSetCodes: Set<String>
    ) async -> (setCode: String, uniqueCardKey: String)? {
        if let parsed = collectionCardIdentity(for: cardID), activeSetCodes.contains(parsed.setCode) {
            return parsed
        }

        guard let card = await services.cardData.loadCard(masterCardId: cardID) else { return nil }
        let setCode = card.setCode.lowercased()
        guard activeSetCodes.contains(setCode) else { return nil }
        if card.masterCardId.contains("::") {
            let number = card.cardNumber.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let uniqueKey = number.isEmpty ? card.masterCardId.lowercased() : "\(setCode)::\(number)"
            return (setCode, uniqueKey)
        }
        return (setCode, card.masterCardId.lowercased())
    }

    private func collectionCardIdentity(for cardID: String) -> (setCode: String, uniqueCardKey: String)? {
        let trimmed = cardID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        if trimmed.contains("::") {
            let parts = trimmed.components(separatedBy: "::")
            guard parts.count >= 2 else { return nil }
            let setCode = parts[0].lowercased()
            let cardNumber = parts[1].lowercased()
            guard setCode.isEmpty == false, cardNumber.isEmpty == false else { return nil }
            return (setCode, "\(setCode)::\(cardNumber)")
        }

        guard let separatorIndex = trimmed.firstIndex(of: "-"), separatorIndex > trimmed.startIndex else {
            return nil
        }
        let setCode = String(trimmed[..<separatorIndex]).lowercased()
        return (setCode, trimmed.lowercased())
    }

    private var setCompletionModeChipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(SetCompletionMode.allCases, id: \.self) { mode in
                    setCompletionModeChip(label: mode.chipLabel, mode: mode)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func setCompletionModeChip(label: String, mode: SetCompletionMode) -> some View {
        let isSelected = setCompletionMode == mode
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                setCompletionMode = mode
            }
            Haptics.lightImpact()
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? .white : .primary.opacity(0.85))
                .glassFilterChipStyle(isSelected: isSelected, accentColor: services.theme.accentColor)
        }
        .buttonStyle(.plain)
    }

    private func setProgress(for set: TCGSet) -> (collected: Int, total: Int?) {
        let setCode = set.setCode.lowercased()
        switch setCompletionMode {
        case .full:
            return (uniqueCollectedCountBySetCode[setCode] ?? 0, set.cardCountTotal)
        case .master:
            let collected = variantCollectedCountBySetCode[setCode] ?? 0
            let total = variantSlotTotalBySetCode[setCode] ?? set.masterSetTotal ?? set.cardCountTotal
            return (collected, total)
        case .grandMaster:
            let collected = grandMasterCollectedCountBySetCode[setCode] ?? 0
            let total = grandMasterSlotTotalBySetCode[setCode] ?? set.masterSetTotal ?? set.cardCountTotal
            return (collected, total)
        }
    }

    private func prefetchSetLogos() {
        let urls = filteredSets.compactMap { set in
            AppConfiguration.setLogoURLCandidates(logoSrc: set.logoSrc.trimmingCharacters(in: .whitespacesAndNewlines)).first
        }
        guard !urls.isEmpty else { return }
        ImagePrefetcher.shared.prefetch(urls, priority: .medium)
    }
}

private struct BrowsePokemonTabContent: View {
    @Environment(AppServices.self) private var services
    @Query private var collectionItems: [CollectionItem]

    let query: String
    let onSelectRoute: (BrowseInlineDetailRoute) -> Void

    @State private var rows: [NationalDexPokemon] = []
    @State private var isLoading = true
    @State private var ownedNationalDexIDs: Set<Int> = []
    @State private var dexCollectionProgress: [Int: (owned: Int, total: Int)] = [:]
    @State private var hideCollectedPokemon = false
    @State private var selectedGeneration: Int? = nil

    private let pokemonColumnCount = 3

    private var availableGenerations: [Int] {
        Array(Set(rows.compactMap(\.generation))).sorted()
    }

    private var filteredPokemonRows: [NationalDexPokemon] {
        let normalizedQuery = normalizedBrowseSearchText(query)
        var filtered = rows
        if !normalizedQuery.isEmpty {
            filtered = filtered.filter { item in
                normalizedBrowseSearchText(item.name).contains(normalizedQuery)
                    || normalizedBrowseSearchText(item.displayName).contains(normalizedQuery)
                    || normalizedBrowseSearchText(String(item.nationalDexNumber)).contains(normalizedQuery)
            }
        }
        if let gen = selectedGeneration {
            filtered = filtered.filter { $0.generation == gen }
        }
        if hideCollectedPokemon {
            filtered = filtered.filter { !ownedNationalDexIDs.contains($0.nationalDexNumber) }
        }
        return filtered
    }

    private var ownedDexTaskKey: Int {
        var h = Hasher()
        h.combine(services.brandSettings.selectedCatalogBrand.rawValue)
        for item in collectionItems where item.quantity > 0 {
            h.combine(item.cardID)
            h.combine(item.quantity)
        }
        for set in services.cardData.sets { h.combine(set.setCode) }
        return h.finalize()
    }

    private var hideCollectedToggleTitle: String {
        let scopedRows = selectedGeneration.map { gen in rows.filter { $0.generation == gen } } ?? rows
        let total = scopedRows.count
        let collected = scopedRows.filter { ownedNationalDexIDs.contains($0.nationalDexNumber) }.count
        return "Hide Collected (\(collected) of \(total) Pokemon collected)"
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading Pokémon…")
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .padding(.horizontal, 16)
            } else {
                pokemonBody
            }
        }
        .onAppear {
            scheduleRowLoad()
        }
        .onChange(of: services.brandSettings.selectedCatalogBrand) { _, _ in
            selectedGeneration = nil
            scheduleRowLoad()
        }
        .onChange(of: query) { _, newQuery in
            if !newQuery.isEmpty { selectedGeneration = nil }
        }
        .task(id: ownedDexTaskKey) {
            await refreshOwnedNationalDexIDs()
        }
    }

    @MainActor
    private func scheduleRowLoad() {
        Task { @MainActor in
            await loadRows()
        }
    }

    private var generationTagBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                generationChip(label: "All Gens", generation: nil)
                ForEach(availableGenerations, id: \.self) { gen in
                    generationChip(label: "Gen \(gen)", generation: gen)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func generationChip(label: String, generation: Int?) -> some View {
        let isSelected = selectedGeneration == generation
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selectedGeneration = isSelected && generation != nil ? nil : generation
            }
            Haptics.lightImpact()
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? .white : .primary.opacity(0.85))
                .glassFilterChipStyle(isSelected: isSelected, accentColor: services.theme.accentColor)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var pokemonBody: some View {
        if rows.isEmpty {
            ContentUnavailableView(
                "No Pokédex list",
                systemImage: "hare",
                description: Text("Add pokemon.json next to sets.json on your CDN.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
            .padding(.horizontal, 16)
        } else if filteredPokemonRows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                generationTagBar
                Toggle(hideCollectedToggleTitle, isOn: $hideCollectedPokemon)
                    .font(.caption.weight(.semibold))
                    .toggleStyle(.switch)
                    .padding(.horizontal, 16)

                ContentUnavailableView(
                    "No matching Pokémon",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different name or National Dex number.")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
                .padding(.horizontal, 16)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                generationTagBar
                Toggle(hideCollectedToggleTitle, isOn: $hideCollectedPokemon)
                    .font(.caption.weight(.semibold))
                    .toggleStyle(.switch)
                    .padding(.horizontal, 16)

                EagerVGrid(items: filteredPokemonRows, columns: pokemonColumnCount, spacing: BindrSpacing.cardGrid) { item in
                    Button {
                        onSelectRoute(.dex(dexId: item.nationalDexNumber, displayName: item.displayName))
                    } label: {
                        VStack(spacing: 6) {
                            let isOwned = ownedNationalDexIDs.contains(item.nationalDexNumber)
                            CachedAsyncImage(
                                url: AppConfiguration.pokemonArtURL(imageFileName: item.imageUrl)
                            ) { img in
                                img.resizable().scaledToFit()
                            } placeholder: {
                                Color.gray.opacity(0.12)
                            }
                            .saturation(isOwned ? 1.0 : 0.0)
                            .opacity(isOwned ? 1.0 : 0.35)
                            .frame(height: 140)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text("#\(item.nationalDexNumber)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                Text(dexCollectionSummary(for: item.nationalDexNumber))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private func loadRows() async {
        isLoading = true
        defer { isLoading = false }

        if services.cardData.nationalDexPokemon.isEmpty {
            await services.cardData.loadNationalDexPokemon()
        }
        rows = services.cardData.nationalDexPokemonSorted()
    }

    @MainActor
    private func refreshOwnedNationalDexIDs() async {
        guard services.brandSettings.selectedCatalogBrand == .pokemon else {
            ownedNationalDexIDs = []
            dexCollectionProgress = [:]
            return
        }

        var allPokemonCards: [Card] = []
        for set in services.cardData.sets {
            allPokemonCards.append(contentsOf: await services.cardData.loadCards(forSetCode: set.setCode))
        }

        var totalByDex: [Int: Int] = [:]
        for card in allPokemonCards {
            guard let dexIDs = card.dexIds else { continue }
            for dexID in Set(dexIDs) {
                totalByDex[dexID, default: 0] += 1
            }
        }

        let ownedCardIDs: Set<String> = Set(collectionItems.compactMap { item in
            guard item.quantity > 0 else { return nil }
            guard TCGBrand.inferredFromMasterCardId(item.cardID) == .pokemon else { return nil }
            return item.cardID
        })

        var nextOwnedDexIDs: Set<Int> = []
        var ownedByDex: [Int: Int] = [:]
        for cardID in ownedCardIDs {
            guard let card = await services.cardData.loadCard(masterCardId: cardID) else { continue }
            guard let dexIDs = card.dexIds else { continue }
            for dexID in Set(dexIDs) {
                nextOwnedDexIDs.insert(dexID)
                ownedByDex[dexID, default: 0] += 1
            }
        }

        var nextDexCollectionProgress: [Int: (owned: Int, total: Int)] = [:]
        for (dexID, total) in totalByDex {
            nextDexCollectionProgress[dexID] = (ownedByDex[dexID] ?? 0, total)
        }

        ownedNationalDexIDs = nextOwnedDexIDs
        dexCollectionProgress = nextDexCollectionProgress
    }

    private func dexCollectionSummary(for dexID: Int) -> String {
        let progress = dexCollectionProgress[dexID] ?? (0, 0)
        return "\(progress.owned) of \(progress.total) collected"
    }

}

private struct BrowseGridCardCell: View {
    @Environment(AppServices.self) private var services

    private static let thumbnailSize = CGSize(width: 220, height: 308)

    let card: Card
    let gridOptions: BrowseGridOptions
    let setName: String?

    private var imageDecodeSize: CGSize {
        Self.thumbnailSize
    }

    private var showsMetadataHeader: Bool {
        gridOptions.showCardName
            || (gridOptions.showSetName && !(setName?.isEmpty ?? true))
            || gridOptions.showSetID
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsMetadataHeader {
                VStack(alignment: .center, spacing: 1) {
                    if gridOptions.showCardName {
                        Text(card.cardName)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }
                    if gridOptions.showSetName, let setName, !setName.isEmpty {
                        Text(setName)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    if gridOptions.showSetID {
                        let cardID = card.cardNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                        Text(cardID.isEmpty ? card.setCode : cardID)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(.tertiary)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }

            CachedAsyncImage(
                url: AppConfiguration.imageURL(relativePath: card.displayImageSrc),
                targetSize: imageDecodeSize
            ) { img in
                img.resizable().scaledToFit()
            } placeholder: {
                Color.gray.opacity(0.12)
                    .aspectRatio(5/7, contentMode: .fit)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(5/7, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if gridOptions.showPricing {
                    BrowseGridPriceText(
                        services: services,
                        accentColor: services.theme.accentColor,
                        card: card,
                        alignment: .leading,
                        overlayTextColor: .white
                    )
                    .cardGridPriceBadgeStyle()
                }
            }
        }
    }
}

private struct PokemonOwnedPokeBallBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(Color.primary.opacity(0.9), lineWidth: 1.1))

            Circle()
                .trim(from: 0, to: 0.5)
                .fill(Color.red)
                .rotationEffect(.degrees(180))

            Rectangle()
                .fill(Color.primary.opacity(0.9))
                .frame(height: 1.1)

            Circle()
                .fill(Color.white)
                .frame(width: 6.6, height: 6.6)
                .overlay(Circle().stroke(Color.primary.opacity(0.9), lineWidth: 1.0))
        }
    }
}

private struct BrowseGridPriceText: View {
    @ObservationIgnored private let services: AppServices
    let accentColor: Color
    let taskKey: String

    let card: Card
    /// When set, displayed directly without a live lookup (used by collection grid for grade-correct pricing).
    var overridePrice: Double? = nil
    /// When set, shown as a small pill badge next to the price (e.g. "PSA 10", "ACE 10").
    var gradeLabel: String? = nil
    var precomputedPriceLine: String? = nil
    /// When true, render the resolved price in the current theme accent color.
    var usesAccentColor: Bool = false
    /// When set, show the price for this specific variant only (no range).
    var variantKey: String? = nil
    var alignment: HorizontalAlignment = .center
    /// When set, used for image-overlay pricing instead of accent/secondary colors.
    var overlayTextColor: Color? = nil

    /// `nil` until the pricing task finishes; then a single price, a `low - high` range, or an em dash when unknown.
    @State private var priceLine: String?

    init(
        services: AppServices,
        accentColor: Color,
        card: Card,
        overridePrice: Double? = nil,
        gradeLabel: String? = nil,
        precomputedPriceLine: String? = nil,
        usesAccentColor: Bool = false,
        variantKey: String? = nil,
        alignment: HorizontalAlignment = .center,
        overlayTextColor: Color? = nil
    ) {
        self.services = services
        self.accentColor = accentColor
        self.card = card
        self.overridePrice = overridePrice
        self.gradeLabel = gradeLabel
        self.precomputedPriceLine = precomputedPriceLine
        self.usesAccentColor = usesAccentColor
        self.variantKey = variantKey
        self.alignment = alignment
        self.overlayTextColor = overlayTextColor
        self.taskKey = Self.makeTaskKey(
            card: card,
            overridePrice: overridePrice,
            variantKey: variantKey,
            currencyRawValue: services.priceDisplay.currency.rawValue,
            usdToGbp: services.pricing.usdToGbp
        )
    }

    private static func makeTaskKey(
        card: Card,
        overridePrice: Double?,
        variantKey: String?,
        currencyRawValue: String,
        usdToGbp: Double
    ) -> String {
        "\(card.id)|\(overridePrice ?? -1)|\(variantKey ?? "")|\(currencyRawValue)|\(usdToGbp)"
    }

    var body: some View {
        Group {
            if let precomputedPriceLine {
                if precomputedPriceLine.isEmpty {
                    pricePlaceholder
                } else {
                    priceContent(precomputedPriceLine)
                }
            } else if let priceLine {
                priceContent(priceLine)
            } else {
                pricePlaceholder
            }
        }
        .task(id: taskKey) {
            guard precomputedPriceLine == nil else { return }
            if let cached = await BrowseGridPriceLineCache.shared.value(for: taskKey) {
                priceLine = cached
                return
            }
            priceLine = nil
            let currency = services.priceDisplay.currency
            let fx = services.pricing.usdToGbp
            if let usd = overridePrice {
                let line = currency.format(amountUSD: usd, usdToGbp: fx)
                priceLine = line
                await BrowseGridPriceLineCache.shared.set(line, for: taskKey)
                return
            }
            guard let entry = await services.pricing.pricing(for: card) else {
                if let fallbackUSD = await services.pricing.latestHistoryPriceUSD(for: card, variantKey: variantKey ?? "holofoil", grade: "raw") {
                    let line = currency.format(amountUSD: fallbackUSD, usdToGbp: fx)
                    priceLine = line
                    await BrowseGridPriceLineCache.shared.set(line, for: taskKey)
                } else {
                    priceLine = "—"
                    await BrowseGridPriceLineCache.shared.set("—", for: taskKey)
                }
                return
            }
            if let key = variantKey {
                var usd = entry.scrydex?[key]?.rawMarketEstimateUSD() ?? entry.tcgplayerMarketEstimateUSD()
                if usd == nil {
                    usd = await services.pricing.latestHistoryPriceUSD(for: card, variantKey: key, grade: "raw")
                }
                let line = usd.map { currency.format(amountUSD: $0, usdToGbp: fx) } ?? "—"
                priceLine = line
                await BrowseGridPriceLineCache.shared.set(line, for: taskKey)
                return
            }
            guard let range = resolvedMarketPriceRange(entry) else {
                var fallbackUSD = await services.pricing.latestHistoryPriceUSD(for: card, variantKey: "holofoil", grade: "raw")
                if fallbackUSD == nil {
                    fallbackUSD = await services.pricing.latestHistoryPriceUSD(for: card, variantKey: "normal", grade: "raw")
                }
                if fallbackUSD == nil {
                    fallbackUSD = await services.pricing.latestHistoryPriceUSD(for: card, variantKey: "reverseHolofoil", grade: "raw")
                }
                if let fallbackUSD {
                    let line = currency.format(amountUSD: fallbackUSD, usdToGbp: fx)
                    priceLine = line
                    await BrowseGridPriceLineCache.shared.set(line, for: taskKey)
                } else {
                    priceLine = "—"
                    await BrowseGridPriceLineCache.shared.set("—", for: taskKey)
                }
                return
            }
            if abs(range.max - range.min) < 0.005 {
                let line = currency.format(amountUSD: range.min, usdToGbp: fx)
                priceLine = line
                await BrowseGridPriceLineCache.shared.set(line, for: taskKey)
            } else {
                let low = currency.format(amountUSD: range.min, usdToGbp: fx)
                let high = currency.format(amountUSD: range.max, usdToGbp: fx)
                let line = "\(low) - \(high)"
                priceLine = line
                await BrowseGridPriceLineCache.shared.set(line, for: taskKey)
            }
        }
    }

    private func priceContent(_ priceLine: String) -> some View {
        HStack(spacing: 3) {
            if let gradeLabel {
                Text(gradeLabel)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1.5)
                    .background(accentColor, in: RoundedRectangle(cornerRadius: 3))
            }
            if let overlayTextColor {
                Text(priceLine)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(overlayTextColor)
            } else if usesAccentColor {
                Text(priceLine)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(accentColor)
            } else {
                Text(priceLine)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: alignment == .leading ? nil : .infinity, alignment: alignment == .leading ? .leading : .center)
    }

    private var pricePlaceholder: some View {
        Text(" ")
            .font(.caption2.weight(.semibold))
            .redacted(reason: .placeholder)
    }

    /// Min/max raw (ungraded) market USD across Scrydex variants on the card.
    private func resolvedMarketPriceRange(_ entry: CardPricingEntry) -> (min: Double, max: Double)? {
        if let scrydex = entry.scrydex, !scrydex.isEmpty {
            let values = scrydex.values.compactMap { $0.rawMarketEstimateUSD() }
            guard let minV = values.min(), let maxV = values.max() else { return nil }
            return (minV, maxV)
        }
        if let u = entry.tcgplayerMarketEstimateUSD() {
            return (u, u)
        }
        return nil
    }

}

private func sortCardsByReleaseDateNewestFirst(_ cards: [Card], sets: [TCGSet]) -> [Card] {
    guard !cards.isEmpty else { return cards }
    let dates = firstValueMap(sets, key: \.setCode) { $0.releaseDate ?? "" }
    return cards.sorted { a, b in
        let da = dates[a.setCode] ?? ""
        let db = dates[b.setCode] ?? ""
        if da != db {
            return da > db
        }
        if a.setCode != b.setCode {
            return a.setCode.localizedStandardCompare(b.setCode) == .orderedAscending
        }
        return a.cardNumber.localizedStandardCompare(b.cardNumber) == .orderedAscending
    }
}

private func sortBrowseFilterCardsByReleaseDateNewestFirst(_ cards: [BrowseFilterCard], sets: [TCGSet]) -> [BrowseFilterCard] {
    guard !cards.isEmpty else { return cards }
    let dates = firstValueMap(sets, key: \.setCode) { $0.releaseDate ?? "" }
    return cards.sorted { a, b in
        let da = dates[a.setCode] ?? ""
        let db = dates[b.setCode] ?? ""
        if da != db {
            return da > db
        }
        if a.setCode != b.setCode {
            return a.setCode.localizedStandardCompare(b.setCode) == .orderedAscending
        }
        return a.cardNumber.localizedStandardCompare(b.cardNumber) == .orderedAscending
    }
}

private func firstValueMap<Input, Key: Hashable, Value>(
    _ values: [Input],
    key: KeyPath<Input, Key>,
    value: (Input) -> Value
) -> [Key: Value] {
    var out: [Key: Value] = [:]
    out.reserveCapacity(values.count)
    for item in values where out[item[keyPath: key]] == nil {
        out[item[keyPath: key]] = value(item)
    }
    return out
}

private func chunkedBrowseCards(_ cards: [Card], columnCount: Int) -> [[Card]] {
    guard columnCount > 0, cards.isEmpty == false else { return [] }
    var rows: [[Card]] = []
    rows.reserveCapacity((cards.count + columnCount - 1) / columnCount)
    var index = 0
    while index < cards.count {
        let end = min(index + columnCount, cards.count)
        rows.append(Array(cards[index..<end]))
        index = end
    }
    return rows
}

private func safeBrowseGridColumnCount(_ count: Int) -> Int {
    min(max(count, 1), 4)
}

// MARK: - Set cards

struct SetCardsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.presentCard) private var presentCard
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var collectionItems: [CollectionItem]
    @Query(sort: \WishlistItem.dateAdded, order: .reverse) private var wishlistItems: [WishlistItem]
    let set: TCGSet

    @State private var cards: [Card] = []
    @State private var isLoading = true
    @State private var query = ""
    @State private var filters = BrowseCardGridFilters()
    @State private var priceByCardID: [String: Double] = [:]

    // Multi-select
    @State private var isMultiSelectActive = false
    @State private var selectedCardIDs: Set<String> = []
    @State private var multiSelectCollectionPayload: MultiSelectCollectionPayload?
    @State private var wishlistAlertMessage: String?
    @State private var showWishlistAlert = false
    @State private var showWishlistPaywall = false

    @State private var pendingCardContextRequest: CardContextActionRequest?
    @State private var setTrendChanges: (change1d: Double?, change7d: Double?, change30d: Double?) = (nil, nil, nil)

    @State private var ownedCardIDs: Set<String> = []
    @State private var ownedQuantityByCardID: [String: Int] = [:]

    private func rebuildOwnershipCaches() {
        let brand = services.brandSettings.selectedCatalogBrand
        var ids = Set<String>(minimumCapacity: collectionItems.count)
        var qty = [String: Int](minimumCapacity: collectionItems.count)
        for item in collectionItems {
            guard TCGBrand.inferredFromMasterCardId(item.cardID) == brand else { continue }
            ids.insert(item.cardID)
            if item.quantity > 0 { qty[item.cardID, default: 0] += item.quantity }
        }
        ownedCardIDs = ids
        ownedQuantityByCardID = qty
    }

    private var wishlistedCardIDs: Set<String> {
        Set(wishlistItems.compactMap { item in
            let brand = TCGBrand.inferredFromMasterCardId(item.cardID)
            return brand == services.brandSettings.selectedCatalogBrand ? item.cardID : nil
        })
    }

    private var filteredCards: [Card] {
        filterBrowseCards(
            cards,
            query: query,
            filters: filters,
            ownedCardIDs: ownedCardIDs,
            brand: services.brandSettings.selectedCatalogBrand,
            sets: services.cardData.sets,
            priceByCardID: priceByCardID
        )
    }

    private var priceCacheTaskKey: String {
        "\(services.brandSettings.selectedCatalogBrand.rawValue)#\(cards.count)#\(cards.first?.masterCardId ?? "")#\(cards.last?.masterCardId ?? "")"
    }

    private var selectedCards: [Card] {
        cards.filter { selectedCardIDs.contains($0.masterCardId) }
    }

    private var glassButtonBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
    }

    private var glassButtonBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private var uniqueOwnedInSet: Int {
        cards.filter { ownedCardIDs.contains($0.masterCardId) }.count
    }

    private var totalSetValueUSD: Double {
        priceByCardID.values.reduce(0, +)
    }

    private var ownedSetValueUSD: Double {
        cards
            .filter { ownedCardIDs.contains($0.masterCardId) }
            .compactMap { priceByCardID[$0.masterCardId] }
            .reduce(0, +)
    }

    private var setProgressBar: some View {
        let total = cards.count
        let owned = uniqueOwnedInSet
        let progress = total > 0 ? CGFloat(owned) / CGFloat(total) : 0
        let currency = services.priceDisplay.currency
        let fx = services.pricing.usdToGbp
        let totalValue = totalSetValueUSD
        let ownedValue = ownedSetValueUSD
        let remainingValue = max(totalValue - ownedValue, 0)
        let hasPrices = totalValue > 0

        return VStack(spacing: 14) {
            // Header row
            HStack(alignment: .firstTextBaseline) {
                Text("Set Completion")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(owned)")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(services.theme.accentColor)
                    Text("/ \(total)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [services.theme.accentColor, services.theme.accentColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * progress, 10))
                        .shadow(color: services.theme.accentColor.opacity(0.3), radius: 6, x: 0, y: 0)
                        .overlay {
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.4), .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                        }
                }
            }
            .frame(height: 10)

            // Value row — always shown; dashes until prices load
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SET VALUE")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(hasPrices ? currency.format(amountUSD: totalValue, usdToGbp: fx) : "—")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                Spacer()

                VStack(alignment: .center, spacing: 2) {
                    Text("COLLECTED")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(hasPrices ? currency.format(amountUSD: ownedValue, usdToGbp: fx) : "—")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("TO COMPLETE")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(hasPrices ? currency.format(amountUSD: remainingValue, usdToGbp: fx) : "—")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(hasPrices ? services.theme.accentColor : .secondary)
                }
            }

            // Trend badges — always show row; shimmer/empty until loaded
            HStack(spacing: 8) {
                let trends = setTrendChanges
                Spacer()
                setTrendBadge(label: "1D", value: trends.change1d)
                setTrendBadge(label: "7D", value: trends.change7d)
                setTrendBadge(label: "30D", value: trends.change30d)
                if trends.change1d == nil && trends.change7d == nil && trends.change30d == nil {
                    Text("Loading trends…")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
        .padding(16)
        .glassCardStyle(cornerRadius: 16, interactive: false)
    }

    @ViewBuilder
    private func setTrendBadge(label: String, value: Double?) -> some View {
        if let value {
            let isUp = value >= 0
            let tint = isUp ? Color(red: 0.2, green: 0.78, blue: 0.35) : Color(red: 0.95, green: 0.27, blue: 0.27)
            HStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint.opacity(0.8))
                Image(systemName: isUp ? "arrow.up" : "arrow.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(tint)
                Text(String(format: "%.1f%%", abs(value)))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.12)))
        }
    }

    var body: some View {
        let accentColor = services.theme.accentColor
        ZStack(alignment: .bottom) {
            ScrollView {
                if isLoading {
                    ProgressView().padding()
                } else {
                    VStack(spacing: 12) {
                        BrowseInlineSearchField(title: "Search \(cards.count) cards in set", text: $query)
                            .padding(.top, 2)

                        setProgressBar
                            .padding(.bottom, 4)

                        Toggle("Hide owned cards", isOn: $filters.hideOwned)
                            .font(.caption.weight(.semibold))
                            .toggleStyle(.switch)

                        if filteredCards.isEmpty {
                            ContentUnavailableView(
                                "No matching cards",
                                systemImage: "magnifyingglass",
                                description: Text("Try a different card name or number.")
                            )
                            .padding(.bottom)
                        } else {
                            EagerVGrid(items: filteredCards.indexedIdentifiedValues, columns: safeBrowseGridColumnCount(services.browseGridOptions.options.columnCount), spacing: BindrSpacing.cardGrid) { indexedCard in
                                let card = indexedCard.value
                                let isSelected = selectedCardIDs.contains(card.masterCardId)
                                Button {
                                    if isMultiSelectActive {
                                        toggleSelection(card)
                                    } else {
                                        presentCard(card, filteredCards)
                                    }
                                } label: {
                                    CardGridCell(
                                        card: card,
                                        services: services,
                                        colorScheme: colorScheme,
                                        accentColor: accentColor,
                                        gridOptions: services.browseGridOptions.options,
                                        setName: set.name,
                                        isOwned: ownedCardIDs.contains(card.masterCardId),
                                        isWishlisted: wishlistedCardIDs.contains(card.masterCardId),
                                        ownedCountBadge: ownedQuantityByCardID[card.masterCardId]
                                    )
                                    .overlay(alignment: .topTrailing) {
                                        if isMultiSelectActive {
                                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 22, weight: .semibold))
                                                .foregroundStyle(isSelected ? Color.blue : Color.white)
                                                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                                                .padding(6)
                                        }
                                    }
                                }
                                .buttonStyle(CardCellButtonStyle())
                                .contextMenu {
                                    Button {
                                        beginCardContextAction(card: card, action: .collection)
                                    } label: {
                                        Label("Add to Collection", systemImage: "books.vertical")
                                    }
                                    Button {
                                        beginCardContextAction(card: card, action: .wishlist)
                                    } label: {
                                        Label("Add to Wishlist", systemImage: "heart")
                                    }
                                }
                                .onAppear {
                                    guard indexedCard.index.isMultiple(of: max(safeBrowseGridColumnCount(services.browseGridOptions.options.columnCount), 1)) else { return }
                                    ImagePrefetcher.shared.prefetchCardWindow(filteredCards, startingAt: indexedCard.index + 1)
                                }
                            }
                            .padding(.bottom, isMultiSelectActive && !selectedCardIDs.isEmpty ? 88 : 0)
                        }
                    }
                    .padding(.horizontal, BindrSpacing.cardGridScreenInset)
                }
            }
            .id(set.id)

            if isMultiSelectActive && !selectedCardIDs.isEmpty {
                multiSelectActionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isMultiSelectActive && !selectedCardIDs.isEmpty)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            BrowseDetailNavBar(
                title: set.name,
                isFilterActive: filters.isVisiblyCustomized,
                isGridOptionsActive: !services.browseGridOptions.options.isDefault
            ) {
                BrowseGridFiltersMenuContent(
                    brand: services.brandSettings.selectedCatalogBrand,
                    filters: $filters,
                    energyOptions: cardEnergyOptions(cards),
                    rarityOptions: cardRarityOptions(cards),
                    trainerTypeOptions: cardTrainerTypeOptions(cards),
                    config: FilterMenuConfig(showGridOptions: false)
                )
            } gridMenuContent: {
                BrowseGridOptionsMenuContent()
            }
        }
        .sheet(item: $multiSelectCollectionPayload) { payload in
            MultiSelectAddToCollectionSheet(cards: payload.cards)
                .environment(services)
        }
        .sheet(item: $pendingCardContextRequest) { req in
            CardContextActionSheet(request: req)
                .environment(services)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showWishlistPaywall) {
            PaywallSheet()
                .environment(services)
        }
        .alert("Wishlist", isPresented: $showWishlistAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(wishlistAlertMessage ?? "")
        }
        .task {
            isLoading = true
            let loaded = await services.cardData.loadCards(forSetCode: set.setCode)
            cards = sortCardsByLocalIdHighestFirst(loaded)
            ImagePrefetcher.shared.prefetchCardWindow(cards, startingAt: 0, count: 12)
            isLoading = false
        }
        .task(id: priceCacheTaskKey) {
            await refreshPriceCache()
        }
        .onChange(of: filters.sortBy) { _, sortBy in
            guard sortBy == .price else { return }
            Task { @MainActor in
                await refreshPriceCache()
            }
        }
        .onAppear { rebuildOwnershipCaches() }
        .onChange(of: collectionItems) { _, _ in rebuildOwnershipCaches() }
        .onChange(of: services.brandSettings.selectedCatalogBrand) { _, _ in rebuildOwnershipCaches() }
    }

    private var multiSelectActionBar: some View {
        HStack(spacing: 8) {
            multiSelectActionButton(
                title: "Add to Collection",
                systemImage: "plus.circle.fill",
                tint: Color(red: 0.28, green: 0.84, blue: 0.39)
            ) {
                multiSelectCollectionPayload = MultiSelectCollectionPayload(cards: selectedCards)
            }
            multiSelectActionButton(
                title: "Wish List",
                systemImage: "star",
                tint: Color(red: 0.99, green: 0.72, blue: 0.22)
            ) {
                addSelectedToWishlist()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .safeAreaPadding(.bottom, 0)
    }

    private func multiSelectActionButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(glassButtonBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(glassButtonBorder, lineWidth: 1)
                    )
            }
            .accessibilityLabel(title)
        }
        .buttonStyle(.plain)
    }

    private func toggleSelection(_ card: Card) {
        if selectedCardIDs.contains(card.masterCardId) {
            selectedCardIDs.remove(card.masterCardId)
        } else {
            selectedCardIDs.insert(card.masterCardId)
            HapticManager.impact(.light)
        }
    }

    private func addSelectedToWishlist() {
        guard let wl = services.wishlist else {
            wishlistAlertMessage = "Wishlist isn't available yet. Try again in a moment."
            showWishlistAlert = true
            return
        }
        var addedCount = 0
        for card in selectedCards {
            do {
                try wl.addItem(cardID: card.masterCardId, variantKey: "normal", notes: "")
                addedCount += 1
            } catch let error as WishlistError {
                switch error {
                case .limitReached:
                    showWishlistPaywall = true
                    return
                case .alreadyExists:
                    break
                case .saveFailed:
                    break
                }
            } catch {
                break
            }
        }
        if addedCount > 0 {
            HapticManager.notification(.success)
        }
    }

    @MainActor
    private func refreshPriceCache() async {
        guard !cards.isEmpty else {
            priceByCardID = [:]
            return
        }
        await services.pricing.prefetchPokemonCardPricing(forSetCodes: [])
        await services.pricing.indexPricingForCards(cards)

        var next: [String: Double] = [:]
        next.reserveCapacity(cards.count)
        var misses: [Card] = []
        misses.reserveCapacity(8)

        for card in cards {
            if services.pricing.isPricingIndexed(for: card) {
                if let usd = browseMarketPriceUSD(for: services.pricing.cachedPricingEntry(for: card)) {
                    next[card.masterCardId] = usd
                }
            } else {
                misses.append(card)
            }
        }

        if !misses.isEmpty {
            var offset = 0
            while offset < misses.count {
                guard !Task.isCancelled else { break }
                let batch = Array(misses[offset..<min(offset + 8, misses.count)])
                await withTaskGroup(of: (String, Double?).self) { group in
                    for card in batch {
                        group.addTask {
                            guard let entry = await services.pricing.pricing(for: card),
                                  let usd = browseMarketPriceUSD(for: entry) else {
                                return (card.masterCardId, nil)
                            }
                            return (card.masterCardId, usd)
                        }
                    }
                    for await (id, usd) in group {
                        if let usd { next[id] = usd }
                    }
                }
                offset += 8
            }
        }

        priceByCardID = next
        await refreshSetTrends()
    }

    @MainActor
    private func refreshSetTrends() async {
        var sum1d = 0.0; var count1d = 0
        var sum7d = 0.0; var count7d = 0
        var sum30d = 0.0; var count30d = 0

        for card in cards {
            guard let trends = await services.pricing.priceTrends(for: card) else { continue }
            let candidates = ["holofoil", "normal", trends.variant]
            var resolved: (change1d: Double?, change7d: Double?, change30d: Double?) = (nil, nil, nil)
            for variant in candidates {
                let c = trends.changes(for: variant, grade: "raw")
                if c.change1d != nil || c.change7d != nil || c.change30d != nil {
                    resolved = c
                    break
                }
            }
            if resolved.change1d == nil && resolved.change7d == nil && resolved.change30d == nil {
                resolved = (trends.change1d, trends.change7d, trends.change30d)
            }
            if let v = resolved.change1d { sum1d += v; count1d += 1 }
            if let v = resolved.change7d { sum7d += v; count7d += 1 }
            if let v = resolved.change30d { sum30d += v; count30d += 1 }
        }

        setTrendChanges = (
            change1d: count1d > 0 ? sum1d / Double(count1d) : nil,
            change7d: count7d > 0 ? sum7d / Double(count7d) : nil,
            change30d: count30d > 0 ? sum30d / Double(count30d) : nil
        )
    }

    private func beginCardContextAction(card: Card, action: CardContextAction) {
        if action == .wishlist {
            addCardToWishlist(card)
            return
        }
        Task {
            var keys = await services.pricing.variantKeys(for: card)
            if keys.isEmpty, let variants = card.pricingVariants, !variants.isEmpty {
                keys = variants
            }
            if keys.isEmpty { keys = ["normal"] }
            let sortedKeys = Array(Set(keys)).sorted()
            await MainActor.run {
                pendingCardContextRequest = CardContextActionRequest(
                    card: card,
                    availableVariantKeys: sortedKeys,
                    initialVariantKey: sortedKeys.first ?? "normal",
                    initialAction: action
                )
            }
        }
    }

    private func addCardToWishlist(_ card: Card) {
        guard let wl = services.wishlist else {
            wishlistAlertMessage = "Wishlist isn't available yet. Try again in a moment."
            showWishlistAlert = true
            return
        }
        do {
            try wl.addItem(cardID: card.masterCardId, variantKey: "normal", notes: "")
            HapticManager.notification(.success)
        } catch let error as WishlistError {
            switch error {
            case .limitReached:
                showWishlistPaywall = true
            case .alreadyExists:
                break
            case .saveFailed:
                wishlistAlertMessage = "Couldn’t add card to wishlist. Please try again."
                showWishlistAlert = true
            }
        } catch {
            wishlistAlertMessage = "Couldn’t add card to wishlist. Please try again."
            showWishlistAlert = true
        }
    }
}

/// Browse-by-set grid: highest catalog `localId` first (numeric when possible); ties and missing `localId` use `masterCardId`.
private func sortCardsByLocalIdHighestFirst(_ cards: [Card]) -> [Card] {
    cards.sorted { a, b in
        let va = localIdNumericSortValue(a.localId)
        let vb = localIdNumericSortValue(b.localId)
        if va != vb { return va > vb }
        return a.masterCardId > b.masterCardId
    }
}

/// Parses `localId` like `"102"` for ordering; missing or non-numeric sorts last (same as `Int.min`).
private func localIdNumericSortValue(_ raw: String?) -> Int {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
        return Int.min
    }
    if let v = Int(raw) { return v }
    let digits = raw.prefix { $0.isNumber }
    if let v = Int(String(digits)), !digits.isEmpty { return v }
    return Int.min
}

// MARK: - Dex cards

struct DexCardsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.presentCard) private var presentCard
    @Environment(\.colorScheme) private var colorScheme
    @Query private var collectionItems: [CollectionItem]
    @Query(sort: \WishlistItem.dateAdded, order: .reverse) private var wishlistItems: [WishlistItem]
    let dexId: Int
    let displayName: String

    @State private var cards: [Card] = []
    @State private var isLoading = true
    @State private var query = ""
    @State private var filters = BrowseCardGridFilters()
    @State private var priceByCardID: [String: Double] = [:]

    @State private var ownedCardIDs: Set<String> = []
    @State private var ownedQuantityByCardID: [String: Int] = [:]

    private var setNameByCode: [String: String] {
        firstValueMap(services.cardData.sets, key: \.setCode, value: \.name)
    }

    private func rebuildOwnershipCaches() {
        let brand = services.brandSettings.selectedCatalogBrand
        var ids = Set<String>(minimumCapacity: collectionItems.count)
        var qty = [String: Int](minimumCapacity: collectionItems.count)
        for item in collectionItems {
            guard TCGBrand.inferredFromMasterCardId(item.cardID) == brand else { continue }
            ids.insert(item.cardID)
            if item.quantity > 0 { qty[item.cardID, default: 0] += item.quantity }
        }
        ownedCardIDs = ids
        ownedQuantityByCardID = qty
    }

    private var wishlistedCardIDs: Set<String> {
        Set(wishlistItems.compactMap { item in
            let brand = TCGBrand.inferredFromMasterCardId(item.cardID)
            return brand == services.brandSettings.selectedCatalogBrand ? item.cardID : nil
        })
    }

    private var filteredCards: [Card] {
        filterBrowseCards(
            cards,
            query: query,
            filters: filters,
            ownedCardIDs: ownedCardIDs,
            brand: services.brandSettings.selectedCatalogBrand,
            sets: services.cardData.sets,
            priceByCardID: priceByCardID
        )
    }

    private var priceCacheTaskKey: String {
        "\(services.brandSettings.selectedCatalogBrand.rawValue)#\(cards.count)#\(cards.first?.masterCardId ?? "")#\(cards.last?.masterCardId ?? "")"
    }

    var body: some View {
        let accentColor = services.theme.accentColor
        ScrollView {
            if isLoading {
                ProgressView().padding()
            } else {
                VStack(spacing: 12) {
                    BrowseInlineSearchField(title: "Search cards for Pokémon", text: $query)
                        .padding(.horizontal)
                        .padding(.top, 2)
                    if filteredCards.isEmpty {
                        ContentUnavailableView(
                            "No matching cards",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different card name or number.")
                        )
                        .padding(.horizontal)
                        .padding(.bottom)
                    } else {
                        EagerVGrid(items: filteredCards.indexedIdentifiedValues, columns: safeBrowseGridColumnCount(services.browseGridOptions.options.columnCount), spacing: BindrSpacing.cardGrid) { indexedCard in
                            let card = indexedCard.value
                            Button {
                                presentCard(card, filteredCards)
                            } label: {
                                CardGridCell(
                                    card: card,
                                    services: services,
                                    colorScheme: colorScheme,
                                    accentColor: accentColor,
                                    gridOptions: services.browseGridOptions.options,
                                    setName: setNameByCode[card.setCode],
                                    isOwned: ownedCardIDs.contains(card.masterCardId),
                                    isWishlisted: wishlistedCardIDs.contains(card.masterCardId),
                                    ownedCountBadge: ownedQuantityByCardID[card.masterCardId]
                                )
                        }
                        .buttonStyle(CardCellButtonStyle())
                        .onAppear {
                            guard indexedCard.index.isMultiple(of: max(safeBrowseGridColumnCount(services.browseGridOptions.options.columnCount), 1)) else { return }
                            ImagePrefetcher.shared.prefetchCardWindow(filteredCards, startingAt: indexedCard.index + 1)
                        }
                    }
                        .padding(.horizontal, BindrSpacing.cardGridScreenInset)
                        .padding(.bottom)
                    }
                }
            }
        }
        .id(dexId)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            BrowseDetailNavBar(
                title: displayName,
                isFilterActive: filters.isVisiblyCustomized,
                isGridOptionsActive: !services.browseGridOptions.options.isDefault
            ) {
                BrowseGridFiltersMenuContent(
                    brand: services.brandSettings.selectedCatalogBrand,
                    filters: $filters,
                    energyOptions: cardEnergyOptions(cards),
                    rarityOptions: cardRarityOptions(cards),
                    trainerTypeOptions: cardTrainerTypeOptions(cards),
                    config: FilterMenuConfig(showGridOptions: false)
                )
            } gridMenuContent: {
                BrowseGridOptionsMenuContent()
            }
        }
        .task {
            isLoading = true
            cards = await services.cardData.cards(matchingNationalDex: dexId)
            ImagePrefetcher.shared.prefetchCardWindow(cards, startingAt: 0, count: 12)
            isLoading = false
        }
        .task(id: priceCacheTaskKey) {
            await refreshPriceCache()
        }
        .onChange(of: filters.sortBy) { _, sortBy in
            guard sortBy == .price else { return }
            Task { @MainActor in
                await refreshPriceCache()
            }
        }
        .onAppear { rebuildOwnershipCaches() }
        .onChange(of: collectionItems) { _, _ in rebuildOwnershipCaches() }
        .onChange(of: services.brandSettings.selectedCatalogBrand) { _, _ in rebuildOwnershipCaches() }
    }

    @MainActor
    private func refreshPriceCache() async {
        guard !cards.isEmpty else {
            priceByCardID = [:]
            return
        }
        await services.pricing.prefetchPokemonCardPricing(forSetCodes: [])
        await services.pricing.indexPricingForCards(cards)

        var next: [String: Double] = [:]
        next.reserveCapacity(cards.count)
        var misses: [Card] = []
        misses.reserveCapacity(8)

        for card in cards {
            if services.pricing.isPricingIndexed(for: card) {
                if let usd = browseMarketPriceUSD(for: services.pricing.cachedPricingEntry(for: card)) {
                    next[card.masterCardId] = usd
                }
            } else {
                misses.append(card)
            }
        }

        if !misses.isEmpty {
            var offset = 0
            while offset < misses.count {
                guard !Task.isCancelled else { break }
                let batch = Array(misses[offset..<min(offset + 8, misses.count)])
                await withTaskGroup(of: (String, Double?).self) { group in
                    for card in batch {
                        group.addTask {
                            guard let entry = await services.pricing.pricing(for: card),
                                  let usd = browseMarketPriceUSD(for: entry) else {
                                return (card.masterCardId, nil)
                            }
                            return (card.masterCardId, usd)
                        }
                    }
                    for await (id, usd) in group {
                        if let usd { next[id] = usd }
                    }
                }
                offset += 8
            }
        }

        priceByCardID = next
    }
}

private struct BrowseDetailNavBar<FilterMenuContent: View, GridMenuContent: View>: View {
    let title: String
    let isFilterActive: Bool
    let isGridOptionsActive: Bool
    @ViewBuilder let filterMenuContent: () -> FilterMenuContent
    @ViewBuilder let gridMenuContent: () -> GridMenuContent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BindrPageHeader(
            title: title,
            leading: {
                ChromeGlassCircleButton(accessibilityLabel: "Back") { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }
            },
            trailing: {
                HStack(spacing: 8) {
                    Menu {
                        gridMenuContent()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)
                            .modifier(ChromeGlassCircleGlyphModifier())
                    }
                    .buttonStyle(.plain)
                    .menuActionDismissBehavior(.disabled)
                    .menuOrder(.fixed)
                    .menuIndicator(.hidden)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Grid options")

                    Menu {
                        filterMenuContent()
                    } label: {
                        Image(systemName: isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)
                            .modifier(ChromeGlassCircleGlyphModifier())
                    }
                    .buttonStyle(.plain)
                    .menuActionDismissBehavior(.disabled)
                    .menuOrder(.fixed)
                    .menuIndicator(.hidden)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Filters")
                }
            }
        )
    }
}

struct BrowseFilterToolbarButton: View {
    let isActive: Bool

    var body: some View {
        Image(systemName: isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(isActive ? Color.blue : Color.primary)
            .modifier(ChromeGlassCircleGlyphModifier())
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
    }
}

struct FilterMenuConfig {
    var showSortBy: Bool = true
    var showAcquiredDateSort: Bool = false
    var showRandomSort: Bool = true
    var showCardNumberSort: Bool = true
    var showBrandFilters: Bool = true
    var showCardFilters: Bool = true
    var showRarity: Bool = true
    var showRarePlusOnly: Bool = true
    var showHideOwned: Bool = true
    var showOwnedOnly: Bool = true
    var showShowDuplicates: Bool = false
    var showGridOptions: Bool = true
    var defaultSortBy: BrowseCardGridSortOption = .random
    var gridNameToggleTitle: String = "Show card name"
    var showGridCardIDToggle: Bool = true
    var showGridColumns: Bool = true
    var showGridOwnedToggle: Bool = true
    var showSealedProductTypeFilter: Bool = false

    static let browse = FilterMenuConfig()
    static let collect = FilterMenuConfig(
        showAcquiredDateSort: true,
        showRandomSort: false,
        showCardNumberSort: false,
        showHideOwned: false,
        showOwnedOnly: false,
        showShowDuplicates: true,
        defaultSortBy: .price
    )
    static let products = FilterMenuConfig(
        showAcquiredDateSort: false,
        showCardNumberSort: false,
        showBrandFilters: false,
        showCardFilters: false,
        showRarity: false,
        showRarePlusOnly: false,
        showHideOwned: false,
        showShowDuplicates: false,
        showGridOptions: false,
        defaultSortBy: .newestSet,
        gridNameToggleTitle: "Show product name",
        showGridCardIDToggle: false,
        showGridColumns: true,
        showGridOwnedToggle: false,
        showSealedProductTypeFilter: true
    )
    static let friendBrowsable = FilterMenuConfig(
        showAcquiredDateSort: true,
        showRandomSort: false,
        showCardNumberSort: false,
        showHideOwned: false,
        showOwnedOnly: false,
        showShowDuplicates: false,
        showGridOptions: false,
        defaultSortBy: .acquiredDateNewest,
        showGridOwnedToggle: false
    )
}

struct BrowseGridFiltersMenuContent: View {
    @Environment(AppServices.self) private var services

    let brand: TCGBrand
    @Binding var filters: BrowseCardGridFilters
    let energyOptions: [String]
    let rarityOptions: [String]
    let trainerTypeOptions: [String]
    var isAllBrands: Bool = false
    /// When nil, falls back to `services.browseGridOptions` (browse behaviour). Pass a binding to use separate grid options.
    var gridOptions: Binding<BrowseGridOptions>? = nil
    var config: FilterMenuConfig = .browse

    var body: some View {
        if filters.isVisiblyCustomized || filters.sortBy != config.defaultSortBy {
            Section {
                Button(role: .destructive) {
                    filters = BrowseCardGridFilters()
                    filters.sortBy = config.defaultSortBy
                } label: {
                    Label("Reset filters", systemImage: "arrow.counterclockwise.circle")
                }
            }
        }

        Section("Sort by") {
            Menu {
                Picker("Sort by", selection: $filters.sortBy) {
                    ForEach(BrowseCardGridSortOption.allCases.filter {
                        ($0 != .acquiredDateNewest || config.showAcquiredDateSort)
                            && ($0 != .random || config.showRandomSort)
                            && ($0 != .cardNumber || config.showCardNumberSort)
                    }) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Label(menuTitle("Sort by", summary: filters.sortBy.title), systemImage: "arrow.up.arrow.down.circle")
            }
            .menuActionDismissBehavior(.disabled)
            .menuOrder(.fixed)
        }

        if !isAllBrands && config.showCardFilters {
        Section("Filters") {
            filterMenu(title: "Series", summary: selectionSummary(for: filters.seriesNames), systemImage: "books.vertical") {
                let seriesOptions = browseFilterSeriesOptions(from: services.cardData.sets)
                if seriesOptions.isEmpty {
                    Text("No series available")
                } else {
                    ForEach(seriesOptions, id: \.self) { series in
                        Toggle(series, isOn: stringBinding(for: series, keyPath: \.seriesNames))
                    }
                }
            }
            filterMenu(title: "Card type", summary: selectionSummary(for: filters.cardTypes), systemImage: "square.stack.3d.up") {
                ForEach(BrowseCardTypeFilter.pokemonOptions) { type in
                    Toggle(type.title, isOn: cardTypeBinding(for: type))
                }
            }
            filterMenu(title: "Legal", summary: selectionSummary(for: filters.legalities), systemImage: "checkmark.shield") {
                ForEach(BrowseCardLegalityFilter.allCases) { legality in
                    Toggle(legality.title, isOn: legalityBinding(for: legality))
                }
            }

            filterMenu(title: brand.energyFilterMenuTitle, summary: selectionSummary(for: filters.energyTypes), systemImage: "bolt.circle") {
                if energyOptions.isEmpty {
                    Text("No options available")
                } else {
                    ForEach(energyOptions, id: \.self) { energy in
                        Toggle(energy, isOn: stringBinding(for: energy, keyPath: \.energyTypes))
                    }
                }
            }

            filterMenu(title: "Trainer type", summary: selectionSummary(for: filters.trainerTypes), systemImage: "person.crop.square") {
                if trainerTypeOptions.isEmpty {
                    Text("No trainer types available")
                } else {
                    ForEach(trainerTypeOptions, id: \.self) { trainerType in
                        Toggle(trainerType, isOn: stringBinding(for: trainerType, keyPath: \.trainerTypes))
                    }
                }
            }
            filterMenu(title: "Weakness", summary: selectionSummary(for: filters.weaknessTypes), systemImage: "shield.lefthalf.filled") {
                ForEach(pokemonWeaknessFilterAllOptions, id: \.self) { weakness in
                    Toggle(weakness, isOn: stringBinding(for: weakness, keyPath: \.weaknessTypes))
                }
            }
            filterMenu(title: "Resistance", summary: selectionSummary(for: filters.resistanceTypes), systemImage: "shield.righthalf.filled") {
                ForEach(pokemonResistanceFilterAllOptions, id: \.self) { resistance in
                    Toggle(resistance, isOn: stringBinding(for: resistance, keyPath: \.resistanceTypes))
                }
            }
            filterMenu(title: "Subtype", summary: selectionSummary(for: filters.pokemonSubtypes), systemImage: "square.grid.2x2") {
                ForEach(pokemonSubtypeAllOptions, id: \.self) { subtype in
                    Toggle(subtype, isOn: stringBinding(for: subtype, keyPath: \.pokemonSubtypes))
                }
            }
            filterMenu(title: "Ability", summary: filters.abilityPresence?.title, systemImage: "wand.and.rays") {
                ForEach(BrowseCardAbilityPresenceFilter.allCases) { option in
                    Toggle(option.title, isOn: abilityPresenceBinding(for: option))
                }
            }

            if config.showSealedProductTypeFilter {
                filterMenu(title: "Product type", summary: selectionSummary(for: filters.productTypes), systemImage: "shippingbox") {
                    ForEach(productTypeFilterOptions) { option in
                        Toggle(option.title, isOn: stringBinding(for: option.id, keyPath: \.productTypes))
                    }
                }
            }
        }

        if config.showRarity || config.showRarePlusOnly || config.showHideOwned || config.showOwnedOnly || config.showShowDuplicates {
            Section("Collection") {
                if config.showRarity {
                    filterMenu(title: "Rarity", summary: selectionSummary(for: filters.rarities), systemImage: "sparkles") {
                        if rarityOptions.isEmpty {
                            Text("No rarities available")
                        } else {
                            ForEach(rarityOptions, id: \.self) { rarity in
                                Toggle(rarity, isOn: stringBinding(for: rarity, keyPath: \.rarities))
                            }
                        }
                    }
                }
                if config.showRarePlusOnly {
                    Toggle(isOn: $filters.rarePlusOnly) {
                        Label("> Rare", systemImage: "star.circle")
                    }
                }
                if config.showHideOwned {
                    Toggle(isOn: hideOwnedBinding) {
                        Label("Hide owned", systemImage: "eye.slash")
                    }
                }
                if config.showOwnedOnly {
                    Toggle(isOn: ownedOnlyBinding) {
                        Label("Owned only", systemImage: "checkmark.circle")
                    }
                }
                if config.showShowDuplicates {
                    Toggle(isOn: $filters.showDuplicates) {
                        Label("Show duplicates", systemImage: "square.stack.3d.up.badge.a")
                    }
                }
            }
        }
        } // end if !isAllBrands && showBrandFilters

        if config.showSealedProductTypeFilter && (!isAllBrands && config.showBrandFilters) == false {
            Section("Filters") {
                filterMenu(title: "Product type", summary: selectionSummary(for: filters.productTypes), systemImage: "shippingbox") {
                    ForEach(productTypeFilterOptions) { option in
                        Toggle(option.title, isOn: stringBinding(for: option.id, keyPath: \.productTypes))
                    }
                }
            }
        }

        if config.showGridOptions {
            Section("Grid options") {
                BrowseGridOptionsMenuContent(
                    gridOptions: gridOptions,
                    nameToggleTitle: config.gridNameToggleTitle,
                    showCardIDToggle: config.showGridCardIDToggle,
                    showColumns: config.showGridColumns,
                    showOwnedToggle: config.showGridOwnedToggle
                )
            }
        }
    }

    @ViewBuilder
    private func filterMenu<Content: View>(
        title: String,
        summary: String?,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            if let systemImage {
                Label(menuTitle(title, summary: summary), systemImage: systemImage)
            } else {
                Text(menuTitle(title, summary: summary))
            }
        }
        .menuActionDismissBehavior(.disabled)
        .menuOrder(.fixed)
    }

    private func cardTypeBinding(for type: BrowseCardTypeFilter) -> Binding<Bool> {
        Binding(
            get: { filters.cardTypes.contains(type) },
            set: { isOn in
                if isOn { filters.cardTypes.insert(type) }
                else { filters.cardTypes.remove(type) }
            }
        )
    }

    private func legalityBinding(for legality: BrowseCardLegalityFilter) -> Binding<Bool> {
        Binding(
            get: { filters.legalities.contains(legality) },
            set: { isOn in
                if isOn { filters.legalities.insert(legality) }
                else { filters.legalities.remove(legality) }
            }
        )
    }

    private func stringBinding(for value: String, keyPath: WritableKeyPath<BrowseCardGridFilters, Set<String>>) -> Binding<Bool> {
        Binding(
            get: { filters[keyPath: keyPath].contains(value) },
            set: { isOn in
                if isOn { filters[keyPath: keyPath].insert(value) }
                else { filters[keyPath: keyPath].remove(value) }
            }
        )
    }

    private var hideOwnedBinding: Binding<Bool> {
        Binding(
            get: { filters.hideOwned },
            set: { isOn in
                filters.hideOwned = isOn
                if isOn { filters.ownedOnly = false }
            }
        )
    }

    private var ownedOnlyBinding: Binding<Bool> {
        Binding(
            get: { filters.ownedOnly },
            set: { isOn in
                filters.ownedOnly = isOn
                if isOn { filters.hideOwned = false }
            }
        )
    }

    private func intBinding(for value: Int, keyPath: WritableKeyPath<BrowseCardGridFilters, Set<Int>>) -> Binding<Bool> {
        Binding(
            get: { filters[keyPath: keyPath].contains(value) },
            set: { isOn in
                if isOn { filters[keyPath: keyPath].insert(value) }
                else { filters[keyPath: keyPath].remove(value) }
            }
        )
    }

    private func abilityPresenceBinding(for value: BrowseCardAbilityPresenceFilter) -> Binding<Bool> {
        Binding(
            get: { filters.abilityPresence == value },
            set: { isOn in
                filters.abilityPresence = isOn ? value : nil
            }
        )
    }

    private func gridOptionBinding<T>(_ keyPath: WritableKeyPath<BrowseGridOptions, T>) -> Binding<T> {
        if let gridOptions {
            return Binding(
                get: { gridOptions.wrappedValue[keyPath: keyPath] },
                set: { newValue in
                    var updated = gridOptions.wrappedValue
                    updated[keyPath: keyPath] = newValue
                    gridOptions.wrappedValue = updated
                }
            )
        }
        return Binding(
            get: { services.browseGridOptions.options[keyPath: keyPath] },
            set: { newValue in
                var updated = services.browseGridOptions.options
                updated[keyPath: keyPath] = newValue
                services.browseGridOptions.options = updated
            }
        )
    }

    private func menuTitle(_ title: String, summary: String?) -> String {
        guard let summary, !summary.isEmpty else { return title }
        return "\(title) (\(summary))"
    }

    private func selectionSummary<T>(for values: Set<T>) -> String? {
        guard !values.isEmpty else { return nil }
        return values.count == 1 ? "1 selected" : "\(values.count) selected"
    }

    private func combinedSelectionSummary(_ groups: (String, Int)...) -> String? {
        let active = groups.filter { $0.1 > 0 }
        guard !active.isEmpty else { return nil }
        return active.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
    }
}

struct BrowseGridOptionsMenuContent: View {
    @Environment(AppServices.self) private var services

    /// When nil, falls back to `services.browseGridOptions` (browse behaviour). Pass a binding to use separate grid options.
    var gridOptions: Binding<BrowseGridOptions>? = nil
    var nameToggleTitle: String = "Show card name"
    var showCardIDToggle: Bool = true
    var showColumns: Bool = true
    var showOwnedToggle: Bool = true
    var ownedToggleTitle: String = "Owned"
    var ownedToggleSystemImage: String = "checkmark.circle"

    var body: some View {
        Toggle(isOn: gridOptionBinding(\.showCardName)) {
            Label(nameToggleTitle, systemImage: "textformat")
        }
        Toggle(isOn: gridOptionBinding(\.showSetName)) {
            Label("Show set name", systemImage: "doc.text")
        }
        if showCardIDToggle {
            Toggle(isOn: gridOptionBinding(\.showSetID)) {
                Label("Show card ID", systemImage: "number.circle")
            }
        }
        if showOwnedToggle, gridOptions != nil {
            Toggle(isOn: gridOptionBinding(\.showOwned)) {
                Label(ownedToggleTitle, systemImage: ownedToggleSystemImage)
            }
        }
        Toggle(isOn: gridOptionBinding(\.showPricing)) {
            Label("Show pricing", systemImage: "dollarsign.circle")
        }
        if showColumns {
            Stepper(value: gridOptionBinding(\.columnCount), in: 1...4) {
                let count = gridOptions?.wrappedValue.columnCount ?? services.browseGridOptions.options.columnCount
                Label("Columns: \(count)", systemImage: "square.grid.3x2")
            }
            .tint(.primary)
        }
    }

    private func gridOptionBinding<T>(_ keyPath: WritableKeyPath<BrowseGridOptions, T>) -> Binding<T> {
        if let gridOptions {
            return Binding(
                get: { gridOptions.wrappedValue[keyPath: keyPath] },
                set: { newValue in
                    var updated = gridOptions.wrappedValue
                    updated[keyPath: keyPath] = newValue
                    gridOptions.wrappedValue = updated
                }
            )
        }
        return Binding(
            get: { services.browseGridOptions.options[keyPath: keyPath] },
            set: { newValue in
                var updated = services.browseGridOptions.options
                updated[keyPath: keyPath] = newValue
                services.browseGridOptions.options = updated
            }
        )
    }
}

func cardEnergyOptions(_ cards: [Card]) -> [String] {
    var values = Set<String>()
    for card in cards {
        if let energyType = card.energyType?.trimmingCharacters(in: .whitespacesAndNewlines), !energyType.isEmpty {
            values.insert(energyType)
        }
        for type in card.elementTypes ?? [] {
            let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                values.insert(trimmed)
            }
        }
    }
    return values.sorted()
}

func cardRarityOptions(_ cards: [Card]) -> [String] {
    Set(cards.compactMap { $0.rarity?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).sorted()
}

func cardTrainerTypeOptions(_ cards: [Card]) -> [String] {
    Set(cards.compactMap { $0.trainerType?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).sorted()
}

func browseFilterEnergyOptions(_ cards: [BrowseFilterCard]) -> [String] {
    var values = Set<String>()
    for card in cards {
        if let energyType = card.energyType?.trimmingCharacters(in: .whitespacesAndNewlines), !energyType.isEmpty {
            values.insert(energyType)
        }
        for type in card.elementTypes ?? [] {
            let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                values.insert(trimmed)
            }
        }
    }
    return values.sorted()
}

func browseFilterRarityOptions(_ cards: [BrowseFilterCard]) -> [String] {
    Set(cards.compactMap { $0.rarity?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).sorted()
}

func browseFilterTrainerTypeOptions(_ cards: [BrowseFilterCard]) -> [String] {
    Set(cards.compactMap { $0.trainerType?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).sorted()
}

private func browseMarketPriceUSD(for entry: CardPricingEntry?) -> Double? {
    guard let entry else { return nil }
    if let scrydex = entry.scrydex, !scrydex.isEmpty {
        return scrydex.values.compactMap { $0.rawMarketEstimateUSD() }.filter { $0 > 0 }.min()
    }
    return entry.tcgplayerMarketEstimateUSD()
}

private func browseMarketPriceLine(for entry: CardPricingEntry, currency: PriceDisplayCurrency, usdToGbp: Double) -> String? {
    let range: (min: Double, max: Double)?
    if let scrydex = entry.scrydex, !scrydex.isEmpty {
        let values = scrydex.values.compactMap { $0.rawMarketEstimateUSD() }.filter { $0 > 0 }
        if let min = values.min(), let max = values.max() {
            range = (min, max)
        } else {
            range = nil
        }
    } else if let usd = entry.tcgplayerMarketEstimateUSD() {
        range = (usd, usd)
    } else {
        range = nil
    }
    guard let range else { return nil }
    if abs(range.max - range.min) < 0.005 {
        return currency.format(amountUSD: range.min, usdToGbp: usdToGbp)
    }
    let low = currency.format(amountUSD: range.min, usdToGbp: usdToGbp)
    let high = currency.format(amountUSD: range.max, usdToGbp: usdToGbp)
    return "\(low) - \(high)"
}

private func isCommonOrUncommon(_ rarity: String?) -> Bool {
    let normalized = rarity?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    let lettersOnly = String(normalized.unicodeScalars.filter(CharacterSet.letters.contains))
    return normalized.contains("common")
        || lettersOnly == "rare"
        || normalized == "rare holo"
}

private func cardMatchesPokemonSubtypeFilters(_ card: Card, precomputedSelectedTokens: Set<String>) -> Bool {
    guard !precomputedSelectedTokens.isEmpty else { return true }

    let cardSubtypeTokens = Set(([card.stage, card.subtype] + (card.subtypes ?? []))
        .map(normalizedBrowseSearchText)
        .filter { !$0.isEmpty })
    guard !cardSubtypeTokens.isEmpty else { return false }

    func compact(_ token: String) -> String {
        token.replacingOccurrences(of: " ", with: "")
    }

    return precomputedSelectedTokens.contains { selected in
        let compactSelected = compact(selected)
        return cardSubtypeTokens.contains { token in
            token == selected
                || token.contains(selected)
                || compact(token) == compactSelected
                || compact(token).contains(compactSelected)
        }
    }
}

func filterBrowseCards(
    _ cards: [Card],
    query: String,
    filters: BrowseCardGridFilters,
    ownedCardIDs: Set<String>,
    brand: TCGBrand,
    sets: [TCGSet] = [],
    priceByCardID: [String: Double] = [:]
) -> [Card] {
    let normalizedQuery = normalizedBrowseSearchText(query)
    let setReleaseDateByCode = firstValueMap(sets, key: \.setCode) { $0.releaseDate ?? "" }
    let setSeriesNameByCode = seriesNameBySetCode(from: sets)
    let normalizedWeaknessTypes = normalizedBrowseFilterTokens(filters.weaknessTypes)
    let normalizedResistanceTypes = normalizedBrowseFilterTokens(filters.resistanceTypes)
    let normalizedSubtypeTokens = Set(filters.pokemonSubtypes.map(normalizedBrowseSearchText).filter { !$0.isEmpty })

    // Pre-normalize searchable card fields once per card rather than once per comparison.
    struct NormalizedCardFields {
        let name: String
        let number: String
        let setCode: String
        let subtype: String
        let subtypes: [String]
    }
    let normalizedFields: [String: NormalizedCardFields] = normalizedQuery.isEmpty ? [:] : {
        var dict = [String: NormalizedCardFields](minimumCapacity: cards.count)
        for card in cards {
            dict[card.masterCardId] = NormalizedCardFields(
                name: normalizedBrowseSearchText(card.cardName),
                number: normalizedBrowseSearchText(card.cardNumber),
                setCode: normalizedBrowseSearchText(card.setCode),
                subtype: normalizedBrowseSearchText(card.subtype),
                subtypes: (card.subtypes ?? []).map(normalizedBrowseSearchText)
            )
        }
        return dict
    }()

    let filtered = cards.filter { card in
        let matchesQuery: Bool
        if normalizedQuery.isEmpty {
            matchesQuery = true
        } else if let f = normalizedFields[card.masterCardId] {
            matchesQuery = f.name.contains(normalizedQuery)
                || f.number.contains(normalizedQuery)
                || f.setCode.contains(normalizedQuery)
                || f.subtype.contains(normalizedQuery)
                || f.subtypes.contains { $0.contains(normalizedQuery) }
        } else {
            matchesQuery = false
        }
        guard matchesQuery else { return false }

        if cardMatchesSeriesNamesFilter(
            setCode: card.setCode,
            selectedSeriesNames: filters.seriesNames,
            seriesNameBySetCode: setSeriesNameByCode
        ) == false {
            return false
        }
        if brand == .pokemon,
           filters.cardTypes.isEmpty == false,
           filters.cardTypes.contains(resolvedBrowseCardType(for: card, brand: brand)) == false {
            return false
        }
        if filters.rarePlusOnly && isCommonOrUncommon(card.rarity) {
            return false
        }
        if filters.hideOwned && ownedCardIDs.contains(card.masterCardId) {
            return false
        }
        if filters.ownedOnly && !ownedCardIDs.contains(card.masterCardId) {
            return false
        }
        if brand == .pokemon,
           filters.legalities.isEmpty == false,
           pokemonCardMatchesLegalityFilters(
                selectedLegalityFilters: filters.legalities,
                setCode: card.setCode,
                releaseDate: setReleaseDateByCode[card.setCode],
                category: card.category,
                energyType: card.energyType,
                regulationMark: card.regulationMark,
                cardName: card.cardName
           ) == false {
            return false
        }
        if filters.energyTypes.isEmpty == false {
            var hasMatch = false
            if let e = card.energyType, !e.isEmpty, filters.energyTypes.contains(e.trimmingCharacters(in: .whitespacesAndNewlines)) {
                hasMatch = true
            }
            if !hasMatch, let types = card.elementTypes {
                hasMatch = types.contains { filters.energyTypes.contains($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            }
            if !hasMatch { return false }
        }
        if filters.rarities.isEmpty == false {
            let rarity = card.rarity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if rarity.isEmpty || filters.rarities.contains(rarity) == false {
                return false
            }
        }
        if filters.trainerTypes.isEmpty == false {
            let trainerType = card.trainerType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trainerType.isEmpty || filters.trainerTypes.contains(trainerType) == false {
                return false
            }
        }
        if brand == .pokemon,
           browseTextContainsAnyToken(card.weakness, normalizedTokens: normalizedWeaknessTypes) == false {
            return false
        }
        if brand == .pokemon,
           browseTextContainsAnyToken(card.resistance, normalizedTokens: normalizedResistanceTypes) == false {
            return false
        }
        if brand == .pokemon,
           filters.pokemonSubtypes.isEmpty == false {
            guard resolvedBrowseCardType(for: card, brand: brand) == .pokemon else {
                return false
            }
            guard cardMatchesPokemonSubtypeFilters(card, precomputedSelectedTokens: normalizedSubtypeTokens) else {
                return false
            }
        }
        if let abilityPresence = filters.abilityPresence {
            let hasAbilities = (card.abilities?.isEmpty == false)
            if abilityPresence == .yes, hasAbilities == false { return false }
            if abilityPresence == .no, hasAbilities == true { return false }
        }
        return true
    }

    switch filters.sortBy {
    case .cardName:
        return filtered.sorted { $0.cardName.localizedCaseInsensitiveCompare($1.cardName) == .orderedAscending }
    case .newestSet:
        return sortCardsByReleaseDateNewestFirst(filtered, sets: sets)
    case .cardNumber:
        return filtered.sorted { lhs, rhs in
            if lhs.setCode != rhs.setCode {
                let lhsDate = setReleaseDateByCode[lhs.setCode] ?? ""
                let rhsDate = setReleaseDateByCode[rhs.setCode] ?? ""
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return lhs.setCode.localizedStandardCompare(rhs.setCode) == .orderedAscending
            }
            return lhs.cardNumber.localizedStandardCompare(rhs.cardNumber) == .orderedAscending
        }
    case .random:
        return filtered.shuffled()
    case .price:
        return filtered.sorted { lhs, rhs in
            let lhsPrice = priceByCardID[lhs.masterCardId]
            let rhsPrice = priceByCardID[rhs.masterCardId]
            switch (lhsPrice, rhsPrice) {
            case let (l?, r?):
                if l != r { return l > r }
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                break
            }
            if lhs.cardName != rhs.cardName {
                return lhs.cardName.localizedCaseInsensitiveCompare(rhs.cardName) == .orderedAscending
            }
            if lhs.setCode != rhs.setCode {
                let lhsDate = setReleaseDateByCode[lhs.setCode] ?? ""
                let rhsDate = setReleaseDateByCode[rhs.setCode] ?? ""
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return lhs.setCode.localizedStandardCompare(rhs.setCode) == .orderedAscending
            }
            return lhs.cardNumber.localizedStandardCompare(rhs.cardNumber) == .orderedAscending
        }
    case .acquiredDateNewest:
        return filtered
    }
}

private func normalizedBrowseSearchText(_ value: String?) -> String {
    guard let value else { return "" }
    let scalars = value.lowercased().unicodeScalars.compactMap { scalar -> Character? in
        if CharacterSet.alphanumerics.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar) {
            return Character(scalar)
        }
        return nil
    }
    return String(scalars)
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
}

private func normalizedBrowseFilterTokens(_ values: Set<String>) -> [String] {
    values
        .map(normalizedBrowseSearchText)
        .filter { !$0.isEmpty }
}

private func browseTextContainsAnyToken(_ value: String?, normalizedTokens: [String]) -> Bool {
    guard normalizedTokens.isEmpty == false else { return true }
    let normalizedValue = normalizedBrowseSearchText(value)
    guard normalizedValue.isEmpty == false else { return false }
    return normalizedTokens.contains { normalizedValue.contains($0) }
}

private func resolvedBrowseCardType(for card: Card, brand: TCGBrand) -> BrowseCardTypeFilter {
    let category = card.category?.lowercased() ?? ""
    if category.contains("trainer") || card.trainerType != nil {
        return .trainer
    }
    if category.contains("energy") || card.energyType != nil {
        return .energy
    }
    return .pokemon
}

private func pokemonCardMatchesLegalityFilters(
    selectedLegalityFilters: Set<BrowseCardLegalityFilter>,
    setCode: String,
    releaseDate: String?,
    category: String?,
    energyType: String?,
    regulationMark: String?,
    cardName: String
) -> Bool {
    selectedLegalityFilters.contains { legality in
        pokemonCardIsLegalInDeckFormat(
            legality.deckFormat,
            setCode: setCode,
            releaseDate: releaseDate,
            category: category,
            energyType: energyType,
            regulationMark: regulationMark,
            cardName: cardName
        )
    }
}

private func pokemonCardIsLegalInDeckFormat(
    _ format: DeckFormat,
    setCode: String,
    releaseDate: String?,
    category: String?,
    energyType: String?,
    regulationMark: String?,
    cardName: String
) -> Bool {
    if let legalSets = format.legalSetKeys, legalSets.contains(setCode) == false {
        return false
    }
    if format == .pokemonStandard,
       pokemonSetIsTournamentLegal(releaseDate: releaseDate) == false {
        return false
    }
    if let legalMarks = format.legalRegulationMarks {
        let trimmedMark = regulationMark?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedMark.isEmpty {
            if pokemonCardIsBasicEnergy(category: category, energyType: energyType) == false {
                return false
            }
        } else if legalMarks.contains(trimmedMark) == false {
            return false
        }
    }
    if format.isBanned(cardName: cardName) {
        return false
    }
    return true
}

private func pokemonCardIsBasicEnergy(category: String?, energyType: String?) -> Bool {
    guard category == "Energy" else { return false }
    return energyType?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .caseInsensitiveCompare("Basic") == .orderedSame
}

private func pokemonSetIsTournamentLegal(releaseDate: String?, now: Date = Date()) -> Bool {
    guard let releaseDate, releaseDate.isEmpty == false else { return true }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    guard let release = formatter.date(from: releaseDate) else { return true }
    guard let legalDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: 14, to: release) else {
        return true
    }
    return legalDate <= now
}

#Preview {
    NavigationStack {
        BrowseView(
            collectionItems: [],
            filters: .constant(BrowseCardGridFilters()),
            inlineDetailFilters: .constant(BrowseCardGridFilters()),
            gridOptions: .constant(BrowseGridOptions()),
            filterResultCount: .constant(0),
            filterEnergyOptions: .constant([]),
            filterRarityOptions: .constant([]),
            filterTrainerTypeOptions: .constant([]),
            inlineDetailFilterResultCount: .constant(0),
            inlineDetailFilterEnergyOptions: .constant([]),
            inlineDetailFilterRarityOptions: .constant([]),
            inlineDetailFilterTrainerTypeOptions: .constant([]),
            selectedTab: .constant(.cards),
            inlineDetailRoute: .constant(nil),
            isMultiSelectActive: .constant(false),
            multiSelectedCardIDs: .constant([]),
            query: .constant("")
        )
    }
        .environment(AppServices())
        .environmentObject(ChromeScrollCoordinator())
}
