import SwiftUI
import UIKit

struct SearchExperienceView: View {
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset

    @Binding var query: String
    var onBrowseSets: () -> Void
    var onBrowsePokemon: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    onBrowseSets()
                } label: {
                    Text("Browse sets")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemFill))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    onBrowsePokemon()
                } label: {
                    Text("Browse Pokémon")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemFill))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 6)

            Divider()
                .opacity(0.5)

            UniversalSearchResultsView(query: query)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // Root `UniversalSearchBar` is overlaid in `ZStack` above this stack; inset matches `BrowseView` spacer.
        .padding(.top, rootFloatingChromeInset)
        // Title is for the **back** label on pushed screens (`DexCardsView` / `SetCardsView` — same pattern as Browse Pokémon).
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }
}
