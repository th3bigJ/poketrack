import SwiftUI
import SwiftData

// MARK: - Card group

private enum DeckCardGroup: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case pokemon  = "Pokémon"
    case trainer  = "Trainers"
    case energy   = "Energy"

    func matches(_ card: DeckCard) -> Bool {
        switch self {
        case .pokemon: return card.category == .pokemon
        case .trainer: return card.category == .trainer
        case .energy:  return card.category == .energy
        }
    }

    var pickerFilter: BrowseCardTypeFilter {
        switch self {
        case .pokemon: return .pokemon
        case .trainer: return .trainer
        case .energy:  return .energy
        }
    }
}

private extension DeckCard {
    enum CardCategory { case pokemon, trainer, energy }

    /// Maps a deck line into the three on-screen sections. Must align with TCG `Card.category`, not only evolution flags (Stage 1/2 Pokémon are still Pokémon).
    var category: CardCategory {
        if isEnergyCard { return .energy }

        if let raw = catalogCategory?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let c = raw.lowercased()
            if c.contains("energy") { return .energy }
            if c.contains("trainer") { return .trainer }
            if c.contains("pokémon") || c.contains("pokemon") { return .pokemon }
        }

        // Rows saved before `catalogCategory` existed: infer from stored flags.
        if trainerType != nil { return .trainer }
        if isBasicPokemon || isRuleBox || isRadiant { return .pokemon }

        // Previously Stage 1/2 Pokémon (etc.) fell through to `.other` and disappeared from every section while still counting toward the deck total.
        return .pokemon
    }
}

/// Full deck swipe order for ``CardBrowseDetailView`` paging (matches Pokémon → Trainers → Energy on screen).
private struct DeckDetailBrowseSession: Identifiable {
    let id = UUID()
    let cards: [Card]
    let startIndex: Int
}

private struct EnergySummaryChip: Identifiable {
    let id: String
    let label: String
    let count: Int
    /// When set, a type-color dot is shown (basic energy by type).
    let circleType: String?
}

// MARK: - Main view

struct DeckDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Bindable var deck: Deck
    @Query private var collectionItems: [CollectionItem]

    @State private var isEditing = false
    @State private var pickerGroup: DeckCardGroup? = nil
    @State private var browseDetailSession: DeckDetailBrowseSession?
    @State private var deckValue: Double? = nil
    @State private var missingValue: Double? = nil
    @State private var isLoadingValue = false
    @State private var isSummaryExpanded = false

    /// Loose + graded copies per catalog `cardID`, scoped to this deck’s TCG brand (what can “cover” deck slots).
    private func playableOwnedQuantityByCardID() -> [String: Int] {
        var counts: [String: Int] = [:]
        let brand = deck.tcgBrand
        for item in collectionItems {
            guard TCGBrand.inferredFromMasterCardId(item.cardID) == brand else { continue }
            guard let kind = ProductKind(rawValue: item.itemKind),
                  kind == .singleCard || kind == .gradedItem else { continue }
            counts[item.cardID, default: 0] += max(0, item.quantity)
        }
        return counts
    }

    /// Per `DeckCard` row: copies still missing from the collection to satisfy that line (same pool allocation as deck value).
    private var copiesNeededByDeckCard: [PersistentIdentifier: Int] {
        var remaining = playableOwnedQuantityByCardID()
        var result: [PersistentIdentifier: Int] = [:]
        for deckCard in deck.cardList {
            let needed = deckCard.quantity
            let pool = remaining[deckCard.cardID] ?? 0
            let covered = min(pool, needed)
            remaining[deckCard.cardID] = pool - covered
            result[deckCard.persistentModelID] = needed - covered
        }
        return result
    }

    private var pokemonCards: [DeckCard] { deck.cardList.filter { $0.category == .pokemon }.sorted { $0.cardName < $1.cardName } }
    private var trainerCards: [DeckCard] { deck.cardList.filter { $0.category == .trainer }.sorted { $0.cardName < $1.cardName } }
    private var energyCards:  [DeckCard] { deck.cardList.filter { $0.category == .energy }.sorted  { $0.cardName < $1.cardName } }

    private var pokemonCount: Int { pokemonCards.reduce(0) { $0 + $1.quantity } }
    private var trainerCount: Int { trainerCards.reduce(0) { $0 + $1.quantity } }
    private var energyCount:  Int { energyCards.reduce(0)  { $0 + $1.quantity } }

    /// Same order as the decklist sections (for horizontal paging in the detail sheet).
    private var orderedDeckRowsForSwipe: [DeckCard] {
        pokemonCards + trainerCards + energyCards
    }

    private var validationColor: Color {
        if deck.isValid { return .green }
        return deck.totalCardCount > deck.deckFormat.deckSize ? .red : .orange
    }

    /// Types / stages / trainer & energy breakdowns only apply to Pokémon TCG in this screen.
    private var hasExpandableSummaryDetail: Bool {
        deck.tcgBrand == .pokemon && !deck.cardList.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                summarySection
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                Divider().padding(.horizontal, 16)

                cardGroupSection(group: .pokemon, cards: pokemonCards)
                cardGroupSection(group: .trainer, cards: trainerCards)
                cardGroupSection(group: .energy,  cards: energyCards)

                Spacer(minLength: 40)
            }
        }
        .navigationTitle(isEditing ? "" : deck.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if isEditing {
                    TextField("Deck name", text: $deck.title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 220)
                } else {
                    Text(deck.title).font(.headline)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(isEditing ? "Done" : "Edit") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isEditing.toggle()
                    }
                }
                .fontWeight(isEditing ? .semibold : .regular)
            }
        }
        .sheet(item: $pickerGroup) { group in
            DeckCardPickerView(deck: deck, initialCategoryFilter: group.pickerFilter)
        }
        .sheet(item: $browseDetailSession) { session in
            CardBrowseDetailView(
                cards: session.cards,
                startIndex: session.startIndex,
                addToDeckAction: nil,
                showsHeaderChromeActions: false,
                showsWishlistWhenChromeHidden: true
            )
            .environment(services)
        }
        .task(id: deck.cardList.map(\.cardID).sorted().joined()) {
            await refreshValue()
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        VStack(spacing: 16) {
            // Always visible: totals + Pokémon / Trainer / Energy counts
            VStack(spacing: 6) {
                HStack {
                    Text("\(deck.totalCardCount) / \(deck.deckFormat.deckSize) cards")
                        .font(.title2.weight(.bold))
                    Spacer()
                    Circle().fill(validationColor).frame(width: 10, height: 10)
                    Text(deck.isValid ? "Valid" : (deck.validationIssues.first ?? "Invalid"))
                        .font(.caption)
                        .foregroundStyle(validationColor)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(Color(uiColor: .systemFill)).frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(validationColor)
                            .frame(width: geo.size.width * min(Double(deck.totalCardCount) / Double(deck.deckFormat.deckSize), 1.0), height: 8)
                    }
                }
                .frame(height: 8)

                HStack(spacing: 0) {
                    summaryPill(label: "Pokémon", count: pokemonCount, color: .blue)
                    Spacer()
                    summaryPill(label: "Trainers", count: trainerCount, color: .purple)
                    Spacer()
                    summaryPill(label: "Energy", count: energyCount, color: .orange)
                }
                .padding(.top, 4)
            }

            if hasExpandableSummaryDetail {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        isSummaryExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Text(isSummaryExpanded ? "Hide breakdown" : "Show breakdown")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.secondary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.secondary)
                            .rotationEffect(.degrees(isSummaryExpanded ? 180 : 0))
                            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: isSummaryExpanded)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSummaryExpanded ? "Hide deck breakdown" : "Show deck breakdown")
            }

            if isSummaryExpanded && hasExpandableSummaryDetail {
                VStack(alignment: .leading, spacing: 18) {
                    Divider()
                    typeBreakdown
                    subtypeBreakdown
                    if !trainerCards.isEmpty {
                        trainerBreakdown
                    }
                    if !energyCards.isEmpty {
                        energyBreakdown
                    }
                    Divider()
                    valueRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !hasExpandableSummaryDetail {
                Divider()
                valueRow
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func summaryPill(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.title3.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: Type breakdown

    @ViewBuilder
    private var typeBreakdown: some View {
        let types = typeCounts()
        if !types.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Types").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                FlowRow(spacing: 8) {
                    ForEach(types, id: \.type) { row in
                        HStack(spacing: 4) {
                            typeCircle(row.type)
                            Text(row.type).font(.caption2).foregroundStyle(.primary)
                            Text("×\(row.count)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                    }
                }
            }
        }
    }

    private func typeCounts() -> [(type: String, count: Int)] {
        var counts: [String: Int] = [:]
        for card in pokemonCards {
            for type in (card.elementTypes ?? []) where type != "-" {
                counts[type, default: 0] += card.quantity
            }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }

    // MARK: Subtype breakdown

    @ViewBuilder
    private var subtypeBreakdown: some View {
        let subtypes = subtypeCounts()
        if !subtypes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pokémon Stages").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                FlowRow(spacing: 8) {
                    ForEach(subtypes, id: \.subtype) { row in
                        HStack(spacing: 4) {
                            Text(row.subtype).font(.caption2)
                            Text("×\(row.count)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                    }
                }
            }
        }
    }

    private func subtypeCounts() -> [(subtype: String, count: Int)] {
        // Extract meaningful stage tokens from the comma-separated subtype string stored on DeckCard
        // e.g. "Stage 2, ex" → ["Stage 2", "ex"]
        let relevantTokens: Set<String> = ["Basic", "Stage 1", "Stage 2", "MEGA", "ex", "GX", "V", "VMAX", "VSTAR", "Radiant", "BREAK"]
        var counts: [String: Int] = [:]
        for card in pokemonCards {
            let tokens = (card.subtypeTokens).filter { relevantTokens.contains($0) }
            for token in tokens {
                counts[token, default: 0] += card.quantity
            }
        }
        let order = ["Basic", "Stage 1", "Stage 2", "MEGA", "BREAK", "ex", "GX", "V", "VMAX", "VSTAR", "Radiant"]
        return counts.map { ($0.key, $0.value) }.sorted {
            let li = order.firstIndex(of: $0.subtype) ?? 99
            let ri = order.firstIndex(of: $1.subtype) ?? 99
            return li < ri
        }
    }

    // MARK: Trainer breakdown

    @ViewBuilder
    private var trainerBreakdown: some View {
        let types = trainerTypeCounts()
        if !types.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Trainer Types").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                FlowRow(spacing: 8) {
                    ForEach(types, id: \.type) { row in
                        HStack(spacing: 4) {
                            Text(row.type).font(.caption2)
                            Text("×\(row.count)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                    }
                }
            }
        }
    }

    private func trainerTypeCounts() -> [(type: String, count: Int)] {
        var counts: [String: Int] = [:]
        for card in trainerCards {
            let key = card.trainerType ?? "Other"
            counts[key, default: 0] += card.quantity
        }
        let order = ["Supporter", "Item", "Stadium", "Pokémon Tool", "Other"]
        return counts.map { ($0.key, $0.value) }.sorted {
            let li = order.firstIndex(of: $0.type) ?? 99
            let ri = order.firstIndex(of: $1.type) ?? 99
            return li < ri
        }
    }

    // MARK: Energy breakdown

    @ViewBuilder
    private var energyBreakdown: some View {
        let chips = energySummaryChips()
        if !chips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Energy").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                FlowRow(spacing: 8) {
                    ForEach(chips) { chip in
                        HStack(spacing: 4) {
                            if let circleType = chip.circleType {
                                typeCircle(circleType)
                            }
                            Text(chip.label).font(.caption2).foregroundStyle(.primary)
                            Text("×\(chip.count)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                    }
                }
            }
        }
    }

    private func energySummaryChips() -> [EnergySummaryChip] {
        var basicByType: [String: Int] = [:]
        var specialCount = 0
        for card in energyCards {
            if card.isBasicEnergy {
                let t = card.elementTypes?.first(where: { !$0.isEmpty && $0 != "-" }) ?? "Colorless"
                basicByType[t, default: 0] += card.quantity
            } else {
                specialCount += card.quantity
            }
        }
        let typeOrder = ["Grass", "Fire", "Water", "Lightning", "Psychic", "Fighting", "Darkness", "Metal", "Dragon", "Fairy", "Colorless"]
        var chips: [EnergySummaryChip] = []
        for t in typeOrder {
            if let c = basicByType[t], c > 0 {
                chips.append(EnergySummaryChip(id: t, label: t, count: c, circleType: t))
            }
        }
        for t in basicByType.keys.filter({ !typeOrder.contains($0) }).sorted() {
            if let c = basicByType[t], c > 0 {
                chips.append(EnergySummaryChip(id: t, label: t, count: c, circleType: t))
            }
        }
        if specialCount > 0 {
            chips.append(EnergySummaryChip(id: "special", label: "Special", count: specialCount, circleType: nil))
        }
        return chips
    }

    // MARK: Value row

    private var valueRow: some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                if isLoadingValue {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Text(deckValue.map { formatPrice($0) } ?? "—")
                        .font(.title3.weight(.bold))
                    Text("Deck value").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 36)

            VStack(spacing: 2) {
                if isLoadingValue {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Text(missingValue.map { formatPrice($0) } ?? "—")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(missingValue ?? 0 > 0 ? .orange : .primary)
                    Text("To complete").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func formatPrice(_ value: Double) -> String {
        services.priceDisplay.currency.format(amountUSD: value, usdToGbp: services.pricing.usdToGbp)
    }

    private func refreshValue() async {
        guard !deck.cardList.isEmpty else {
            deckValue = 0; missingValue = 0; return
        }
        isLoadingValue = true
        var ownedUSD = 0.0
        var missingUSD = 0.0
        /// Remaining collection copies we can allocate to deck lines (handles “own 1 of 4”).
        var remainingOwnedCopies = playableOwnedQuantityByCardID()

        for deckCard in deck.cardList {
            guard let card = await services.cardData.loadCard(masterCardId: deckCard.cardID) else { continue }
            let entry = await services.pricing.pricing(for: card)
            let unitUSD = bestPrice(entry) ?? 0.0
            let needed = deckCard.quantity
            let pool = remainingOwnedCopies[deckCard.cardID] ?? 0
            let covered = min(pool, needed)
            remainingOwnedCopies[deckCard.cardID] = pool - covered
            let shortfall = needed - covered
            ownedUSD += unitUSD * Double(covered)
            missingUSD += unitUSD * Double(shortfall)
        }
        await MainActor.run {
            // Full decklist at market estimate; “To complete” is only the gap (missing copies × price).
            deckValue = ownedUSD + missingUSD
            missingValue = missingUSD
            isLoadingValue = false
        }
    }

    private func bestPrice(_ entry: CardPricingEntry?) -> Double? {
        guard let entry else { return nil }
        if let scrydex = entry.scrydex, !scrydex.isEmpty {
            return scrydex.values.compactMap { $0.marketEstimateUSD() }.max()
        }
        return entry.tcgplayerMarketEstimateUSD()
    }

    // MARK: - Card groups

    @ViewBuilder
    private func cardGroupSection(group: DeckCardGroup, cards: [DeckCard]) -> some View {
        let count = cards.reduce(0) { $0 + $1.quantity }
        if !cards.isEmpty || isEditing {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(group.rawValue)
                        .font(.title3.weight(.bold))
                    Text("(\(count))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)

                let columns = [GridItem(.adaptive(minimum: 100), spacing: 10)]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(cards) { deckCard in
                        DeckCardGridCell(
                            deckCard: deckCard,
                            copiesNeededFromCollection: copiesNeededByDeckCard[deckCard.persistentModelID] ?? 0,
                            isEditing: isEditing,
                            maxCopies: deckCard.isBasicEnergy ? 99 : deck.deckFormat.maxCopiesPerCard,
                            onQuantityChange: { updateQuantity(deckCard: deckCard, qty: $0) },
                            onDelete: { modelContext.delete(deckCard) },
                            onViewCardTap: isEditing ? nil : {
                                Task { await openBrowseDetail(for: deckCard) }
                            }
                        )
                    }

                    if isEditing {
                        AddCardCell {
                            pickerGroup = group
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Helpers

    private func updateQuantity(deckCard: DeckCard, qty: Int) {
        if qty <= 0 { modelContext.delete(deckCard) } else { deckCard.quantity = qty }
    }

    private func openBrowseDetail(for deckCard: DeckCard) async {
        let rows = orderedDeckRowsForSwipe
        let indexedPairs: [(Int, Card)] = await withTaskGroup(of: (Int, Card?).self, returning: [(Int, Card)].self) { group in
            for (i, row) in rows.enumerated() {
                group.addTask {
                    let c = await services.cardData.loadCard(masterCardId: row.cardID)
                    return (i, c)
                }
            }
            var pairs: [(Int, Card)] = []
            pairs.reserveCapacity(rows.count)
            for await (i, c) in group {
                if let c { pairs.append((i, c)) }
            }
            return pairs.sorted { $0.0 < $1.0 }
        }
        let loaded = indexedPairs.map(\.1)
        guard let swipeIndex = loaded.firstIndex(where: { $0.masterCardId == deckCard.cardID }) else {
            guard let card = await services.cardData.loadCard(masterCardId: deckCard.cardID) else { return }
            await MainActor.run {
                browseDetailSession = DeckDetailBrowseSession(cards: [card], startIndex: 0)
                HapticManager.impact(.light)
            }
            return
        }
        await MainActor.run {
            browseDetailSession = DeckDetailBrowseSession(cards: loaded, startIndex: swipeIndex)
            HapticManager.impact(.light)
        }
    }

    private func typeCircle(_ type: String) -> some View {
        Circle()
            .fill(pokemonTypeColor(type))
            .frame(width: 10, height: 10)
    }

    private func pokemonTypeColor(_ type: String) -> Color {
        switch type {
        case "Fire":       return .red
        case "Water":      return .blue
        case "Grass":      return .green
        case "Lightning":  return .yellow
        case "Psychic":    return .purple
        case "Fighting":   return .orange
        case "Darkness":   return Color(uiColor: .darkGray)
        case "Metal":      return Color(uiColor: .systemGray)
        case "Dragon":     return .indigo
        case "Fairy":      return .pink
        case "Colorless":  return Color(uiColor: .systemGray3)
        default:           return .secondary
        }
    }
}

// MARK: - DeckCard helper

private extension DeckCard {
    var subtypeTokens: [String] {
        var tokens: [String] = []
        if isBasicPokemon { tokens.append("Basic") }
        if isRuleBox      { tokens.append("ex") }
        if isRadiant      { tokens.append("Radiant") }
        return tokens
    }
}

// MARK: - Deck grid metrics (edit mode columns share the same vertical slots so `Add` aligns with cards)

private enum DeckCardGridLayoutMetrics {
    /// Reserve space for the two-line “N needed / to complete deck” block so rows stay level when some cards need 0 copies.
    static let neededSectionHeight: CGFloat = 40
    /// Matches ``ChromeGlassCircleButton`` outer frame height in the − / + row.
    static let editControlsRowHeight: CGFloat = 48
}

// MARK: - Card grid cell (view + edit)

private struct DeckCardGridCell: View {
    let deckCard: DeckCard
    /// Copies of this deck line still not covered by the collection (after allocating owned playsets across lines).
    let copiesNeededFromCollection: Int
    let isEditing: Bool
    let maxCopies: Int
    let onQuantityChange: (Int) -> Void
    let onDelete: () -> Void
    /// When non-`nil` and not editing, tapping the artwork opens browse detail (view-only sheet).
    var onViewCardTap: (() -> Void)? = nil

    private var cardArtStack: some View {
        ZStack(alignment: .bottom) {
            CachedAsyncImage(
                url: AppConfiguration.imageURL(relativePath: deckCard.imageLowSrc),
                targetSize: CGSize(width: 200, height: 280)
            ) { img in
                img.resizable().scaledToFit()
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(uiColor: .systemGray5))
                    .aspectRatio(5/7, contentMode: .fit)
                    .overlay {
                        Text(deckCard.cardName)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .padding(4)
                            .foregroundStyle(.secondary)
                    }
            }
            .aspectRatio(5/7, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Spacer()
                Text("×\(deckCard.quantity)")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.black.opacity(0.7), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(4)
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let tap = onViewCardTap, !isEditing {
                    Button(action: tap) {
                        cardArtStack
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(deckCard.cardName)")
                    .accessibilityHint("Opens card details")
                } else {
                    cardArtStack
                }
            }

            if isEditing {
                VStack(spacing: 2) {
                    if copiesNeededFromCollection > 0 {
                        Text("\(copiesNeededFromCollection) needed")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.orange)
                        Text("to complete deck")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(height: DeckCardGridLayoutMetrics.neededSectionHeight, alignment: .center)
                .accessibilityElement(children: .combine)
                .accessibilityHidden(copiesNeededFromCollection == 0)
                .accessibilityLabel("\(copiesNeededFromCollection) copies needed from your collection to complete this deck slot")

                HStack(spacing: 16) {
                    ChromeGlassCircleButton(accessibilityLabel: "Remove one copy") {
                        onQuantityChange(deckCard.quantity - 1)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.primary)
                    }

                    ChromeGlassCircleButton(accessibilityLabel: "Add one copy") {
                        onQuantityChange(deckCard.quantity + 1)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(deckCard.quantity >= maxCopies ? Color.secondary : Color.primary)
                    }
                    .disabled(deckCard.quantity >= maxCopies)
                }
                .frame(maxWidth: .infinity)
                .frame(height: DeckCardGridLayoutMetrics.editControlsRowHeight)
            } else if copiesNeededFromCollection > 0 {
                VStack(spacing: 2) {
                    Text("\(copiesNeededFromCollection) needed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.orange)
                    Text("to complete deck")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(copiesNeededFromCollection) copies needed from your collection to complete this deck slot")
            }
        }
        .contextMenu {
            if isEditing {
                Button(role: .destructive, action: onDelete) {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Add card cell

private struct AddCardCell: View {
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onTap) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(uiColor: .systemGray5))
                    .aspectRatio(5/7, contentMode: .fit)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.accentColor)
                            Text("Add")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
            }
            .buttonStyle(.plain)

            // Match ``DeckCardGridCell`` edit layout so the Add tile tops-align with card columns in `LazyVGrid`.
            Color.clear
                .frame(height: DeckCardGridLayoutMetrics.neededSectionHeight)
                .accessibilityHidden(true)

            Color.clear
                .frame(height: DeckCardGridLayoutMetrics.editControlsRowHeight)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Flow row layout

private struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                height += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
