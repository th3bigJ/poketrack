import SwiftUI

struct BrowseInlineSearchField: View {
    let title: String
    @Binding var text: String
    private let chromeCornerRadius: CGFloat = 16

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(title, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: chromeCornerRadius, style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill))
        )
    }
}

struct BrowseAllSetsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

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
                                                    SetLogoAsyncImage(logoSrc: set.logoSrc, height: 44, brand: services.brandSettings.selectedCatalogBrand)
                                                        .frame(width: 80)
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(set.name)
                                                            .font(.subheadline.weight(.medium))
                                                            .foregroundStyle(.primary)
                                                            .lineLimit(2)
                                                        Text(set.setCode.uppercased())
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
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
