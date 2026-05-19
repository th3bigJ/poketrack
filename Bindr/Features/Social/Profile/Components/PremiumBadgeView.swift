import SwiftUI

// MARK: - PremiumBadgeStyle

/// Which icon a premium user has chosen to display next to their name.
enum PremiumBadgeStyle: String, CaseIterable, Codable, Sendable {
    case pokeball  = "pokeball"
    case strawHat  = "straw_hat"

    var displayName: String {
        switch self {
        case .pokeball: return "Pokéball"
        case .strawHat: return "Straw Hat"
        }
    }

    var gameHint: String {
        switch self {
        case .pokeball: return "Pokémon"
        case .strawHat: return "ONE PIECE"
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

    @ViewBuilder
    private var emblem: some View {
        switch profile.badgeStyle {
        case .pokeball:
            PokeballEmblemView(size: size)
        case .strawHat:
            StrawHatEmblemView(size: size)
        }
    }
}

// MARK: - StrawHatEmblemView

/// Vector-drawn Luffy-style straw hat badge for ONE PIECE premium users.
/// Rendered entirely with SwiftUI shapes — no images, scales perfectly.
struct StrawHatEmblemView: View {
    var size: CGFloat = 14

    var body: some View {
        Canvas { ctx, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let cx = w / 2
            let cy = h / 2

            // ── Brim (wide flat ellipse) ────────────────────────────────
            let brimW = w * 0.98
            let brimH = h * 0.38
            let brimY = cy + h * 0.18
            let brimRect = CGRect(x: cx - brimW / 2, y: brimY - brimH / 2, width: brimW, height: brimH)

            let brimPath = Path(ellipseIn: brimRect)
            ctx.fill(brimPath, with: .color(Color(hex: "D4A017")))
            ctx.stroke(brimPath, with: .color(Color(hex: "8B6914")), lineWidth: size * 0.06)

            // ── Crown (dome on top) ─────────────────────────────────────
            let crownW = w * 0.54
            let crownH = h * 0.52
            let crownRect = CGRect(x: cx - crownW / 2, y: cy - h * 0.40, width: crownW, height: crownH)
            var crownPath = Path()
            crownPath.addArc(
                center: CGPoint(x: cx, y: crownRect.maxY),
                radius: crownW / 2,
                startAngle: .degrees(180),
                endAngle: .degrees(0),
                clockwise: false
            )
            crownPath.closeSubpath()
            ctx.fill(crownPath, with: .color(Color(hex: "D4A017")))
            ctx.stroke(crownPath, with: .color(Color(hex: "8B6914")), lineWidth: size * 0.06)

            // ── Red band ────────────────────────────────────────────────
            let bandH = h * 0.14
            let bandY = brimRect.minY - bandH * 0.4
            let bandRect = CGRect(x: cx - crownW * 0.52, y: bandY, width: crownW * 1.04, height: bandH)
            let bandPath = Path(ellipseIn: bandRect)
            ctx.fill(bandPath, with: .color(Color(hex: "E04040")))

            // ── Band highlight ──────────────────────────────────────────
            let hlH = bandH * 0.35
            let hlRect = CGRect(x: bandRect.minX + bandRect.width * 0.15,
                                y: bandRect.minY + bandH * 0.15,
                                width: bandRect.width * 0.7, height: hlH)
            let hlPath = Path(ellipseIn: hlRect)
            ctx.fill(hlPath, with: .color(.white.opacity(0.28)))
        }
        .frame(width: size * 1.35, height: size)
        .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 12) {
            PokeballEmblemView(size: 24)
            Text("Premium Trainer").font(.headline)
        }
        HStack(spacing: 12) {
            StrawHatEmblemView(size: 24)
            Text("Premium Pirate").font(.headline)
        }
    }
    .padding()
}
