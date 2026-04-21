import SwiftUI

struct ProfileHeroHeader: View {
    let profile: SocialProfile
    let onEditTapped: (() -> Void)?
    
    @Environment(\.colorScheme) var colorScheme
    
    private var backgroundGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [Color(hex: "161616"), Color(hex: "0a0a0a")],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [Color(hex: "e8e8ed"), Color(hex: "f2f2f7")],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background Gradient
            backgroundGradient
                .frame(height: 230)
            
            // Texture: Diagonal Rule Lines
            Canvas { context, size in
                let p1 = CGPoint(x: size.width * 0.2, y: 0)
                let p2 = CGPoint(x: size.width * 0.5, y: size.height)
                
                let p3 = CGPoint(x: size.width * 0.5, y: 0)
                let p4 = CGPoint(x: size.width * 0.8, y: size.height)
                
                context.stroke(Path { path in
                    path.move(to: p1)
                    path.addLine(to: p2)
                }, with: .color(colorScheme == .dark ? .white.opacity(0.03) : .black.opacity(0.04)), lineWidth: 1)
                
                context.stroke(Path { path in
                    path.move(to: p3)
                    path.addLine(to: p4)
                }, with: .color(colorScheme == .dark ? .white.opacity(0.03) : .black.opacity(0.04)), lineWidth: 1)
            }
            .rotationEffect(.degrees(15))
            .clipped()
            
            // Watermark Pokédex Number
            if let dex = profile.favoritePokemonDex {
                Text("#\(String(format: "%03d", dex))")
                    .font(.system(size: 140, weight: .black))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .opacity(colorScheme == .dark ? 0.04 : 0.05)
                    .frame(maxWidth: .infinity, maxHeight: 230, alignment: .center)
                    .offset(y: -10)
                    .allowsHitTesting(false)
            }
            
            // Edit Button (Top Right)
            if let onEditTapped = onEditTapped {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: onEditTapped) {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.primary)
                                .frame(width: 32, height: 32)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.1), radius: 2)
                        }
                        .padding(.top, 50) // Adjust for status bar if needed inside modal
                        .padding(.trailing, 20)
                    }
                    Spacer()
                }
            }
            
            // Hero Card (Tilted)
            HStack {
                Spacer()
                ZStack {
                    // Ghost Card
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(colorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.05), lineWidth: 1)
                        .frame(width: 100, height: 140)
                        .offset(x: -8, y: 4)
                    
                    // Main Card
                    if let imageURL = profile.favoriteCardImageURL, let url = URL(string: imageURL) {
                        CachedAsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.gray.opacity(0.1)
                        }
                        .frame(width: 100, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                        // Sheen effect
                        .overlay(
                            LinearGradient(
                                colors: [.white.opacity(0.15), .clear, .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        )
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.gray.opacity(0.1))
                            .frame(width: 100, height: 140)
                    }
                }
                .rotationEffect(.degrees(6))
                .padding(.top, 40)
                .padding(.trailing, 30)
            }
            
            // Avatar and Identity (Bottom Left)
            HStack(alignment: .bottom, spacing: 12) {
                // Avatar
                if let avatarURL = profile.avatarURL, let url = URL(string: avatarURL) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle().fill(Color.gray.opacity(0.2))
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 2))
                    .shadow(radius: 4)
                } else {
                    Circle()
                        .fill(LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 64, height: 64)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundStyle(.secondary)
                        )
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 2))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName ?? profile.username)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("@\(profile.username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)
            }
            .padding(.leading, 20)
            .offset(y: 32) // Overlap into content
        }
        .frame(height: 230)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
