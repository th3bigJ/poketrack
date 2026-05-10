import SwiftUI

struct BinderShareView: View {
    @Environment(AppServices.self) private var services
    let item: SocialFeedService.FeedItem

    var body: some View {
        let binder = Binder(
            title: item.content?.title ?? "Binder",
            pageLayout: .fixed(rows: 3, columns: 3), // Fallback
            colour: item.binderColour ?? "navy",
            texture: BinderTexture(rawValue: item.binderTexture ?? "leather") ?? .leather
        )

        return VStack(alignment: .leading, spacing: 12) {
            BinderCoverView(
                binder: binder,
                compact: true
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
