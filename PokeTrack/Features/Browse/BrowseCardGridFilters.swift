import SwiftUI

enum BrowseCardGridSortOption: String, CaseIterable, Identifiable, Sendable {
    case random
    case newestSet
    case cardName
    case cardNumber
    case rarity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .random: return "Random"
        case .newestSet: return "Newest set"
        case .cardName: return "Card name"
        case .cardNumber: return "Card number"
        case .rarity: return "Rarity"
        }
    }
}

enum BrowseCardTypeFilter: String, CaseIterable, Identifiable, Sendable {
    case pokemon
    case trainer
    case energy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pokemon: return "Pokemon"
        case .trainer: return "Trainer"
        case .energy: return "Energy"
        }
    }
}

struct BrowseCardGridFilters: Equatable, Sendable {
    var sortBy: BrowseCardGridSortOption = .random
    var cardTypes: Set<BrowseCardTypeFilter> = []
    var rarePlusOnly = false
    var hideOwned = false
    var energyTypes: Set<String> = []
    var rarities: Set<String> = []

    var isDefault: Bool {
        self == Self()
    }

    var hasActiveFieldFilters: Bool {
        !cardTypes.isEmpty
            || rarePlusOnly
            || hideOwned
            || !energyTypes.isEmpty
            || !rarities.isEmpty
    }

    var hasActiveSort: Bool {
        sortBy != .random
    }

    var hasActiveDataFilters: Bool {
        hasActiveFieldFilters
    }

    var isVisiblyCustomized: Bool {
        hasActiveFieldFilters
    }
}

struct BrowseGridOptions: Equatable, Sendable {
    var showCardName = true
    var showSetName = false
    var showPricing = false
    var columnCount = 3
}

struct BrowseCardGridFilterMenu: View {
    @Binding var filters: BrowseCardGridFilters
    @Binding var gridOptions: BrowseGridOptions

    let resultCount: Int
    let energyOptions: [String]
    let rarityOptions: [String]
    let onReset: () -> Void

    @State private var isSortExpanded = true
    @State private var isEnergyExpanded = false
    @State private var isRarityExpanded = false
    @State private var isGridOptionsExpanded = false

    private var glassStroke: Color { Color.primary.opacity(0.08) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                divider
                sortSection
                divider
                cardTypeSection
                divider
                toggleRow("Rare + only", isOn: $filters.rarePlusOnly)
                divider
                toggleRow("Hide owned", isOn: $filters.hideOwned)
                divider
                energySection
                divider
                raritySection
                divider
                displaySection
            }
        }
        .frame(width: 290)
        .frame(maxHeight: 520)
        .padding(10)
        .background(backgroundView)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(glassStroke, lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.18), radius: 22, x: 0, y: 12)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Card Grid Filters")
                    .font(.headline.weight(.semibold))
                Text("\(resultCount) cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if filters.isDefault == false {
                Button("Reset", action: onReset)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var sortSection: some View {
        VStack(spacing: 0) {
            sectionLabel(title: "Sort by", subtitle: filters.sortBy.title, isExpanded: isSortExpanded)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { isSortExpanded.toggle() } }
            if isSortExpanded {
                VStack(spacing: 0) {
                    ForEach(BrowseCardGridSortOption.allCases) { option in
                        optionRow(title: option.title, isSelected: filters.sortBy == option) {
                            filters.sortBy = option
                        }
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var cardTypeSection: some View {
        VStack(spacing: 0) {
            sectionLabel(title: "Card type", subtitle: selectionSummary(for: filters.cardTypes), isExpanded: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            VStack(spacing: 0) {
                ForEach(BrowseCardTypeFilter.allCases) { type in
                    multiSelectRow(title: type.title, isSelected: filters.cardTypes.contains(type)) {
                        toggle(type, in: &filters.cardTypes)
                    }
                }
            }
        }
    }

    private var energySection: some View {
        VStack(spacing: 0) {
            sectionLabel(title: "Energy", subtitle: selectionSummary(for: filters.energyTypes), isExpanded: isEnergyExpanded)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { isEnergyExpanded.toggle() } }
            if isEnergyExpanded {
                VStack(spacing: 0) {
                    if energyOptions.isEmpty {
                        emptyRow("No energy types available")
                    } else {
                        ForEach(energyOptions, id: \.self) { energy in
                            multiSelectRow(title: energy, isSelected: filters.energyTypes.contains(energy)) {
                                toggle(energy, in: &filters.energyTypes)
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var raritySection: some View {
        VStack(spacing: 0) {
            sectionLabel(title: "Rarity", subtitle: selectionSummary(for: filters.rarities), isExpanded: isRarityExpanded)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { isRarityExpanded.toggle() } }
            if isRarityExpanded {
                VStack(spacing: 0) {
                    if rarityOptions.isEmpty {
                        emptyRow("No rarities available")
                    } else {
                        ForEach(rarityOptions, id: \.self) { rarity in
                            multiSelectRow(title: rarity, isSelected: filters.rarities.contains(rarity)) {
                                toggle(rarity, in: &filters.rarities)
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var displaySection: some View {
        VStack(spacing: 0) {
            sectionLabel(title: "Grid options", subtitle: nil, isExpanded: isGridOptionsExpanded)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { isGridOptionsExpanded.toggle() } }
            if isGridOptionsExpanded {
                VStack(spacing: 0) {
                    toggleRow("Show card name", isOn: $gridOptions.showCardName)
                    divider
                    toggleRow("Show set name", isOn: $gridOptions.showSetName)
                    divider
                    toggleRow("Show pricing", isOn: $gridOptions.showPricing)
                    divider
                    stepperRow("Columns", value: $gridOptions.columnCount, in: 1...4)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var backgroundView: some View {
        Group {
            if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
    }

    private var divider: some View {
        Divider()
            .overlay(Color.primary.opacity(0.06))
            .padding(.horizontal, 12)
    }

    private func sectionLabel(title: String, subtitle: String?, isExpanded: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func optionRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary.opacity(0.6))
                Text(title)
                    .font(.body)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func multiSelectRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 18)
                Text(title)
                    .font(.body)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.body)
        }
        .tint(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func stepperRow(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            HStack {
                Text(title)
                    .font(.body)
                Spacer()
                Text("\(value.wrappedValue)")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func emptyRow(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func selectionSummary(for values: Set<String>) -> String? {
        guard values.isEmpty == false else { return "Any" }
        if values.count == 1 { return values.first }
        return "\(values.count) selected"
    }

    private func selectionSummary(for values: Set<BrowseCardTypeFilter>) -> String? {
        guard values.isEmpty == false else { return "Any" }
        if values.count == 1 { return values.first?.title }
        return "\(values.count) selected"
    }

    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }
}
