import SwiftUI

struct SocialRootView: View {
    var body: some View {
        VStack(spacing: 0) {
            socialHeader
            ScrollView {
                ContentUnavailableView(
                    "Coming soon",
                    systemImage: "person.2",
                    description: Text("Friends, trades and activity feed coming soon.")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
                .padding(.top, 16)
            }
        }
        .navigationTitle("Social")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var socialHeader: some View {
        ZStack {
            Text("Social")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)

            HStack {
                ChromeGlassCircleButton(accessibilityLabel: "Search") {} label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 0)
                Menu {
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                        .modifier(ChromeGlassCircleGlyphModifier())
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .menuActionDismissBehavior(.disabled)
                .menuOrder(.fixed)
                .menuIndicator(.hidden)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
