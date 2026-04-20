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
    @State private var sourceScope: SearchSourceScope = .allCards

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Text(services.brandSettings.selectedCatalogBrand.displayTitle)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .padding(.horizontal, 2)

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
                selectedBrand: services.brandSettings.selectedCatalogBrand,
                sourceScope: sourceScope
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }
}
