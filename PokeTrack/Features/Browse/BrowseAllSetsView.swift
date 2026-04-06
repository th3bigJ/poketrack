import SwiftUI

struct BrowseAllSetsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        let sets = services.cardData.allSetsSortedByReleaseDateNewestFirst()
        Group {
            if sets.isEmpty {
                ContentUnavailableView(
                    "No sets",
                    systemImage: "rectangle.stack",
                    description: Text("Load your catalog to browse sets.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(sets) { set in
                            NavigationLink(value: set) {
                                VStack(spacing: 6) {
                                    SetLogoAsyncImage(logoSrc: set.logoSrc, height: 100)
                                    Text(set.name)
                                        .font(.caption2)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
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
}
