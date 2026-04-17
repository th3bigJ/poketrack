import SwiftUI

struct SocialRootView: View {
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Social")
                    .font(.largeTitle.bold())
                    .padding(.horizontal, 16)

                ContentUnavailableView(
                    "Coming soon",
                    systemImage: "person.2",
                    description: Text("Friends, trades and activity feed coming soon.")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
            }
            .padding(.top, rootFloatingChromeInset)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
