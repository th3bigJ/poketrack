import SwiftUI

struct DeckShareView: View {
    @Environment(AppServices.self) private var services
    let item: SocialFeedService.FeedItem
    
    var body: some View {
        HStack(spacing: 16) {
            // Stacked card thumbnails
            ZStack {
                ForEach(0..<min(3, item.thumbnails?.count ?? 0), id: \.self) { index in
                    if let thumbnails = item.thumbnails {
                        thumbnail(cardID: thumbnails[index])
                            .rotationEffect(.degrees(Double(index - 1) * 10))
                            .offset(x: Double(index - 1) * 15)
                    }
                }
            }
            .frame(width: 80, height: 80)
            .padding(.leading, 10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.content?.title ?? "New Deck")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                
                Text(item.pullSetName ?? "Standard Format")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    private func thumbnail(cardID: String) -> some View {
        AsyncImage(url: AppConfiguration.imageURL(relativePath: "cards/thumbnails/\(cardID).jpg")) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Color.primary.opacity(0.05)
        }
        .frame(width: 42, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
    }
}
