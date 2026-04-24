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
                ProfileAvatarView(profile: profile, size: 80)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName ?? profile.username)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("@\(profile.username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
            }
            .padding(.leading, 20)
            .offset(y: 40) // Overlap into content
        }
        .frame(height: 230)
    }
}

struct ProfileAvatarView: View {
    let profile: SocialProfile
    let size: CGFloat
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            if let avatarURL = profile.avatarURL, let url = URL(string: avatarURL) {
                // Custom uploaded avatar (fallback)
                CachedAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle().fill(Color.gray.opacity(0.2))
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                // Pokémon Icon Avatar
                Circle()
                    .fill(avatarBackground)
                    .frame(width: size, height: size)
                
                if let imageURL = profile.favoritePokemonImageURL, let url = URL(string: imageURL) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView().scaleEffect(0.8)
                    }
                    .frame(width: size * 0.75, height: size * 0.75)
                } else if let dex = profile.favoritePokemonDex {
                    // Fallback to construction if URL is missing for some reason
                    let imageFileName = "\(dex)-1.png" 
                    CachedAsyncImage(url: AppConfiguration.pokemonArtURL(imageFileName: imageFileName)) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView().scaleEffect(0.8)
                    }
                    .frame(width: size * 0.75, height: size * 0.75)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            
            // Outline Pattern
            avatarOutline
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
    
    private var avatarBackground: AnyShapeStyle {
        if let hex = profile.avatarBackgroundColor {
            return AnyShapeStyle(Color(hex: hex))
        }
        // Default premium gradient
        return AnyShapeStyle(LinearGradient(
            colors: [Color(hex: "6366f1"), Color(hex: "4f46e5")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ))
    }
    
    @ViewBuilder
    private var avatarOutline: some View {
        let style = profile.avatarOutlineStyle ?? "solid"
        let color = colorScheme == .dark ? Color.white.opacity(0.3) : Color.white.opacity(0.5)
        
        Circle()
            .strokeBorder(color, lineWidth: style == "thick" ? 4 : 2)
            .if(style == "dotted") { view in
                view.overlay(
                    Circle()
                        .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [4]))
                )
            }
            .if(style == "double") { view in
                view.padding(3)
                    .overlay(Circle().stroke(color, lineWidth: 1))
            }
            .if(style == "dashed") { view in
                view.overlay(
                    Circle()
                        .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                )
            }
            .if(style == "glow") { view in
                view.shadow(color: Color(hex: profile.avatarBackgroundColor ?? "4f46e5").opacity(0.5), radius: 6)
            }
    }
}

extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

