import SwiftUI

struct PullEventView: View {
    @Environment(AppServices.self) private var services
    let item: SocialFeedService.FeedItem
    
    var body: some View {
        HStack(spacing: 12) {
            // Card Thumbnail
            if let cardID = item.pullCardID {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(cardGradient)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    
                    AsyncImage(url: AppConfiguration.imageURL(relativePath: "cards/thumbnails/\(cardID).jpg")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.primary.opacity(0.05)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    
                    // Inset highlight
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(LinearGradient(colors: [.primary.opacity(0.2), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
                .frame(width: 54, height: 76)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.pullCardName ?? "Unknown Card")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                
                Text(item.pullSetName ?? "Unknown Set")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    if let value = item.pullValue {
                        Text(formatCurrency(value))
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(.primary)
                    }
                    
                    if let rarity = item.pullRarity {
                        Text(rarity)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: "f59e0b").opacity(0.2))
                            .foregroundStyle(Color(hex: "f59e0b"))
                            .clipShape(Capsule())
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private var cardGradient: LinearGradient {
        LinearGradient(colors: [Color.primary.opacity(0.05), Color.black.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "GBP"
        return formatter.string(from: NSNumber(value: value)) ?? "£\(value)"
    }
}
