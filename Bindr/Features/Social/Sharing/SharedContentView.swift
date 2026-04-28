import SwiftUI

private struct SharedCardRow: Identifiable {
    let id: String
    let cardID: String
    let cardName: String
    let variantKey: String
    let quantity: Int
    let notes: String?
    let marketValue: Double?
}

struct SharedContentView: View {
    @Environment(AppServices.self) private var services

    let content: SharedContent

    @State private var cardsByID: [String: Card] = [:]
    @State private var isSendingWishlistMatch = false
    @State private var errorMessage: String?
    @State private var presentedCard: Card?

    private var rows: [SharedCardRow] {
        switch content.contentType {
        case .binder, .wishlist, .collection, .folder:
            return decodeRows(key: "items")
        case .deck:
            return decodeRows(key: "cards")
        case .pull:
            // Pulls store a single card at the top level of the payload
            // (`card_id` / `card_name` / `variant_key`) rather than under an
            // `items` array, so the generic `decodeRows` won't pick it up.
            // Reconstruct one row so friends viewing the pull see the actual
            // card and can tap through to its browse detail.
            return decodePullRow()
        case .dailyDigest:
            return decodeRows(key: "items")
        }
    }

    var body: some View {
        // Binders get a dedicated read-only binder view that reproduces the
        // playmat surface and grid the publisher sees in BinderDetailView.
        // Everything else (wishlist, deck, pull, daily digest, folder) keeps
        // the list rendering — those payloads are inherently list-shaped.
        if content.contentType == .binder {
            SharedBinderView(content: content)
        } else {
            listBody
        }
    }

    private var listBody: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(content.title)
                        .font(.headline)
                    if let description = content.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        labelPill(
                            title: content.contentType.rawValue.capitalized,
                            systemImage: "rectangle.stack.fill"
                        )
                        labelPill(
                            title: content.visibility == .friends ? "Friends" : "Link",
                            systemImage: content.visibility == .friends ? "person.2.fill" : "link"
                        )
                        if content.includeValue {
                            labelPill(title: "Value on", systemImage: "dollarsign.circle")
                        }
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)

            Section("Cards") {
                if rows.isEmpty {
                    Text("No cards were published in this snapshot.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { row in
                        // Tap a row to open the same browse detail screen we
                        // use everywhere else in the app — but only when the
                        // catalog has actually resolved a Card for this row.
                        // Without the resolved card, opening would show an
                        // empty detail page.
                        Button {
                            if let card = cardsByID[row.cardID] {
                                presentedCard = card
                            }
                        } label: {
                            sharedRow(row)
                        }
                        .buttonStyle(.plain)
                        .disabled(cardsByID[row.cardID] == nil)
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(content.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadCards()
        }
        .sheet(item: $presentedCard) { card in
            // Reuse the standard browse detail screen so the experience matches
            // tapping a card from the Browse tab — same chrome, same actions.
            CardBrowseDetailView(cards: [card], startIndex: 0)
                .environment(services)
        }
    }

    private func sharedRow(_ row: SharedCardRow) -> some View {
        HStack(spacing: 12) {
            cardThumbnail(cardID: row.cardID)
            VStack(alignment: .leading, spacing: 3) {
                Text(resolvedName(for: row))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(row.variantKey) • Qty \(row.quantity)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let notes = row.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let marketValue = row.marketValue {
                    Text("Market value: \(services.priceDisplay.currency.format(amountUSD: marketValue, usdToGbp: services.pricing.usdToGbp))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if content.contentType == .wishlist {
                Button {
                    Task { await sendWishlistMatch(for: row) }
                } label: {
                    if isSendingWishlistMatch {
                        ProgressView()
                    } else {
                        Label("I have this", systemImage: "checkmark.circle")
                            .labelStyle(.iconOnly)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isSendingWishlistMatch)
            }
        }
        .padding(.vertical, 2)
    }

    private func cardThumbnail(cardID: String) -> some View {
        let imageURL = cardsByID[cardID].map { AppConfiguration.imageURL(relativePath: $0.imageLowSrc) }
        return CachedAsyncImage(url: imageURL, targetSize: CGSize(width: 80, height: 112)) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
        }
        .frame(width: 40, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func resolvedName(for row: SharedCardRow) -> String {
        if !row.cardName.isEmpty {
            return row.cardName
        }
        return cardsByID[row.cardID]?.cardName ?? row.cardID
    }

    private func sendWishlistMatch(for row: SharedCardRow) async {
        isSendingWishlistMatch = true
        defer { isSendingWishlistMatch = false }
        do {
            try await services.socialShare.sendWishlistMatch(contentID: content.id, cardID: row.cardID, variantKey: row.variantKey)
            errorMessage = nil
            HapticManager.notification(.success)
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.notification(.error)
        }
    }

    private func loadCards() async {
        var resolved: [String: Card] = [:]
        for row in rows {
            guard resolved[row.cardID] == nil else { continue }
            if let card = await services.cardData.loadCard(masterCardId: row.cardID) {
                resolved[row.cardID] = card
            }
        }
        cardsByID = resolved
    }

    /// Builds a single ``SharedCardRow`` from a pull payload. Pulls flatten the
    /// card into the payload root (`card_id`, `card_name`, `variant_key`)
    /// rather than the `items` array used by binders/wishlists, so they need
    /// their own decoder. Returns an empty array when the payload has no card
    /// id (e.g. malformed legacy posts).
    private func decodePullRow() -> [SharedCardRow] {
        guard let cardID = content.payload["card_id"]?.stringValue, !cardID.isEmpty else {
            return []
        }
        let cardName = content.payload["card_name"]?.stringValue ?? ""
        let variant = content.payload["variant_key"]?.stringValue ?? "normal"
        let marketValue: Double?
        if case .number(let value) = content.payload["card_value"] {
            marketValue = value
        } else {
            marketValue = nil
        }
        return [
            SharedCardRow(
                id: "\(cardID)|\(variant)",
                cardID: cardID,
                cardName: cardName,
                variantKey: variant,
                quantity: 1,
                notes: nil,
                marketValue: marketValue
            )
        ]
    }

    private func decodeRows(key: String) -> [SharedCardRow] {
        guard let rootRows = content.payload[key] else { return [] }
        guard case .array(let entries) = rootRows else { return [] }

        return entries.compactMap { value in
            guard case .object(let object) = value else { return nil }
            let cardID = object["cardID"]?.stringValue ?? ""
            let variant = object["variantKey"]?.stringValue ?? "normal"
            let name = object["cardName"]?.stringValue ?? ""
            let qty: Int
            if case .some(.number(let rawQty)) = object["quantity"] {
                qty = Int(rawQty)
            } else {
                qty = 1
            }
            let notes = object["notes"]?.stringValue
            let marketValue: Double?
            switch object["market_value_usd"] {
            case .number(let value):
                marketValue = value
            default:
                marketValue = nil
            }
            return SharedCardRow(
                id: "\(cardID)|\(variant)|\(qty)|\(name)",
                cardID: cardID,
                cardName: name,
                variantKey: variant,
                quantity: max(1, qty),
                notes: notes,
                marketValue: marketValue
            )
        }
    }

    private func labelPill(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
    }
}
