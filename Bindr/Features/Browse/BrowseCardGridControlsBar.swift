import SwiftUI

/// Inline search + glass grid/filter controls used beneath section tabs on
/// collection-style surfaces (friend profiles, friends' collections, etc.).
struct BrowseCardGridControlsBar: View {
    @Environment(AppServices.self) private var services

    let searchTitle: String
    @Binding var query: String
    @Binding var filters: BrowseCardGridFilters
    @Binding var gridOptions: BrowseGridOptions

    let brand: TCGBrand
    let energyOptions: [String]
    let rarityOptions: [String]
    let trainerTypeOptions: [String]
    var filterConfig: FilterMenuConfig = FilterMenuConfig(
        showAcquiredDateSort: false,
        showRandomSort: false,
        showHideOwned: false,
        showOwnedOnly: false,
        showShowDuplicates: false,
        showGridOptions: false,
        defaultSortBy: .cardName,
        showGridOwnedToggle: false
    )
    var isAllBrands: Bool = false
    var gridNameToggleTitle: String = "Show card name"
    var showGridCardIDToggle: Bool = true
    var showGridOwnedToggle: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            BrowseInlineSearchField(title: searchTitle, text: $query)

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                Menu {
                    BrowseGridOptionsMenuContent(
                        gridOptions: $gridOptions,
                        nameToggleTitle: gridNameToggleTitle,
                        showCardIDToggle: showGridCardIDToggle,
                        showOwnedToggle: showGridOwnedToggle
                    )
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
                    BrowseGridFiltersMenuContent(
                        brand: brand,
                        filters: $filters,
                        energyOptions: energyOptions,
                        rarityOptions: rarityOptions,
                        trainerTypeOptions: trainerTypeOptions,
                        isAllBrands: isAllBrands,
                        gridOptions: $gridOptions,
                        config: filterConfig
                    )
                } label: {
                    Image(
                        systemName: filters.isVisiblyCustomized
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle"
                    )
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(filters.isVisiblyCustomized ? services.theme.accentColor : .primary)
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
    }
}
