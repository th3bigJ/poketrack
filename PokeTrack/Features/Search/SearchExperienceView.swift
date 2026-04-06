import SwiftUI

struct SearchExperienceView: View {
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
                        .foregroundStyle(Color(white: 0.95))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.16))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    onBrowsePokemon()
                } label: {
                    Text("Browse Pokémon")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(white: 0.95))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.16))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Divider()
                .opacity(0.35)

            UniversalSearchResultsView(query: query)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
