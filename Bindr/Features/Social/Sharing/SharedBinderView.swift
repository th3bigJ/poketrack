import SwiftUI

/// Read-only rendering of a friend's shared binder.
///
/// Mirrors the look of ``BinderDetailView``'s page surface — a textured
/// playmat background derived from the publisher's colour/texture/seed, with
/// the cards laid out on top in a 3-column grid. Tapping a card opens the
/// standard browse detail screen so the experience matches viewing a card
/// anywhere else in the app.
///
/// Used by ``SharedContentView`` whenever the shared content is a binder. For
/// other content types (wishlist, deck, pull, etc.) the original list-style
/// renderer is still appropriate because a list is what those callers
/// actually produce.
struct SharedBinderView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    let content: SharedContent

    @State private var cardsByID: [String: Card] = [:]
    @State private var presentedCard: Card?

    private struct BinderCardEntry: Identifiable {
        let id: String
        let cardID: String
        let cardName: String
        let variantKey: String
    }

    /// Decoded binder slots in publish order. Empty when the publisher's
    /// payload was malformed or the binder genuinely had no cards.
    private var entries: [BinderCardEntry] {
        guard case .array(let raw)? = content.payload["items"] else { return [] }
        return raw.enumerated().compactMap { offset, value in
            guard case .object(let object) = value else { return nil }
            let cardID = object["cardID"]?.stringValue ?? ""
            guard !cardID.isEmpty else { return nil }
            return BinderCardEntry(
                id: "\(offset)|\(cardID)",
                cardID: cardID,
                cardName: object["cardName"]?.stringValue ?? "",
                variantKey: object["variantKey"]?.stringValue ?? "normal"
            )
        }
    }

    private var colourName: String {
        let raw = content.payload["colour"]?.stringValue ?? ""
        return raw.isEmpty ? "navy" : raw
    }

    private var texture: BinderTexture {
        guard let raw = content.payload["texture"]?.stringValue,
              let value = BinderTexture(rawValue: raw) else {
            return .smooth
        }
        return value
    }

    /// Texture seed from the publisher. Falls back to a stable default so the
    /// pattern is at least deterministic if the payload is missing the field.
    private var seed: Int {
        if case .number(let value)? = content.payload["seed"] {
            return Int(value)
        }
        return 1
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                titleHeader
                binderSurface
                if entries.isEmpty {
                    Text("No cards in this binder yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            }
            .padding(.vertical, 16)
        }
        .navigationTitle(content.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemBackground))
        .task {
            await loadCards()
        }
        .sheet(item: $presentedCard) { card in
            // Reuse the standard browse detail screen so tapping a card here
            // matches tapping a card anywhere else in the app.
            CardBrowseDetailView(cards: [card], startIndex: 0)
                .environment(services)
        }
    }

    private var titleHeader: some View {
        VStack(spacing: 8) {
            Text(content.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            if let description = content.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Capsule()
                .fill(BinderColourPalette.color(named: colourName))
                .frame(width: 40, height: 3)
                .opacity(0.8)
        }
        .padding(.horizontal, 16)
    }

    /// Playmat surface with the cards laid out on top. Sized intrinsically to
    /// the grid's natural height — the texture sits behind the grid via
    /// `.background`, so the surface grows with the card count without
    /// needing a GeometryReader or hard-coded height.
    private var binderSurface: some View {
        let surfaceRadius: CGFloat = 22
        let cols = 3
        let slotSpacing: CGFloat = 8

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: slotSpacing), count: cols),
            spacing: slotSpacing
        ) {
            ForEach(entries) { entry in
                cardCell(entry: entry)
                    .aspectRatio(5/7, contentMode: .fit)
            }
        }
        .padding(14)
        .background {
            // Same base as BinderDetailView: textured playmat (forced to
            // `.linen`) with a subtle dark wash and radial vignette so cards
            // pop against the surface.
            ZStack {
                BinderTextureView(
                    colourName: colourName,
                    texture: .linen,
                    seed: seed,
                    compact: false
                )
                Color.black.opacity(0.22)
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: .black.opacity(0), location: 0.0),
                        .init(color: .black.opacity(0.14), location: 0.6),
                        .init(color: .black.opacity(0.30), location: 1.0)
                    ]),
                    center: .center,
                    startRadius: 40,
                    endRadius: 360
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: surfaceRadius, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: surfaceRadius, style: .continuous)
                .stroke(Color.black.opacity(0.55), lineWidth: 6)
                .blur(radius: 5)
                .mask(RoundedRectangle(cornerRadius: surfaceRadius, style: .continuous))
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: surfaceRadius, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func cardCell(entry: BinderCardEntry) -> some View {
        let card = cardsByID[entry.cardID]
        let imageURL = card.map { AppConfiguration.imageURL(relativePath: $0.imageLowSrc) }

        Button {
            if let card { presentedCard = card }
        } label: {
            ZStack(alignment: .topTrailing) {
                CachedAsyncImage(url: imageURL, targetSize: CGSize(width: 220, height: 308)) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(uiColor: .systemGray5))
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                // Inset top highlight — same trick BinderDetailView uses to
                // suggest light catching the card edge.
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .inset(by: 0.5)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(card == nil)
    }

    private func loadCards() async {
        var resolved: [String: Card] = [:]
        for entry in entries {
            guard resolved[entry.cardID] == nil else { continue }
            if let card = await services.cardData.loadCard(masterCardId: entry.cardID) {
                resolved[entry.cardID] = card
            }
        }
        cardsByID = resolved
    }
}
