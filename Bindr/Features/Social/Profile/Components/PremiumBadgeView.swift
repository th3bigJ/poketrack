import SwiftUI

// MARK: - PremiumBadgeStyle

/// Which icon a premium user has chosen to display next to their name.
enum PremiumBadgeStyle: String, CaseIterable, Codable, Sendable {
    case pokeball  = "pokeball"

    var displayName: String {
        switch self {
        case .pokeball: return "Pocket Collector"
        }
    }

    var gameHint: String {
        switch self {
        case .pokeball: return "COLLECTOR"
        }
    }
}

// MARK: - PremiumBadgeView

/// Unified badge view that reads the profile's chosen style and renders
/// the appropriate emblem. Drop this in wherever a badge is needed —
/// it handles the nil / non-premium case by rendering nothing.
struct PremiumBadgeView: View {
    @Environment(AppServices.self) private var services
    
    let profile: SocialProfile
    var size: CGFloat = 14
    /// Temporary override: show for all users while testing.
    /// Set this to `true` to allow anyone to have the badge for preview/testing.
    var showForAllUsers: Bool = true

    var isPremium: Bool {
        if let myID = services.socialAuth.currentUserID, profile.id == myID {
            return services.store.isPremium
        }
        return profile.hasPremium
    }

    var body: some View {
        if showForAllUsers || isPremium {
            emblem
        }
    }

    private var emblem: some View {
        PokeballEmblemView(size: size)
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 12) {
        PokeballEmblemView(size: 24)
        Text("Premium Trainer").font(.headline)
    }
    .padding()
}
