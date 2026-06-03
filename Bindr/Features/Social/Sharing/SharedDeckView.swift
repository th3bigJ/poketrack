import SwiftUI

struct SharedDeckView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    let content: SharedContent

    @State private var cardsByID: [String: Card] = [:]
    @State private var presentedCard: Card?
    @State private var isSummaryExpanded = false

    fileprivate struct SharedCardRow: Identifiable {
        let id: String
        let cardID: String
        let cardName: String
        let variantKey: String
        let quantity: Int
        let notes: String?
        let marketValue: Double?
    }

    private var entries: [SharedCardRow] {
        guard let rootRows = content.payload["cards"] else { return [] }
        guard case .array(let entries) = rootRows else { return [] }

        return entries.compactMap { value in
            guard case .object(let object) = value else { return nil }
            let cardID = object["cardID"]?.stringValue ?? ""
            let variant = object["variantKey"]?.stringValue ?? "normal"
            let name = object["cardName"]?.stringValue ?? ""
            let qty: Int
            if case .some(.number(let rawQty)) = object["quantity"] {
                qty = Int(rawQty)
            } else {
                qty = 1
            }
            let notes = object["notes"]?.stringValue
            let marketValue: Double?
            switch object["market_value_usd"] {
            case .number(let value):
                marketValue = value
            default:
                marketValue = nil
            }
            return SharedCardRow(
                id: "\(cardID)|\(variant)|\(qty)|\(name)",
                cardID: cardID,
                cardName: name,
                variantKey: variant,
                quantity: max(1, qty),
                notes: notes,
                marketValue: marketValue
            )
        }
    }

    private var tcgBrand: TCGBrand {
        if let raw = content.payload["brand"]?.stringValue,
           let brand = TCGBrand(rawValue: raw) {
            return brand
        }
        if let brandRaw = content.brand, let b = TCGBrand(rawValue: brandRaw) {
            return b
        }
        if let firstCardID = entries.first?.cardID {
            return TCGBrand.inferredFromMasterCardId(firstCardID)
        }
        return .pokemon
    }

    private var formatName: String {
        content.payload["format"]?.stringValue ?? "Standard"
    }

    private var isOnePiece: Bool { tcgBrand == .onePiece }

    // Pokémon TCG card lists
    private var pokemonCards: [SharedCardRow] {
        entries.filter { SharedPokemonCategory.category(for: cardsByID[$0.cardID]) == .pokemon }
            .sorted { resolvedName(for: $0) < resolvedName(for: $1) }
    }
    private var trainerCards: [SharedCardRow] {
        entries.filter { SharedPokemonCategory.category(for: cardsByID[$0.cardID]) == .trainer }
            .sorted { resolvedName(for: $0) < resolvedName(for: $1) }
    }
    private var energyCards: [SharedCardRow] {
        entries.filter { SharedPokemonCategory.category(for: cardsByID[$0.cardID]) == .energy }
            .sorted { resolvedName(for: $0) < resolvedName(for: $1) }
    }

    private var pokemonCount: Int { pokemonCards.reduce(0) { $0 + $1.quantity } }
    private var trainerCount: Int { trainerCards.reduce(0) { $0 + $1.quantity } }
    private var energyCount:  Int { energyCards.reduce(0)  { $0 + $1.quantity } }

    // One Piece card lists
    private var opLeaderCards: [SharedCardRow] {
        entries.filter { SharedOPCategory.category(for: cardsByID[$0.cardID]) == .leader }
            .sorted { resolvedName(for: $0) < resolvedName(for: $1) }
    }
    private var opCharacterCards: [SharedCardRow] {
        entries.filter { SharedOPCategory.category(for: cardsByID[$0.cardID]) == .character }
            .sorted { resolvedName(for: $0) < resolvedName(for: $1) }
    }
    private var opEventCards: [SharedCardRow] {
        entries.filter { SharedOPCategory.category(for: cardsByID[$0.cardID]) == .event }
            .sorted { resolvedName(for: $0) < resolvedName(for: $1) }
    }
    private var opStageCards: [SharedCardRow] {
        entries.filter { SharedOPCategory.category(for: cardsByID[$0.cardID]) == .stage }
            .sorted { resolvedName(for: $0) < resolvedName(for: $1) }
    }

    private var opLeaderCount:    Int { opLeaderCards.reduce(0)    { $0 + $1.quantity } }
    private var opCharacterCount: Int { opCharacterCards.reduce(0) { $0 + $1.quantity } }
    private var opEventCount:     Int { opEventCards.reduce(0)     { $0 + $1.quantity } }
    private var opStageCount:     Int { opStageCards.reduce(0)     { $0 + $1.quantity } }

    private var totalCardCount: Int {
        entries.reduce(0) { $0 + $1.quantity }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                summarySection
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                Divider().padding(.horizontal, 16)

                if isOnePiece {
                    cardGroupSection(title: "Leader",      cards: opLeaderCards)
                    cardGroupSection(title: "Characters",  cards: opCharacterCards)
                    cardGroupSection(title: "Events",      cards: opEventCards)
                    cardGroupSection(title: "Stages",      cards: opStageCards)
                } else {
                    cardGroupSection(title: "Pokémon",     cards: pokemonCards)
                    cardGroupSection(title: "Trainers",    cards: trainerCards)
                    cardGroupSection(title: "Energy",      cards: energyCards)
                }

                Spacer(minLength: 40)
            }
        }
        .background(BindrPageBackground().ignoresSafeArea())
        .navigationTitle(content.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadCards()
        }
        .sheet(item: $presentedCard) { card in
            CardDetailSheet(cards: [card], startIndex: 0)
                .environment(services)
        }
    }

    private var summarySection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                HStack {
                    Text("\(totalCardCount) cards")
                        .font(.title2.weight(.bold))
                    Spacer()
                    Text(formatName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(services.theme.accentColor)
                }

                if isOnePiece {
                    HStack(spacing: 0) {
                        summaryPill(label: "Leader",     count: opLeaderCount,    color: .red)
                        Spacer()
                        summaryPill(label: "Characters", count: opCharacterCount, color: .blue)
                        Spacer()
                        summaryPill(label: "Events",     count: opEventCount,     color: .purple)
                        Spacer()
                        summaryPill(label: "Stages",     count: opStageCount,     color: .green)
                    }
                    .padding(.top, 4)
                } else {
                    HStack(spacing: 0) {
                        summaryPill(label: "Pokémon",  count: pokemonCount,  color: .blue)
                        Spacer()
                        summaryPill(label: "Trainers", count: trainerCount,  color: .purple)
                        Spacer()
                        summaryPill(label: "Energy",   count: energyCount,   color: .orange)
                    }
                    .padding(.top, 4)
                }
            }

            if !entries.isEmpty {
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

            if isSummaryExpanded && !entries.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    Divider()
                    if isOnePiece {
                        opCharacterBreakdown
                        opEventBreakdown
                        opStageBreakdown
                    } else {
                        typeBreakdown
                        subtypeBreakdown
                        if !trainerCards.isEmpty { trainerBreakdown }
                        if !energyCards.isEmpty  { energyBreakdown }
                    }
                    if content.includeValue, let marketValueUSD = content.payload["market_value_usd"]?.doubleValue {
                        Divider()
                        valueRow(value: marketValueUSD)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if content.includeValue, let marketValueUSD = content.payload["market_value_usd"]?.doubleValue {
                Divider()
                valueRow(value: marketValueUSD)
            }
        }
        .padding(16)
        .glassCardStyle(cornerRadius: 16)
    }

    private func summaryPill(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.title3.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Pokémon Breakdown

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
        for row in pokemonCards {
            if let card = cardsByID[row.cardID] {
                for type in (card.elementTypes ?? []) where type != "-" {
                    counts[type, default: 0] += row.quantity
                }
            }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }

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
        let relevantTokens: Set<String> = ["Basic", "Stage 1", "Stage 2", "MEGA", "ex", "GX", "V", "VMAX", "VSTAR", "Radiant", "BREAK"]
        var counts: [String: Int] = [:]
        for row in pokemonCards {
            let card = cardsByID[row.cardID]
            let tokens = subtypeTokens(for: card).filter { relevantTokens.contains($0) }
            for token in tokens {
                counts[token, default: 0] += row.quantity
            }
        }
        let order = ["Basic", "Stage 1", "Stage 2", "MEGA", "BREAK", "ex", "GX", "V", "VMAX", "VSTAR", "Radiant"]
        return counts.map { ($0.key, $0.value) }.sorted {
            let li = order.firstIndex(of: $0.subtype) ?? 99
            let ri = order.firstIndex(of: $1.subtype) ?? 99
            return li < ri
        }
    }

    private func subtypeTokens(for card: Card?) -> [String] {
        guard let card else { return [] }
        var tokens: [String] = []
        if let csv = card.subtype?.trimmingCharacters(in: .whitespacesAndNewlines), !csv.isEmpty {
            tokens.append(contentsOf: csv.split(separator: ",")
                .map { normalizeSubtypeFragment(String($0)) }
                .filter { !$0.isEmpty })
        }
        if let stage = card.stage?.trimmingCharacters(in: .whitespacesAndNewlines), !stage.isEmpty {
            let normalizedStage = normalizeSubtypeFragment(stage)
            if !normalizedStage.isEmpty, !tokens.contains(normalizedStage) {
                tokens.append(normalizedStage)
            }
        }
        return tokens
    }

    private func normalizeSubtypeFragment(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        switch t.lowercased() {
        case "basic": return "Basic"
        case "stage 1", "stage1": return "Stage 1"
        case "stage 2", "stage2": return "Stage 2"
        case "mega": return "MEGA"
        case "break": return "BREAK"
        case "radiant": return "Radiant"
        default: return t
        }
    }

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
        for row in trainerCards {
            let card = cardsByID[row.cardID]
            let key = card?.trainerType ?? "Other"
            counts[key, default: 0] += row.quantity
        }
        let order = ["Supporter", "Item", "Stadium", "Pokémon Tool", "Other"]
        return counts.map { ($0.key, $0.value) }.sorted {
            let li = order.firstIndex(of: $0.type) ?? 99
            let ri = order.firstIndex(of: $1.type) ?? 99
            return li < ri
        }
    }

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

    private struct EnergySummaryChip: Identifiable {
        let id: String
        let label: String
        let count: Int
        let circleType: String?
    }

    private func energySummaryChips() -> [EnergySummaryChip] {
        var basicByType: [String: Int] = [:]
        var specialCount = 0
        for row in energyCards {
            let card = cardsByID[row.cardID]
            let isBasic = card?.energyType?.lowercased() == "basic"
                       || card?.subtypes?.contains(where: { $0.lowercased() == "basic" }) == true
            if isBasic {
                let t = card?.elementTypes?.first(where: { !$0.isEmpty && $0 != "-" }) ?? "Colorless"
                basicByType[t, default: 0] += row.quantity
            } else {
                specialCount += row.quantity
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

    // MARK: - One Piece Breakdown

    @ViewBuilder
    private var opCharacterBreakdown: some View {
        if !opCharacterCards.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Characters").font(.caption.weight(.semibold)).foregroundStyle(.secondary)

                let avgCost  = averageCost(opCharacterCards)
                let avgPower = averagePower(opCharacterCards)
                let withCounter = opCharacterCards.filter { cardsByID[$0.cardID]?.opCounter != nil }.reduce(0) { $0 + $1.quantity }
                let subtypes = opSubtypeCounts(opCharacterCards)
                let colors   = colorCounts(opCharacterCards)

                HStack(spacing: 16) {
                    if let c = avgCost {
                        VStack(spacing: 1) {
                            Text(String(format: "%.1f", c)).font(.caption.weight(.bold))
                            Text("Avg cost").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if let p = avgPower {
                        VStack(spacing: 1) {
                            Text(String(format: "%.0f", p)).font(.caption.weight(.bold))
                            Text("Avg power").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if withCounter > 0 {
                        VStack(spacing: 1) {
                            Text("\(withCounter)").font(.caption.weight(.bold))
                            Text("With counter").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                if !subtypes.isEmpty {
                    opChips(subtypes)
                }
                if !colors.isEmpty {
                    opChips(colors)
                }
            }
        }
    }

    @ViewBuilder
    private var opEventBreakdown: some View {
        if !opEventCards.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Events").font(.caption.weight(.semibold)).foregroundStyle(.secondary)

                let avgCost  = averageCost(opEventCards)
                let subtypes = opSubtypeCounts(opEventCards)
                let colors   = colorCounts(opEventCards)

                if let c = avgCost {
                    HStack(spacing: 16) {
                        VStack(spacing: 1) {
                            Text(String(format: "%.1f", c)).font(.caption.weight(.bold))
                            Text("Avg cost").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                if !subtypes.isEmpty {
                    opChips(subtypes)
                }
                if !colors.isEmpty {
                    opChips(colors)
                }
            }
        }
    }

    @ViewBuilder
    private var opStageBreakdown: some View {
        if !opStageCards.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Stages").font(.caption.weight(.semibold)).foregroundStyle(.secondary)

                let avgCost  = averageCost(opStageCards)
                let subtypes = opSubtypeCounts(opStageCards)
                let colors   = colorCounts(opStageCards)

                if let c = avgCost {
                    HStack(spacing: 16) {
                        VStack(spacing: 1) {
                            Text(String(format: "%.1f", c)).font(.caption.weight(.bold))
                            Text("Avg cost").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                if !subtypes.isEmpty {
                    opChips(subtypes)
                }
                if !colors.isEmpty {
                    opChips(colors)
                }
            }
        }
    }

    private func opChips(_ items: [(label: String, count: Int)]) -> some View {
        FlowRow(spacing: 8) {
            ForEach(items, id: \.label) { item in
                HStack(spacing: 4) {
                    Text(item.label).font(.caption2).foregroundStyle(.primary)
                    Text("×\(item.count)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
            }
        }
    }

    private func averageCost(_ rows: [SharedCardRow]) -> Double? {
        let totalQty = rows.reduce(0) { $0 + $1.quantity }
        guard totalQty > 0 else { return nil }
        let withCost = rows.filter { cardsByID[$0.cardID]?.opCost != nil }
        guard !withCost.isEmpty else { return nil }
        let sum = withCost.reduce(0.0) { $0 + Double(cardsByID[$1.cardID]!.opCost!) * Double($1.quantity) }
        let qty = withCost.reduce(0) { $0 + $1.quantity }
        return sum / Double(qty)
    }

    private func averagePower(_ rows: [SharedCardRow]) -> Double? {
        let withPower = rows.filter { cardsByID[$0.cardID]?.hp != nil }
        guard !withPower.isEmpty else { return nil }
        let sum = withPower.reduce(0.0) {
            let card = cardsByID[$1.cardID]!
            let power = card.hp ?? 0
            return $0 + Double(power) * Double($1.quantity)
        }
        let qty = withPower.reduce(0) { $0 + $1.quantity }
        return sum / Double(qty)
    }

    private func colorCounts(_ rows: [SharedCardRow]) -> [(label: String, count: Int)] {
        var counts: [String: Int] = [:]
        for row in rows {
            if let card = cardsByID[row.cardID] {
                for color in (card.elementTypes ?? []) where !color.isEmpty && color != "-" {
                    counts[color, default: 0] += row.quantity
                }
            }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }

    private func opSubtypeCounts(_ rows: [SharedCardRow]) -> [(label: String, count: Int)] {
        var counts: [String: Int] = [:]
        for row in rows {
            if let card = cardsByID[row.cardID] {
                let tokens = (card.subtype ?? "")
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                for token in tokens {
                    counts[token, default: 0] += row.quantity
                }
            }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }

    // MARK: - Value Row

    private func valueRow(value: Double) -> some View {
        VStack(spacing: 2) {
            Text(formatPrice(value))
                .font(.title3.weight(.bold))
            Text("Deck value").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Grids

    @ViewBuilder
    private func cardGroupSection(title: String, cards: [SharedCardRow]) -> some View {
        let count = cards.reduce(0) { $0 + $1.quantity }
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title)
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
                    ForEach(cards) { row in
                        let imageURL = cardsByID[row.cardID].map { AppConfiguration.imageURL(relativePath: $0.displayImageSrc) }
                        SharedDeckCardGridCell(row: row, imageURL: imageURL) {
                            if let card = cardsByID[row.cardID] {
                                presentedCard = card
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Helper views & methods

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

    private func resolvedName(for row: SharedCardRow) -> String {
        if !row.cardName.isEmpty {
            return row.cardName
        }
        return cardsByID[row.cardID]?.cardName ?? row.cardID
    }

    private func loadCards() async {
        var resolved: [String: Card] = [:]
        for row in entries {
            guard resolved[row.cardID] == nil else { continue }
            if let card = await services.cardData.loadCard(masterCardId: row.cardID) {
                resolved[row.cardID] = card
            }
        }
        await MainActor.run {
            self.cardsByID = resolved
        }
    }

    private func formatPrice(_ value: Double) -> String {
        services.priceDisplay.currency.format(amountUSD: value, usdToGbp: services.pricing.usdToGbp)
    }
}

// MARK: - Shared Deck Card Grid Cell

struct SharedDeckCardGridCell: View {
    fileprivate let row: SharedDeckView.SharedCardRow
    let imageURL: URL?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottom) {
                CachedAsyncImage(url: imageURL, targetSize: CGSize(width: 200, height: 280)) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(uiColor: .systemGray5))
                        .aspectRatio(5/7, contentMode: .fit)
                        .overlay {
                            Text(row.cardName)
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                                .padding(4)
                                .foregroundStyle(.secondary)
                        }
                }
                .aspectRatio(5/7, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(alignment: .bottom) {
                    Spacer()
                    Text("×\(row.quantity)")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.black.opacity(0.7), in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(4)
            }
        }
        .buttonStyle(.plain)
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

// MARK: - TCG Helper Categories

private enum SharedPokemonCategory {
    case pokemon
    case trainer
    case energy

    static func category(for card: Card?) -> SharedPokemonCategory {
        guard let card else { return .pokemon }
        if let categoryRaw = card.category?.trimmingCharacters(in: .whitespacesAndNewlines), !categoryRaw.isEmpty {
            let c = categoryRaw.lowercased()
            if c.contains("energy") { return .energy }
            if c.contains("trainer") { return .trainer }
            if c.contains("pokémon") || c.contains("pokemon") { return .pokemon }
        }
        if card.trainerType != nil { return .trainer }
        if card.energyType != nil { return .energy }
        return .pokemon
    }
}

private enum SharedOPCategory {
    case leader
    case character
    case event
    case stage

    static func category(for card: Card?) -> SharedOPCategory {
        guard let card else { return .character }
        let c = card.category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if c.contains("leader") { return .leader }
        if c.contains("event")  { return .event }
        if c.contains("stage")  { return .stage }
        return .character
    }
}
