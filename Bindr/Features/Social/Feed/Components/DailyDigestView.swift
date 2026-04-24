import SwiftUI

struct DailyDigestView: View {
    @Environment(AppServices.self) private var services
    let item: SocialFeedService.FeedItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 8) {
                if let count = item.digestCollectionCount, count > 0 {
                    digestRow(icon: "plus.circle.fill", text: "Added \(count) cards to collection")
                }
                
                if let count = item.digestWishlistCount, count > 0 {
                    digestRow(icon: "star.fill", text: "Added \(count) cards to wishlist")
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            if let thumbnails = item.digestThumbnails, !thumbnails.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(thumbnails.prefix(4), id: \.self) { cardID in
                            thumbnail(cardID: cardID)
                        }
                        
                        if thumbnails.count > 4 {
                            overflowTile(count: thumbnails.count - 4)
                        }
                    }
                }
            }
        }
    }
    
    private func digestRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color(hex: "5b9df9"))
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            
            Spacer()
            
            Button("View") {
                // Navigate to filtered view
            }
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.1))
            .clipShape(Capsule())
            .foregroundStyle(.primary)
        }
    }
    
    private func thumbnail(cardID: String) -> some View {
        AsyncImage(url: AppConfiguration.imageURL(relativePath: "cards/thumbnails/\(cardID).jpg")) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Color.white.opacity(0.1)
        }
        .frame(width: 42, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
    
    private func overflowTile(count: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.1))
            
            Text("+\(count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 42, height: 58)
    }
}
