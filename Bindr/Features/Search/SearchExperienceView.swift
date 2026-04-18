import SwiftUI

enum SearchSourceScope: String, CaseIterable, Identifiable {
    case allCards
    case myCollection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allCards: return "All cards"
        case .myCollection: return "My collection"
        }
    }
}

struct SearchExperienceView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset

    @Binding var query: String
    @State private var selectedBrand: TCGBrand = .pokemon
    @State private var sourceScope: SearchSourceScope = .allCards

    private var enabledBrands: [TCGBrand] {
        services.brandsManifest.sortBrands(services.brandSettings.enabledBrands)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                if !enabledBrands.isEmpty {
                    Picker("Brand", selection: $selectedBrand) {
                        ForEach(enabledBrands) { brand in
                            Text(brand.displayTitle).tag(brand)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Picker("Search source", selection: $sourceScope) {
                    ForEach(SearchSourceScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 16)
            .padding(.top, rootFloatingChromeInset + 12)
            .padding(.bottom, 10)

            UniversalSearchResultsView(
                query: query,
                selectedBrand: selectedBrand,
                sourceScope: sourceScope
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            syncSelectedBrand()
        }
        .onChange(of: services.brandSettings.enabledBrands) { _, _ in
            syncSelectedBrand()
        }
    }

    private func syncSelectedBrand() {
        let enabled = enabledBrands
        guard !enabled.isEmpty else { return }
        if enabled.contains(selectedBrand) { return }
        if enabled.contains(services.brandSettings.selectedCatalogBrand) {
            selectedBrand = services.brandSettings.selectedCatalogBrand
        } else if let first = enabled.first {
            selectedBrand = first
        }
    }
}
