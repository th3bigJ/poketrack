import SwiftUI

/// Procedural texture layer painted on top of a binder's base colour.
///
/// Every texture is drawn from code at runtime — no image assets. A deterministic
/// seed (see ``Binder/textureSeed``) keeps each binder's pattern stable across
/// app launches and device rotations so the surface doesn't "reshuffle" after a
/// render. The view is intentionally a simple rectangle; callers clip it to
/// whatever shape they need (rounded binder covers, inset card backs, etc.).
struct BinderTextureView: View {
    let baseColour: Color
    let texture: BinderTexture
    let seed: Int

    /// Coarser, cheaper variant for small previews (binder picker swatches,
    /// thumbnail cells). Skips fine-detail passes that disappear at small sizes.
    var compact: Bool = false

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            // Base fill — dyed surface behind the grain/weave pass.
            ctx.fill(Path(rect), with: .color(baseColour))

            // Subtle colour variation: slightly darker towards bottom-right,
            // lifts the "flat paint" feeling even before the texture renders.
            let shade = Gradient(stops: [
                .init(color: .black.opacity(0), location: 0),
                .init(color: .black.opacity(0.16), location: 1)
            ])
            ctx.fill(
                Path(rect),
                with: .linearGradient(
                    shade,
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: rect.width, y: rect.height)
                )
            )

            switch texture {
            case .leather: drawLeather(&ctx, rect: rect)
            case .suede:   drawSuede(&ctx, rect: rect)
            case .felt:    drawFelt(&ctx, rect: rect)
            case .linen:   drawLinen(&ctx, rect: rect)
            case .carbon:  drawCarbon(&ctx, rect: rect)
            case .smooth:  drawSmooth(&ctx, rect: rect)
            }

            // Shared top-left sheen + bottom-right vignette to sell depth.
            drawSheen(&ctx, rect: rect)
        }
    }

    // MARK: Leather

    private func drawLeather(_ ctx: inout GraphicsContext, rect: CGRect) {
        var rng = SeededRandom(seed: seed)
        // Horizontal grain — the signature of a leather surface.
        let lineSpacing: CGFloat = compact ? 4 : 2.5
        let lineCount = Int(rect.height / lineSpacing)
        for _ in 0..<lineCount {
            let y = CGFloat.random(in: 0...rect.height, using: &rng)
            let alpha = CGFloat.random(in: 0.02...0.08, using: &rng)
            let highlight = Bool.random(using: &rng)

            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            let segments = 6
            for i in 1...segments {
                let x = rect.width * CGFloat(i) / CGFloat(segments)
                let dy = CGFloat.random(in: -1.0...1.0, using: &rng)
                path.addLine(to: CGPoint(x: x, y: y + dy))
            }
            let stroke: Color = highlight ? .white.opacity(alpha * 0.55) : .black.opacity(alpha)
            ctx.stroke(path, with: .color(stroke), lineWidth: 0.55)
        }

        // A few deeper creases for character.
        let creaseCount = compact ? 3 : 6
        for _ in 0..<creaseCount {
            let start = CGPoint(
                x: CGFloat.random(in: 0...rect.width, using: &rng),
                y: CGFloat.random(in: 0...rect.height, using: &rng)
            )
            let end = CGPoint(
                x: start.x + CGFloat.random(in: -30...30, using: &rng),
                y: start.y + CGFloat.random(in: 20...80, using: &rng)
            )
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            ctx.stroke(path, with: .color(.black.opacity(0.10)), lineWidth: 0.4)
        }

        // Fine pore stipple.
        if !compact {
            let poreCount = Int(rect.width * rect.height / 28)
            for _ in 0..<poreCount {
                let x = CGFloat.random(in: 0...rect.width, using: &rng)
                let y = CGFloat.random(in: 0...rect.height, using: &rng)
                let r: CGFloat = 0.5
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                    with: .color(.black.opacity(0.12))
                )
            }
        }
    }

    // MARK: Suede

    private func drawSuede(_ ctx: inout GraphicsContext, rect: CGRect) {
        var rng = SeededRandom(seed: seed)
        // Soft, fuzzy stipple — many tiny specks, half light, half dark.
        let density: CGFloat = compact ? 14 : 8
        let count = Int(rect.width * rect.height / density)
        for _ in 0..<count {
            let x = CGFloat.random(in: 0...rect.width, using: &rng)
            let y = CGFloat.random(in: 0...rect.height, using: &rng)
            let r = CGFloat.random(in: 0.3...0.8, using: &rng)
            let alpha = CGFloat.random(in: 0.05...0.15, using: &rng)
            let isHighlight = Int.random(in: 0...3, using: &rng) == 0
            let color: Color = isHighlight
                ? .white.opacity(alpha)
                : .black.opacity(alpha)
            ctx.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                with: .color(color)
            )
        }

        // Gentle "nap" direction — a soft diagonal wash suggesting brushed fibres.
        let nap = Gradient(stops: [
            .init(color: .white.opacity(0.04), location: 0),
            .init(color: .white.opacity(0), location: 0.5),
            .init(color: .black.opacity(0.04), location: 1)
        ])
        ctx.fill(
            Path(rect),
            with: .linearGradient(
                nap,
                startPoint: CGPoint(x: 0, y: rect.height),
                endPoint: CGPoint(x: rect.width, y: 0)
            )
        )
    }

    // MARK: Felt

    private func drawFelt(_ ctx: inout GraphicsContext, rect: CGRect) {
        var rng = SeededRandom(seed: seed)
        // Short random fibres at random angles — densely overlapping.
        let density: CGFloat = compact ? 18 : 11
        let count = Int(rect.width * rect.height / density)
        for _ in 0..<count {
            let x = CGFloat.random(in: 0...rect.width, using: &rng)
            let y = CGFloat.random(in: 0...rect.height, using: &rng)
            let angle = CGFloat.random(in: 0...(2 * .pi), using: &rng)
            let length = CGFloat.random(in: 1.5...4, using: &rng)
            let alpha = CGFloat.random(in: 0.04...0.12, using: &rng)
            let dx = cos(angle) * length
            let dy = sin(angle) * length

            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + dx, y: y + dy))

            let isHighlight = Bool.random(using: &rng)
            let stroke: Color = isHighlight
                ? .white.opacity(alpha * 0.7)
                : .black.opacity(alpha)
            ctx.stroke(path, with: .color(stroke), lineWidth: 0.45)
        }
    }

    // MARK: Linen

    private func drawLinen(_ ctx: inout GraphicsContext, rect: CGRect) {
        var rng = SeededRandom(seed: seed)
        let spacing: CGFloat = compact ? 4 : 3

        // Horizontal threads (warp).
        var y: CGFloat = 0
        while y < rect.height {
            let jitter = CGFloat.random(in: -0.25...0.25, using: &rng)
            let alpha = CGFloat.random(in: 0.07...0.13, using: &rng)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y + jitter))
            path.addLine(to: CGPoint(x: rect.width, y: y + jitter))
            ctx.stroke(path, with: .color(.black.opacity(alpha)), lineWidth: 0.5)
            y += spacing
        }

        // Vertical threads (weft) — lighter so the weave reads as a cross-hatch.
        var x: CGFloat = 0
        while x < rect.width {
            let jitter = CGFloat.random(in: -0.25...0.25, using: &rng)
            let alpha = CGFloat.random(in: 0.04...0.09, using: &rng)
            var path = Path()
            path.move(to: CGPoint(x: x + jitter, y: 0))
            path.addLine(to: CGPoint(x: x + jitter, y: rect.height))
            ctx.stroke(path, with: .color(.white.opacity(alpha)), lineWidth: 0.4)
            x += spacing
        }
    }

    // MARK: Carbon

    private func drawCarbon(_ ctx: inout GraphicsContext, rect: CGRect) {
        // Woven carbon-fibre tiles: checker of dark/light half-cells, offset row.
        let cell: CGFloat = compact ? 5 : 6
        var y: CGFloat = 0
        var row = 0
        while y < rect.height {
            var x: CGFloat = (row % 2 == 0) ? 0 : cell
            while x < rect.width {
                let tile = CGRect(x: x, y: y, width: cell * 2, height: cell)
                let half = cell
                let darkA = CGRect(x: tile.minX, y: tile.minY, width: half, height: half)
                let darkB = CGRect(x: tile.midX, y: tile.minY, width: half, height: half)
                // Rotate the dark/light pair for a subtle woven look.
                ctx.fill(Path(darkA), with: .color(.black.opacity(0.24)))
                ctx.fill(Path(darkB), with: .color(.white.opacity(0.06)))
                // Tiny specular highlight on each dark block — the signature
                // anisotropic glint of carbon fibre.
                let highlight = CGRect(
                    x: darkA.minX,
                    y: darkA.minY,
                    width: half,
                    height: max(0.6, half * 0.18)
                )
                ctx.fill(Path(highlight), with: .color(.white.opacity(0.10)))
                x += cell * 2
            }
            y += cell
            row += 1
        }
    }

    // MARK: Smooth

    private func drawSmooth(_ ctx: inout GraphicsContext, rect: CGRect) {
        // Very subtle noise just to break up the flat fill.
        var rng = SeededRandom(seed: seed)
        let count = Int(rect.width * rect.height / (compact ? 80 : 45))
        for _ in 0..<count {
            let x = CGFloat.random(in: 0...rect.width, using: &rng)
            let y = CGFloat.random(in: 0...rect.height, using: &rng)
            let alpha = CGFloat.random(in: 0.02...0.06, using: &rng)
            ctx.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: 0.8, height: 0.8)),
                with: .color(.black.opacity(alpha))
            )
        }

        // A broader highlight band — smooth binders get more specular than others.
        let band = Gradient(stops: [
            .init(color: .white.opacity(0), location: 0),
            .init(color: .white.opacity(0.10), location: 0.45),
            .init(color: .white.opacity(0), location: 0.9)
        ])
        ctx.fill(
            Path(rect),
            with: .linearGradient(
                band,
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: rect.width, y: rect.height)
            )
        )
    }

    // MARK: Shared sheen

    private func drawSheen(_ ctx: inout GraphicsContext, rect: CGRect) {
        // Top-left highlight — catches "light" from upper-left.
        let highlight = Gradient(stops: [
            .init(color: .white.opacity(0.16), location: 0),
            .init(color: .white.opacity(0), location: 0.55)
        ])
        ctx.fill(
            Path(rect),
            with: .linearGradient(
                highlight,
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: rect.width, y: rect.height)
            )
        )
        // Bottom-right vignette for depth.
        let vignette = Gradient(stops: [
            .init(color: .black.opacity(0), location: 0),
            .init(color: .black.opacity(0.20), location: 1)
        ])
        ctx.fill(
            Path(rect),
            with: .linearGradient(
                vignette,
                startPoint: CGPoint(x: rect.midX, y: rect.midY),
                endPoint: CGPoint(x: rect.width, y: rect.height)
            )
        )
    }
}

// MARK: - Seeded RNG

/// Deterministic `RandomNumberGenerator` so texture patterns stay identical
/// across app launches for the same binder. Uses xorshift64* — fast, no
/// allocations, uniform enough for visual noise.
private struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: Int) {
        // Mix the seed with the SplitMix constant to avoid a zero state and
        // to diffuse small seeds (e.g. 0, 1, 2) into widely different streams.
        let mixed = UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9_7F4A_7C15
        state = mixed == 0 ? 0x9E37_79B9_7F4A_7C15 : mixed
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2_685_821_657_736_338_717
    }
}

// MARK: - Convenience constructors

extension BinderTextureView {
    /// Convenience initialiser that pulls colour/texture/seed from a ``Binder``.
    init(binder: Binder, compact: Bool = false) {
        self.init(
            baseColour: binder.resolvedColour,
            texture: binder.textureKind,
            seed: binder.textureSeed,
            compact: compact
        )
    }

    /// Preview-style initialiser for create/edit sheets where the user is
    /// tweaking colour and texture before a binder exists.
    init(
        colourName: String,
        texture: BinderTexture,
        seed: Int = 1,
        compact: Bool = false
    ) {
        self.init(
            baseColour: BinderColourPalette.color(named: colourName),
            texture: texture,
            seed: seed,
            compact: compact
        )
    }
}
