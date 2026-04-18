import SwiftUI

struct SocialRootView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ContentUnavailableView(
                    "Coming soon",
                    systemImage: "person.2",
                    description: Text("Friends, trades and activity feed coming soon.")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
            }
            .padding(.top, 16)
        }
        .navigationTitle("Social")
        .navigationBarTitleDisplayMode(.inline)
    }
}
