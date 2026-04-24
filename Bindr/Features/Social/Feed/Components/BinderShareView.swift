import SwiftUI

struct BinderShareView: View {
    @Environment(AppServices.self) private var services
    let item: SocialFeedService.FeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BinderCoverView(
                title: item.content?.title ?? "Binder",
                subtitle: nil,
                colourName: item.binderColour ?? "navy",
                texture: BinderTexture(rawValue: item.binderTexture ?? "leather") ?? .leather,
                seed: item.binderSeed ?? 1,
                peekingCardURLs: [],
                showCardPreview: true,
                compact: true
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
