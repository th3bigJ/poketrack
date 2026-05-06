import SwiftUI
import SwiftData

struct BrowseInlineSearchField: View {
    let title: String
    @Binding var text: String
    private let trailingContent: AnyView?
    @Environment(\.colorScheme) private var colorScheme

    init(title: String, text: Binding<String>) {
        self.title = title
        self._text = text
        self.trailingContent = nil
    }

    init<Trailing: View>(
        title: String,
        text: Binding<String>,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self._text = text
        self.trailingContent = AnyView(trailing())
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(title, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty, trailingContent == nil {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            if let trailingContent {
                trailingContent
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .modifier(GlassSearchFieldModifier())
    }
}

// MARK: - Glass search field background

struct GlassSearchFieldModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                content
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
                    )
                    .glassEffect(.regular.tint(nil), in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.12), lineWidth: 1)
                    )
            } else {
                content
                    .background(
                        Capsule(style: .continuous)
                            .fill(.thinMaterial)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.1), lineWidth: 1)
                    )
            }
        }
    }
}

struct BrowseAllSetsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Query private var collectionItems: [CollectionItem]
    @State private var query = ""
    
    // Pricing state
    @State private var setMarketValueUSDByKey: [String: Double] = [:]
    @State private var loadedSetMarketValueKeys: Set<String> = []
    @State private var loadingSetMarketValueKeys: Set<String> = []
    
    // Collected counts
    @State private var uniqueCollectedCountBySetCode: [String: Int] = [:]
    @State private var isFirstAppear = true

    private var filteredSets: [TCGSet] {
        let sets = services.cardData.allSetsSortedByReleaseDateNewestFirst()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sets }
        let q = trimmed.lowercased()
        return sets.filter { set in
            set.name.lowercased().contains(q)
                || set.setCode.lowercased().contains(q)
                || (set.seriesName?.lowercased().contains(q) == true)
        }
    }

    private var groupedSets: [(title: String, sets: [TCGSet])] {
        let grouped = Dictionary(grouping: filteredSets, by: browseSeriesTitle(for:))
        switch services.brandSettings.selectedCatalogBrand {
        case .pokemon:
            return grouped
                .map { (title: $0.key, sets: sortSetsNewestFirst($0.value)) }
                .sorted { lhs, rhs in
                    let lhsOldest = lhs.sets.map(\.releaseDate).compactMap { $0 }.min() ?? ""
                    let rhsOldest = rhs.sets.map(\.releaseDate).compactMap { $0 }.min() ?? ""
                    if lhsOldest != rhsOldest { return lhsOldest > rhsOldest }
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
        case .onePiece:
            return grouped
                .map { (title: $0.key, sets: sortSetsNewestFirst($0.value)) }
                .sorted { lhs, rhs in
                    let li = onePieceSeriesOrderIndex(lhs.title)
                    let ri = onePieceSeriesOrderIndex(rhs.title)
                    if li != ri { return li < ri }
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
        }
    }

    var body: some View {
        Group {
            if filteredSets.isEmpty && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "No sets",
                    systemImage: "rectangle.stack",
                    description: Text("Load your catalog to browse sets.")
                )
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        BrowseInlineSearchField(title: "Search sets", text: $query)
                            .padding(.horizontal)
                            .padding(.top)
                        
                        globalProgressHeader
                        if filteredSets.isEmpty {
                            ContentUnavailableView(
                                "No matching sets",
                                systemImage: "magnifyingglass",
                                description: Text("Try a different set name or code.")
                            )
                            .padding(.horizontal)
                            .padding(.bottom)
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
                                    .padding(.horizontal)
                                    .padding(.top, 10)
                                    LazyVStack(spacing: 0) {
                                        ForEach(group.sets) { set in
                                            NavigationLink(value: set) {
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
                                                            Text("Full Set Value")
                                                                .font(.caption2.weight(.semibold))
                                                                .foregroundStyle(.secondary)
                                                                .lineLimit(1)
                                                        }
                                                        
                                                        if let total = progress.total, total > 0 {
                                                            ProgressView(value: min(Double(progress.collected), Double(total)), total: Double(total))
                                                                .progressViewStyle(.linear)
                                                                .tint(services.theme.accentColor)
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
                                                .padding(.horizontal)
                                                .padding(.vertical, 10)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            .task(id: setMarketValueTaskID(for: set)) {
                                                await ensureSetMarketValueLoaded(for: set)
                                            }
                                            Divider().padding(.leading, 108)
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            }
                            .padding(.bottom)
                        }
                    }
                }
            }
        }
        .navigationDestination(for: TCGSet.self) { set in
            SetCardsView(set: set)
        }
        .navigationTitle("Browse sets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            if isFirstAppear {
                Task {
                    await refreshCollectedCounts()
                    isFirstAppear = false
                }
            }
        }
        .onChange(of: collectionItems.count) { _, _ in
            Task { await refreshCollectedCounts() }
        }
    }

    private var globalProgressHeader: some View {
        let allSets = services.cardData.sets
        
        // Better: let's calculate based on unique card IDs in collection that match the current brand.
        let brandOwned = collectionItems.filter { item in
            let brand = TCGBrand.inferredFromMasterCardId(item.cardID)
            return brand == services.brandSettings.selectedCatalogBrand
        }
        let uniqueOwnedCount = Set(brandOwned.map(\.cardID)).count
        
        // Let's use a simpler "Sets Completed" or "Total Cards Collected" metric.
        let totalCardsInCatalog = allSets.reduce(0, { $0 + ($1.cardCountTotal ?? 0) })
        
        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Overall Completion")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Group {
                    Text("\(uniqueOwnedCount)")
                        .foregroundStyle(services.theme.accentColor)
                    + Text(" / \(totalCardsInCatalog)")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 13, weight: .black, design: .monospaced))
            }
            
            let progress = totalCardsInCatalog > 0 ? CGFloat(uniqueOwnedCount) / CGFloat(totalCardsInCatalog) : 0
            
            Capsule()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    services.theme.accentColor
                        .frame(maxWidth: .infinity)
                        .scaleEffect(x: max(progress, 0.005), y: 1.0, anchor: .leading)
                        .clipShape(Capsule())
                        .shadow(color: services.theme.accentColor.opacity(0.3), radius: 2, x: 0, y: 1)
                }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.025))
                .padding(.horizontal, 12)
        }
    }

    private func setProgress(for set: TCGSet) -> (collected: Int, total: Int?) {
        let collected = uniqueCollectedCountBySetCode[set.setCode.lowercased()] ?? 0
        return (collected, set.cardCountTotal)
    }

    private func setMarketValueTaskID(for set: TCGSet) -> String {
        "\(services.brandSettings.selectedCatalogBrand.rawValue)|\(set.setCode.lowercased())"
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
            guard let cheapestUSD = cheapestVariantMarketUSD(for: entry), cheapestUSD > 0 else { continue }
            totalUSD += cheapestUSD
            pricedCardCount += 1
        }

        if pricedCardCount > 0 {
            setMarketValueUSDByKey[key] = totalUSD
        } else {
            setMarketValueUSDByKey.removeValue(forKey: key)
        }
        loadedSetMarketValueKeys.insert(key)
    }

    private func cheapestVariantMarketUSD(for entry: CardPricingEntry) -> Double? {
        if let scrydex = entry.scrydex, !scrydex.isEmpty {
            return scrydex.values
                .compactMap { $0.marketEstimateUSD() }
                .filter { $0 > 0 }
                .min()
        }
        if let usd = entry.tcgplayerMarketEstimateUSD(), usd > 0 {
            return usd
        }
        return nil
    }

    @MainActor
    private func refreshCollectedCounts() async {
        let activeSetCodes = Set(services.cardData.sets.map { $0.setCode.lowercased() })
        var uniqueCardKeysBySetCode: [String: Set<String>] = [:]

        for item in collectionItems where item.quantity > 0 {
            guard let identity = await resolveCollectionCardIdentity(
                for: item.cardID,
                activeSetCodes: activeSetCodes
            ) else { continue }
            uniqueCardKeysBySetCode[identity.setCode, default: []].insert(identity.uniqueCardKey)
        }

        uniqueCollectedCountBySetCode = uniqueCardKeysBySetCode.mapValues(\.count)
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
        let components = cardID.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count >= 2 else { return nil }
        
        let setCode = String(components[0]).lowercased()
        if components.count == 3 {
            let number = String(components[2]).lowercased()
            return (setCode, "\(setCode)::\(number)")
        }
        return (setCode, cardID.lowercased())
    }

    private func browseSeriesTitle(for set: TCGSet) -> String {
        switch services.brandSettings.selectedCatalogBrand {
        case .pokemon:
            let title = set.seriesName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (title?.isEmpty == false ? title! : "Other")
        case .onePiece:
            return normalizedOnePieceSeriesTitle(set.seriesName)
        }
    }

    private func sortSetsNewestFirst(_ sets: [TCGSet]) -> [TCGSet] {
        sets.sorted { lhs, rhs in
            let ld = lhs.releaseDate ?? ""
            let rd = rhs.releaseDate ?? ""
            if ld != rd { return ld > rd }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func normalizedOnePieceSeriesTitle(_ raw: String?) -> String {
        let title = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lower = title.lowercased()
        if lower.contains("booster pack") { return "Booster Pack" }
        if lower.contains("extra booster") { return "Extra Boosters" }
        if lower.contains("starter") { return "Starter deck" }
        if lower.contains("premium booster") { return "Premium Booster" }
        if lower.contains("promo") { return "Promo" }
        return title.isEmpty ? "Other" : title
    }

    private func onePieceSeriesOrderIndex(_ title: String) -> Int {
        switch title {
        case "Booster Pack": return 0
        case "Extra Boosters": return 1
        case "Starter deck": return 2
        case "Premium Booster": return 3
        case "Promo": return 4
        default: return 5
        }
    }
}
