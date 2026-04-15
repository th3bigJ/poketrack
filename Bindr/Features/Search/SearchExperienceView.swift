import SwiftUI

struct SearchExperienceView: View {
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset

    @Binding var query: String

    var body: some View {
        UniversalSearchResultsView(query: query)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, rootFloatingChromeInset)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
    }
}
