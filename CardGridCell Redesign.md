# CardGridCell Redesign

## Overview
Redesign the browse card grid so each card displays its name **inside** the card tile (above the image), with set name and price in a footer strip below the image. Owned cards get a solid accent-coloured border.

---

## New CardGridCell Structure

```swift
struct CardGridCell: View {
    let card: Card
    var gridOptions = BrowseGridOptions()
    var setName: String? = nil
    var isOwned = false
    var isWishlisted = false
    var footnote: String? = nil
    var overridePrice: Double? = nil
    var gradeLabel: String? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var tileBackground: Color {
        colorScheme == .dark ? .black : .white
    }

    private var tileBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    private var insetBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02)
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── 1. Name header ──────────────────────────────────
            if gridOptions.showCardName {
                Text(card.cardName)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 8)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 1)
                    }
            }

            // ── 2. Card image ───────────────────────────────────
            BrowseCardThumbnailView(
                imageURL: AppConfiguration.imageURL(relativePath: card.imageLowSrc),
                isOwned: isOwned,
                isWishlisted: isWishlisted
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(5/7, contentMode: .fit)

            // ── 3. Details footer ───────────────────────────────
            VStack(spacing: 3) {
                if gridOptions.showSetName, let setName, !setName.isEmpty {
                    Text(setName)
                        .font(.caption2)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                HStack(alignment: .center) {
                    if gridOptions.showPricing {
                        BrowseGridPriceText(
                            card: card,
                            overridePrice: overridePrice,
                            gradeLabel: gradeLabel
                        )
                        // Tint price with accent colour
                        // (pass accentColor in from environment or parent if needed)
                    }
                    Spacer(minLength: 0)
                    if gridOptions.showSetID {
                        Text(card.setCode)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(insetBackground)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
            }
        }
        .background(tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isOwned
                        ? AnyShapeStyle(services.theme.accentColor)  // solid accent border for owned
                        : AnyShapeStyle(tileBorder),                 // subtle border otherwise
                    lineWidth: isOwned ? 1.5 : 1
                )
        )
    }
}
```

---

## Key Design Decisions

| Element | Before | After |
|---|---|---|
| Card name | Below image | Inside tile, above image, centred |
| Set name | Below name (outside tile) | Inside tile footer, centred |
| Price | Below set name | Inside tile footer, left-aligned, accent colour |
| Card number | Not shown by default | Inside tile footer, right-aligned, tertiary |
| Tile shape | No background/border | Rounded rect (r=18), card background + border |
| Owned state | ✅ badge only | ✅ badge + solid accent-coloured border |
| Wishlisted state | ⭐ badge only | ⭐ badge only (no border change) |

---

## Accent Colour on Price

To apply the user's chosen theme accent to the price text, pass the accent colour into `BrowseGridPriceText` or use an environment value:

```swift
// Option A — foregroundStyle modifier on the price view
BrowseGridPriceText(card: card, overridePrice: overridePrice, gradeLabel: gradeLabel)
    .foregroundStyle(services.theme.accentColor)

// Option B — environment key if BrowseGridPriceText is deeply nested
// Define a custom environment key for accentColor and read it inside BrowseGridPriceText
```

---

## Grid Spacing

No changes needed to `BrowseCardListView` column/spacing config — the tile styling is self-contained inside `CardGridCell`.

If you want slightly tighter spacing to account for the taller tile (name header adds ~30pt), reduce grid spacing from `12` to `10`:

```swift
Array(repeating: GridItem(.flexible(), spacing: 10), count: safeColumnCount)
// and LazyVGrid spacing: 10
```

---

## Files to Edit

- `Bindr/Features/Browse/BrowseView.swift` — `CardGridCell` struct (top of file)
- Optionally `BrowseGridPriceText` if you want accent tinting inside that component
