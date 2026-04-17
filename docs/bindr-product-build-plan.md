# Bindr — Product Build Plan

---

## Project Snapshot

This is the single planning document for the next major Bindr product build. It intentionally covers three linked epics:

- Part A: local app structure, binders, decks, and dashboard
- Part B1: social identity, friends, sharing, and feed
- Part B2: trading, ledger execution, and release hardening

The plan is phased so AI can build, test, and gate each slice before moving on. Trading remains the highest-risk area and should not block Part A or early social work.

## V1 Scope Guardrails

- Trading is limited to `single cards + cash top-up`.
- Graded slabs and sealed-product trading are deferred to V2.
- Shared payloads are versioned from day one with `payload_version`.
- Trade execution uses both local and remote idempotency.
- Social must remain usable even if CloudKit is degraded.
- Abuse/privacy controls must be built into friendship, sharing, comments, and trade access.

## Known Design Risks

- Trade inventory locking must prevent offering cards that are no longer truly available.
- Share deletion/unpublish behavior must be defined clearly.
- Pagination is required for feed, comments, friends, and trades.
- Observability is needed for sync failures, push failures, and trade execution failures.
- Mock/test fixtures are needed so the app can be verified without relying on live backend state.

## Open Questions

- Should a true public share mode exist later beyond the authenticated `link` visibility in V1?
- If public sharing is added later, should it be read-only public profiles, public share links, or both?

## Locked Decisions

- Usernames are immutable once chosen during first social setup.
- `link` visibility still requires authentication in V1.
- Free-tier friend limits count both `pending` and `accepted` relationships.
- Blocking a user also unfriends them, hides shared content from both sides, and cancels any open trades between the two accounts.
- Notification preferences are included in V1.
- Comments are enabled on binders and decks only.
- `collection_stats` is private user-facing data and is not a shared content type in V1.
- Social remains usable when iCloud is degraded; local device data is used as the source of truth when needed.
- Trade revision history is included in V1 using full item snapshots per revision.
- Blocked users' old comments and reactions are removed from visibility immediately.
- Comments support replies/threads in V1.
- Account deletion/export can wait, but completed trades should retain anonymized audit records later.
- `collection_stats` may also power private recommendation features later without becoming a shared social post.
- Friend discovery supports partial username search.
- “I have this” is separate from trade flow and should not auto-start a trade.
- Trade chat/messages are included in V1.
- Avatar storage should use Cloudflare R2, not Supabase Storage.

## Immediate Follow-Up Rules

- Because usernames are immutable, users must choose them during first social setup and they should not require alias/redirect handling in V1.
- Since authenticated access is required even for `link` visibility, all share-entry deep links must route through auth/session restoration first.
- Friend-limit checks should run before creating a pending request, not only before accepting one.
- Blocking must be treated as a cross-cutting system action touching friendships, shared-content visibility, feed access, and trade eligibility.
- Notification preferences need a schema/home in the backend plan before feed/trade push work begins.
- Threaded comments require parent/child comment support and UI depth limits to be defined before implementation.
- Social features should continue working when CloudKit is unavailable, but trade and share flows must clearly communicate when they are operating against local-only collection state.
- “I have this” should create a lightweight social signal that can later branch into trade if the user chooses.
- Trade chat should be scoped to the trade itself rather than becoming a general-purpose DM system.
- Avatar upload/signing/caching rules should be planned against Cloudflare R2 before profile media work begins.

# Part A: Bindrs, Deck Builder & Navigation Restructure

## Context

The app currently has 5 tabs: Dashboard, Browse, Wishlist, Collection, Bindrs (placeholder). Three fully new features need to be added: a real Binder organiser, a Deck Builder, and a Social hub (placeholder for now). To fit all of these without exceeding 5 tab-bar items, we restructure navigation using Option A: keep 5 tabs but replace the Wishlist tab with Social, and move Wishlist + Deck Builder into the existing slide-out side menu. The Bindrs tab becomes the real binder organiser. A Social tab placeholder is added (full social build is a later phase).

### Build Order
1. Data models (`BinderModels.swift`, `DeckModels.swift`)
2. Add new models to `BindrApp.makeModelContainer()` Schema
3. Navigation restructure (`AppTab` → `SideMenuSheet` → `SideMenuView` → `RootView`)
4. Binder views (`CreateBinderSheet` → `BindersRootView` → `BinderDetailView` → `BinderSlotPickerView`)
5. Deck views (`CreateDeckSheet` → `DecksRootView` → `DeckDetailView` → `DeckCardPickerView`)
6. Dashboard (`DashboardView` replacing `DashboardPlaceholderView`)
7. Social placeholder tab view
8. Wire everything into `RootView`

---

## Step 1 — Navigation Restructure

### New tab layout (5 tabs)

| Tab | Was | Now |
|---|---|---|
| Dashboard | Placeholder | Unchanged |
| Browse | Cards | Unchanged |
| Collection | Collection | Unchanged |
| Bindrs | Community placeholder | Real Binder organiser |
| Social | — (new) | Social placeholder |

Wishlist and Deck Builder move to the side menu as `fullScreenCover` sheets.

### `Features/Root/AppTab.swift`
- Remove `.wishlist` case
- Add `.social` case with title `"Social"` and symbol `"person.2.fill"`
- Keep `.bindrs` unchanged

```swift
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case dashboard, browse, collection, bindrs, social
}
```

### `Features/Root/SideMenuSheet.swift`
Add two new cases:

```swift
enum SideMenuSheet: String, Identifiable {
    case account, transactions, wishlist, decks

    var title: String { /* "Account", "Transactions", "Wishlist", "Deck Builder" */ }
}
```

### `Features/Menu/SideMenuView.swift`
- Remove Wishlist row that did `selectedTab = .wishlist`
- Add Wishlist row: `presentedSheet = .wishlist` (icon: `"star"`, subtitle: `"Cards you want to collect"`)
- Add Deck Builder row: `presentedSheet = .decks` (icon: `"rectangle.on.rectangle.angled"`, subtitle: `"Build and manage decks"`)
- Add Social row: `selectedTab = .social` (icon: `"person.2"`, subtitle: `"Friends, trades and activity"`)
- Update Bindrs row subtitle to `"Your card binders"`
- Insert Wishlist + Deck Builder rows in the main nav section (after Collection, before Transactions)

### `Features/Root/RootView.swift`
- Remove `case .wishlist:` block from `TabView ForEach`
- Replace `case .bindrs: BindrsPlaceholderView()` with `case .bindrs: NavigationStack { BindersRootView() }`
- Add `case .social: NavigationStack { SocialRootView() }`
- In `fullScreenCover(item: $sideMenuSheet)` switch, add:
  ```swift
  case .wishlist: NavigationStack { WishlistView() }
  case .decks:    NavigationStack { DecksRootView() }
  ```
- Update safeAreaInset "Done" label to use `destination.title`
- Keep `services.setupWishlist(modelContext:)` in `.onAppear` — unchanged
- Remove `chromeScroll.configureForTab` call for `.wishlist`

### `Features/Root/PlaceholderTabViews.swift`
- Delete `BindrsPlaceholderView` struct (no longer used)
- Keep `DashboardPlaceholderView`

---

## Step 2 — Binder Data Models

**New file:** `Bindr/Models/BinderModels.swift`

```swift
enum BinderPageLayout: String, Codable, CaseIterable {
    case nineSlot   = "nineSlot"    // 3×3, 9 cards per page
    case twelveSlot = "twelveSlot"  // 4×3, 12 cards per page
    case freeScroll = "freeScroll"  // scrollable grid, no pages

    var displayName: String { /* "3×3 Pages", "4×3 Pages", "Free Scroll" */ }
    var slotsPerPage: Int? { /* 9, 12, nil */ }
    var columns: Int { /* 3, 4, 3 */ }
}

@Model final class Binder {
    var id: UUID
    var title: String
    var pageLayout: String          // BinderPageLayout.rawValue
    var colour: String              // SwiftUI Color name or hex — used as cover in grid
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \BinderSlot.binder)
    var slots: [BinderSlot] = []
}

@Model final class BinderSlot {
    var position: Int               // sort key; gaps allowed for empty slots
    var cardID: String
    var variantKey: String
    var cardName: String
    var binder: Binder?
    // Any card from the catalog can be slotted; owned status is checked at display time
}
```

Add to `BindrApp.makeModelContainer()` Schema: `Binder.self, BinderSlot.self`

---

## Step 3 — Deck Data Models

**New file:** `Bindr/Models/DeckModels.swift`

```swift
// Format rules:
// Pokémon:   60 cards total, max 4 copies per card name (basic energy exempt)
// One Piece: 50 cards total, max 4 copies (Leader card treated separately)
// Lorcana:   60 cards total, max 4 copies per card name

enum DeckFormat: String, Codable {
    case pokemonStandard  = "Standard"
    case pokemonExpanded  = "Expanded"
    case pokemonUnlimited = "Unlimited"
    case onePiece         = "Standard"
    case lorcana          = "Standard"

    var deckSize: Int { /* 60 except onePiece = 50 */ }
    var maxCopiesPerCard: Int { 4 }
}

@Model final class Deck {
    var id: UUID
    var title: String
    var brand: String               // TCGBrand.rawValue
    var format: String              // DeckFormat.rawValue
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \DeckCard.deck)
    var cards: [DeckCard] = []
}

@Model final class DeckCard {
    var cardID: String
    var variantKey: String
    var cardName: String
    var quantity: Int
    var deck: Deck?
}
```

Validation computed on `Deck`:
```swift
var validationIssues: [String] { /* total count, max copies, basic energy exemption */ }
var isValid: Bool { validationIssues.isEmpty }
```

Add to `BindrApp.makeModelContainer()` Schema: `Deck.self, DeckCard.self`

---

## Step 4 — Binder Views

All new files under `Bindr/Features/Bindrs/`.

**`BindersRootView.swift`**
- `@Query(sort: \Binder.createdAt, order: .reverse)` all binders
- Grid of binder cards: title, layout badge, slot count
- Toolbar trailing `+` → `showCreateSheet = true`
- Free-tier gate: if `!services.store.isPremium && binders.count >= 1` → `PaywallSheet`
- Empty state: `ContentUnavailableView` with "Create a Binder" button
- Swipe-to-delete with confirmation
- Tap → `BinderDetailView(binder:)`

**`CreateBinderSheet.swift`**
- Text field: binder name (required)
- Layout picker: `.segmented` style, `BinderPageLayout.allCases`
- Colour picker: small swatch row (e.g. red/orange/yellow/green/blue/purple/pink/grey). Stored as a named string on `Binder.colour`.
- "Create" button: inserts `Binder` into `modelContext`, dismisses

**`BindersRootView.swift` — cover display**
- Each binder card in the grid shows a coloured background (from `binder.colour`) with the title and layout badge overlaid. No card image dependency.

**`BinderDetailView.swift`**
- Navigation title = binder name (editable inline)
- Paged layout (nineSlot / twelveSlot): `TabView` with `.tabViewStyle(.page)`, each page a `LazyVGrid`
- Free scroll layout: single `LazyVGrid` with 3 adaptive columns
- Drag-to-reorder: `.draggable` / `.dropDestination` (iOS 16+) — swap `BinderSlot.position` values
- Slot cell: filled = `CachedAsyncImage`; empty = dashed `RoundedRectangle` + `"plus"` icon
- Owned indicator: small green checkmark badge on slots where `cardID` exists in a `CollectionItem`. Cards NOT in collection show a grey `"questionmark.circle"` badge.
- Tap (filled or empty) → `BinderSlotPickerView`
- Long press filled slot → context menu "Remove from Binder"
- Toolbar: "Add Page" (paged layouts only), edit/done toggle

**`BinderSlotPickerView.swift`**
- Sheet, `.presentationDetents([.large])`
- Search bar + `LazyVGrid` of `CardGridCell` (reuse existing component)
- Queries `services.cardData` catalog — any card can be added (not restricted to owned)
- Owned cards get a green checkmark badge overlay (cross-ref `CollectionItem`); unowned cards show no badge
- Tap → fills/replaces the target `BinderSlot`, dismisses

---

## Step 5 — Deck Views

All new files under `Bindr/Features/Decks/`.

**`DecksRootView.swift`**
- `@Query(sort: \Deck.createdAt, order: .reverse)` all decks
- Brand filter: segmented Picker (All / Pokémon / One Piece / Lorcana)
- List rows: name, brand colour badge, format label, card count, legality dot (green/amber/red)
- Toolbar `+` → `showCreateSheet = true`
- Free-tier gate: if `!services.store.isPremium && decks.count >= 1` → `PaywallSheet`
- Swipe-to-delete with confirmation
- Tap → `DeckDetailView(deck:)`

**`CreateDeckSheet.swift`**
- Name field (required)
- Brand picker: `services.brandSettings.enabledBrands`
- Format picker: populated by brand (Pokémon → Standard/Expanded/Unlimited; One Piece / Lorcana → Standard only)
- "Create" button: inserts `Deck`, dismisses

**`DeckDetailView.swift`**
- Navigation title = deck name (editable inline)
- Header bar: `"XX / YY"` card count, format badge, legality status (from `deck.validationIssues`)
- Card list: `List` sectioned by category (Pokémon/Trainer/Energy for Pokémon; single section for others)
- Each row: thumbnail, card name, quantity label, stepper (– / +), owned badge
- Stepper max = 4 (unlimited for basic Pokémon energy); `+` disabled at max
- Owned badge: cross-ref `@Query` on `CollectionItem` — "✓ Owned" or "Need N"
- Toolbar: "Add Cards" → `DeckCardPickerView`, Share button → export
- Export: plain `"Qty x Card Name"` text list via `ShareLink` (works for all brands — Pokémon, One Piece, Lorcana)

**`DeckCardPickerView.swift`**
- Sheet, `.large` detent
- Brand-filtered catalog search (locked to `deck.brand`)
- "In deck: N" badge on already-added cards
- Tap → quantity picker popover (1–4, or 1–∞ for basic energy)
- "Add" inserts/updates `DeckCard`; "Done" dismisses

---

## Step 6 — Dashboard

Replace `DashboardPlaceholderView` with a real `DashboardView`.

**New file:** `Bindr/Features/Dashboard/DashboardView.swift`

Four sections, each a card/widget in a `ScrollView`:

1. **Collection Value & P&L** — pull from `CollectionLedgerService`: total market value (via `PricingService`), total cost basis, overall gain/loss in £ and %. Tapping → `TransactionsView` (existing full-screen cover).

2. **Recent Activity** — last 10 `LedgerLine` entries sorted by date. Each row: direction icon (bought/traded/packed etc.), card name, quantity, date. Tapping a row → card detail (reuse existing card detail sheet).

3. **Wishlist Progress** — count of wishlist items owned vs. total. E.g. "12 / 30 acquired". Progress bar. Tapping → `WishlistView` (opens as sheet via `SideMenuSheet.wishlist`).

4. **Set Completion Highlights** — top 3 sets by completion % (owned / total cards in that set). Progress bar per set with set name. Tapping a set → `BrowseView` filtered to that set.

**Data sources:**
- Market value: `PricingService` (already used in Collection tab)
- Ledger lines: `@Query` on `LedgerLine` sorted by date, limit 10
- Wishlist: `WishlistService` (already set up in `.onAppear`)
- Set completion: compute from `CollectionItem` cross-referenced with `services.cardData` set metadata

**`Features/Root/RootView.swift` change:** replace `case .dashboard: DashboardPlaceholderView()` with `case .dashboard: NavigationStack { DashboardView() }`

---

## Step 7 — Social Placeholder Tab

**New file:** `Bindr/Features/Social/SocialRootView.swift`

```swift
struct SocialRootView: View {
    var body: some View {
        ContentUnavailableView(
            "Social",
            systemImage: "person.2",
            description: Text("Friends, trades and activity feed coming soon.")
        )
        .navigationTitle("Social")
    }
}
```

This is replaced wholesale in Part B.

---

## Step 8 — Premium Gating Summary

| Feature | Free | Premium |
|---|---|---|
| Binders | 1 binder | Unlimited |
| Decks | 1 deck | Unlimited |
| Wishlist | 5 items (existing) | Unlimited (existing) |

Gate check pattern (matches existing `WishlistService` pattern):
```swift
if !services.store.isPremium && existingCount >= limit {
    showPaywall = true
    return
}
```

---

## Part A — Files Modified / Created

### Modified
| File | Change |
|---|---|
| `Features/Root/AppTab.swift` | Remove `.wishlist`, add `.social` |
| `Features/Root/SideMenuSheet.swift` | Add `.wishlist`, `.decks` (+ `title` var) |
| `Features/Menu/SideMenuView.swift` | Add Wishlist, Deck Builder, Social rows; remove Wishlist tab nav |
| `Features/Root/RootView.swift` | Update tab routing; add wishlist/decks to sheet handler |
| `Features/Root/PlaceholderTabViews.swift` | Remove `BindrsPlaceholderView` |
| `BindrApp.swift` | Add `Binder`, `BinderSlot`, `Deck`, `DeckCard` to Schema |

### Created
| File | Purpose |
|---|---|
| `Bindr/Models/BinderModels.swift` | `Binder`, `BinderSlot`, `BinderPageLayout` |
| `Bindr/Models/DeckModels.swift` | `Deck`, `DeckCard`, `DeckFormat`, validation logic |
| `Bindr/Features/Bindrs/BindersRootView.swift` | Binder list with paywall gate |
| `Bindr/Features/Bindrs/CreateBinderSheet.swift` | Name + layout creation sheet |
| `Bindr/Features/Bindrs/BinderDetailView.swift` | Paged/free-scroll binder grid with drag-to-reorder |
| `Bindr/Features/Bindrs/BinderSlotPickerView.swift` | Card catalog picker for filling slots |
| `Bindr/Features/Decks/DecksRootView.swift` | Deck list with brand filter and paywall gate |
| `Bindr/Features/Decks/CreateDeckSheet.swift` | Name + brand + format creation sheet |
| `Bindr/Features/Decks/DeckDetailView.swift` | Card list with validation, owned cross-ref, export |
| `Bindr/Features/Decks/DeckCardPickerView.swift` | Card catalog picker for adding to deck |
| `Bindr/Features/Social/SocialRootView.swift` | Placeholder (replaced in Part B) |
| `Bindr/Features/Dashboard/DashboardView.swift` | Collection value, recent activity, wishlist progress, set completion |

---

## Part A — Verification Checklist

- [ ] Tab bar shows exactly 5 items: Dashboard, Browse, Collection, Bindrs, Social
- [ ] Side menu has Wishlist row (opens `WishlistView` as `fullScreenCover`) and Deck Builder row (opens `DecksRootView`)
- [ ] CloudKit: Binder and Deck data appears on a second device after sync delay
- [ ] Binder free tier: Creating a second binder on a free account shows the paywall sheet
- [ ] Binder creation: Name + layout choice → binder appears in `BindersRootView`
- [ ] Binder slot: Tapping empty slot → picker → selecting card fills the slot with card image
- [ ] Binder drag-to-reorder: Hold and drag a card cell; dropping in a new position persists after dismissal
- [ ] Owned badge: A card in both Collection and a binder slot shows the owned indicator
- [ ] Deck free tier: Creating a second deck on a free account shows paywall
- [ ] Deck validation (strict): Adding a 5th copy of a card disables the `+` stepper; total over deck size shows error in header
- [ ] Deck owned cross-ref: Cards in the user's Collection show "✓ Owned"; others show "Need N"
- [ ] Deck export: Share button produces correctly formatted deck list text
- [ ] Wishlist regression: Wishlist accessible from side menu works identically to before (add, remove, 5-item cap for free users)
- [ ] Dashboard: Collection value, cost basis and P&L display correctly using existing ledger + pricing data
- [ ] Dashboard: Recent activity shows last 10 ledger entries with correct direction icons
- [ ] Dashboard: Wishlist progress count matches WishlistService data
- [ ] Dashboard: Set completion highlights show top 3 sets by %; tapping navigates to Browse filtered to that set
- [ ] Existing CloudKit models: `WishlistItem`, `CollectionItem`, `LedgerLine`, `CostLot`, `SaleAllocation` unaffected by schema additions

---

# Part B: Social & Trading

## Context

Bindr is an iOS SwiftUI app using SwiftData + CloudKit for personal card collection data. This plan adds a social layer: friend profiles, content sharing (auto-synced from SwiftData), a live activity feed with reactions and comments, and a full peer-to-peer trading system. All personal financial data (purchase prices, P&L, cost basis) remains private and CloudKit-only. Supabase coordinates social identity, friend graph, shared content snapshots, and trade offers. Actual collection mutations always execute locally in `CollectionLedgerService` on each user's device.

---

## Key Decisions

| Decision | Choice |
|---|---|
| Friend model | Mutual — both must accept |
| Free tier friend limit | 1 friend (premium = unlimited) |
| Free tier content | Wishlist + 1 binder (premium = all types) |
| Discovery | Partial username search + QR code + `bindr://profile/@username` deep link (auth required) |
| Sharing trigger | Auto-sync ~30s after last SwiftData save |
| V1 content types | Wishlist, binders, decks |
| Financial privacy | Opt-in per share — market value toggle only, never purchase price |
| Feed | Pull-on-open + APNs push; reactions (like/fire/wow) + comments on binders/decks only |
| Trade items | V1 = single cards + cash top-up only |
| Trade structure | Multi-card both sides; counter-offers allowed (negotiate loop) |
| Trade ledger price | Market value from PricingService at time offer is created |
| "I have this" | User chooses: notify only OR auto-start trade offer |
| Trade expiry | None — trades stay open until one party declines/cancels. `expires_at` column omitted from schema. |
| Offline trade completion | App checks for `completed` trades on next foreground open (remote + local idempotency) |
| Social tab badge | Red dot on Social tab icon for unread feed items, pending friend requests, and trades requiring action |

---

## Existing Code to Reuse

| Asset | Location | How Used |
|---|---|---|
| `CollectionLedgerService.recordSingleCardAcquisition(kind: .trade)` | `Services/CollectionLedgerService.swift` | Records `tradedIn` leg when trade completes |
| `LedgerDirection.tradedIn / .tradedOut` | `CollectionLedgerModels.swift` | Trade ledger entries (`.tradedOut` needs a new service method) |
| `LedgerLine.transactionGroupId` | `CollectionLedgerModels.swift` | Groups the two legs of a trade |
| `LedgerLine.counterparty` | `CollectionLedgerModels.swift` | Stores friend's display name |
| `LedgerLine.channel = "trade"` | `CollectionLedgerModels.swift` | Channel tag |
| `KeychainStorage.saveAppleUserIdentifier` | `Services/KeychainStorage.swift` | Existing Apple ID — basis for Supabase identity link |
| `AppServices` | `Services/AppServices.swift` | Register all new social services alongside existing ones |
| `PricingService` | `Services/` | Look up market value at trade offer creation time |
| Card grid/list components | `Features/Browse/` | Reuse to render friend's shared content |
| `StoreKitService.isPremium` | `Services/StoreKitService.swift` | Check premium status for friend limit + content gates |

---

## New Service Method Required

`CollectionLedgerService` has no method for outgoing trades. Add:

```swift
func recordTradeOut(
    cardID: String,
    variantKey: String,
    quantity: Int,
    cardDisplayName: String,
    marketValue: Double?,
    currencyCode: String,
    counterparty: String,
    transactionGroupId: UUID
) throws
```

Mirrors the existing acquisition flow but uses `LedgerDirection.tradedOut`, FIFO-consumes cost lots, and links to the group ID.

---

## Supabase Schema

```sql
-- User profiles (linked to Supabase Auth via Apple Sign-In)
create table profiles (
  id             uuid primary key references auth.users,
  apple_user_id  text unique not null,
  username       text unique not null,
  display_name   text,
  avatar_url     text,
  bio            text,
  pinned_card_id text,
  created_at     timestamptz default now()
);

create table trade_messages (
  id         uuid primary key default gen_random_uuid(),
  trade_id   uuid references trade_offers(id) on delete cascade,
  author_id  uuid references profiles(id) on delete cascade,
  body       text not null,
  created_at timestamptz default now()
);

create table notification_preferences (
  user_id                      uuid primary key references profiles(id) on delete cascade,
  friend_requests              boolean default true,
  friend_accepts               boolean default true,
  shared_content_posts         boolean default true,
  comments                     boolean default true,
  wishlist_matches             boolean default true,
  trade_updates                boolean default true,
  marketing                    boolean default false,
  updated_at                   timestamptz default now()
);

-- APNs device tokens
create table device_tokens (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references profiles(id) on delete cascade,
  token      text not null,
  updated_at timestamptz default now(),
  unique(user_id, token)
);

-- Mutual friend graph
create table friendships (
  id           uuid primary key default gen_random_uuid(),
  requester_id uuid references profiles(id) on delete cascade,
  addressee_id uuid references profiles(id) on delete cascade,
  status       text check (status in ('pending', 'accepted', 'blocked')),
  created_at   timestamptz default now(),
  unique(requester_id, addressee_id)
);

-- Shared content snapshots (auto-synced)
create table shared_content (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid references profiles(id) on delete cascade,
  content_type  text check (content_type in ('binder', 'wishlist', 'deck', 'collection_stats')),
  title         text not null,
  description   text,
  visibility    text check (visibility in ('friends', 'link')) default 'friends',
  payload       jsonb not null,
  include_value boolean default false,
  card_count    int,
  brand         text,
  published_at  timestamptz default now(),
  updated_at    timestamptz default now()
);

-- Reactions
create table reactions (
  id            uuid primary key default gen_random_uuid(),
  content_id    uuid references shared_content(id) on delete cascade,
  user_id       uuid references profiles(id) on delete cascade,
  reaction_type text check (reaction_type in ('like', 'fire', 'wow')),
  created_at    timestamptz default now(),
  unique(content_id, user_id)
);

-- Comments
create table comments (
  id         uuid primary key default gen_random_uuid(),
  content_id uuid references shared_content(id) on delete cascade,
  author_id  uuid references profiles(id) on delete cascade,
  parent_id  uuid references comments(id) on delete cascade,
  body       text not null,
  created_at timestamptz default now()
);

-- Wishlist "I have this!" notifications
create table wishlist_matches (
  id         uuid primary key default gen_random_uuid(),
  content_id uuid references shared_content(id) on delete cascade,
  card_id    text not null,
  sender_id  uuid references profiles(id) on delete cascade,
  seen       boolean default false,
  created_at timestamptz default now()
);

-- Trade offers (header)
create table trade_offers (
  id                           uuid primary key default gen_random_uuid(),
  proposer_id                  uuid references profiles(id) on delete cascade,
  recipient_id                 uuid references profiles(id) on delete cascade,
  status                       text check (status in (
                                 'proposed', 'counter_proposed',
                                 'accepted', 'declined', 'cancelled', 'completed'
                               )) default 'proposed',
  last_modified_by             uuid references profiles(id),
  proposer_confirmed_complete  boolean default false,
  recipient_confirmed_complete boolean default false,
  proposer_executed_at         timestamptz,
  recipient_executed_at        timestamptz,
  message                      text,
  created_at                   timestamptz default now(),
  updated_at                   timestamptz default now()
);

create table trade_offer_revisions (
  id              uuid primary key default gen_random_uuid(),
  trade_id        uuid references trade_offers(id) on delete cascade,
  actor_id        uuid references profiles(id) on delete cascade,
  revision_number int not null,
  status_snapshot text not null,
  payload         jsonb not null,
  created_at      timestamptz default now(),
  unique(trade_id, revision_number)
);

-- Trade offer line items (both sides)
create table trade_offer_items (
  id                    uuid primary key default gen_random_uuid(),
  trade_id              uuid references trade_offers(id) on delete cascade,
  owner_id              uuid references profiles(id) on delete cascade,
  item_type             text check (item_type in ('card', 'cash')),
  card_id               text,
  variant_key           text,
  card_name             text,
  quantity              int,
  is_graded             boolean default false,
  grading_company       text,
  grade                 text,
  cash_amount           numeric(10,2),
  currency_code         text default 'GBP',
  market_value_snapshot numeric(10,2),
  created_at            timestamptz default now()
);
```

**RLS Policies:**
- `profiles`: readable by any authenticated user; writable by owner only
- `notification_preferences`: readable/writable by owner only
- `friendships`: visible to both parties; insert by anyone; update status by addressee only
- `shared_content` (friends): readable only when accepted friendship exists. Link visibility: any authenticated user with the UUID
- `reactions`, `comments`, `wishlist_matches`: readable/insertable by authenticated users with friend access to the parent content
- `comments` support threaded replies in V1; keep UI depth intentionally shallow even if storage supports arbitrary nesting
- `trade_offers`: visible to `proposer_id` and `recipient_id` only; status updates only by the counterparty whose turn it is (enforced via RLS + `last_modified_by` check)
- `trade_offer_items`: visible to both parties; items replaceable only during `proposed` / `counter_proposed` phases
- `trade_offer_revisions`: visible to both parties; append-only
- `trade_messages`: visible to both trade participants; insertable by both while the trade is active

**V1 trade scope note:** this schema now intentionally matches the implementation plan for card trading only. Graded slabs and sealed products should not be included in the first build unless separate item identity and ledger rules are added first.

**Block rule:** when either side blocks the other, friendship access is revoked immediately, shared content becomes inaccessible, and any non-completed trades between the pair must be cancelled server-side.

---

## Trade Flow

Two distinct stages — agreement first, collection update only after physical exchange is confirmed.

```
── Stage 1: Negotiation ──────────────────────────────────────────
Proposer builds offer → proposed
  ↓ Recipient views, wants changes
counter_proposed (last_modified_by = recipient)
  ↓ Proposer reviews counter, can counter again or accept
proposed / counter_proposed loop ...
  ↓ Recipient (or proposer after a counter) taps Accept
accepted  ← terms locked, NO collection changes yet

── Stage 2: Physical Exchange ────────────────────────────────────
Both users see "Items in transit" banner with "Mark as Received" button.
Each taps once they physically have the other party's cards.
proposer_confirmed_complete = true
recipient_confirmed_complete = true
  ↓ Both true → Supabase edge function sets status = completed
completed  ← collections + ledger updated on each device
```

**Counter-offer mechanics:** Items are replaced in-place when a counter is submitted, but each revision is also written to `trade_offer_revisions` as a full snapshot. `last_modified_by` indicates whose turn it is.

**Collection execution (each device independently):**

When `status = completed` is detected via APNs or next app foreground:
1. Check `UserDefaults` set `executedTradeIDs` — skip if already applied (idempotency guard)
2. Look up `trade_offer_items` where `owner_id = me` (what I gave away)
3. For each card: call `CollectionLedgerService.recordTradeOut(...)` with `market_value_snapshot` and shared `transactionGroupId`
4. Look up items where `owner_id = counterparty` (what I received)
5. For each card: call `CollectionLedgerService.recordSingleCardAcquisition(kind: .trade, ...)` with counterparty's `market_value_snapshot` as unit price
6. Mark the relevant `*_executed_at` column remotely and add the trade UUID to `executedTradeIDs` in `UserDefaults`

**Cash top-up ledger treatment:**
- If proposer includes cash: recorded as `feesAmount` on their `tradedOut` ledger entries
- If recipient includes cash: recorded as `feesAmount` on their `tradedOut` entries

---

## JSONB Payload Schemas

**Binder / Collection:**
```json
{ "brand": "pokemon", "items": [{ "cardID": "sv3pt5-001", "variantKey": "holofoil", "quantity": 2, "cardName": "Pikachu" }] }
```

**Wishlist:**
```json
{ "items": [{ "cardID": "sv3pt5-001", "variantKey": "normal", "cardName": "Pikachu", "notes": "Want PSA 10" }] }
```

**Deck:**
```json
{ "format": "Standard", "brand": "pokemon", "cards": [{ "cardID": "sv3pt5-001", "variantKey": "normal", "quantity": 4, "cardName": "Pikachu" }] }
```

**Add to every shared payload:** `payload_version`, `generated_at`, and stable owner/content identifiers so future app versions can safely deserialize older snapshots.

---

## New Files to Create

```
Bindr/Services/
├── SocialAuthService.swift          — Sign in with Apple → Supabase JWT; session restore
├── SocialProfileService.swift       — Profile CRUD, avatar upload to Cloudflare R2, APNs token registration
├── SocialFriendService.swift        — Friend requests, accept/decline/block, search, QR
├── SocialShareService.swift         — Serialize SwiftData → JSONB; 30s auto-sync debounce
├── SocialFeedService.swift          — Feed fetch (pull-on-open), reactions, binder/deck comments
└── SocialTradeService.swift         — Trade offer CRUD, counter-offer, chat, execution

Bindr/Models/
└── SocialModels.swift               — Codable structs for all Supabase tables

Bindr/Features/Social/
├── SocialRootView.swift             — Tab root: Feed / Friends / Trades navigation
├── Feed/
│   ├── FeedView.swift
│   ├── FeedItemView.swift
│   └── CommentsView.swift
├── Profile/
│   ├── MyProfileView.swift
│   ├── FriendProfileView.swift
│   └── EditProfileView.swift        — Username/avatar/bio setup (first social launch)
├── Friends/
│   ├── FriendsListView.swift
│   ├── FriendSearchView.swift
│   ├── FriendRequestView.swift
│   └── QRProfileView.swift          — Own QR (CIFilter) + AVFoundation scanner
├── Sharing/
│   ├── SharedContentView.swift      — Render any friend's binder/wishlist/deck
│   └── ShareSettingsView.swift      — Title, description, visibility, include_value toggle
└── Trading/
    ├── TradesListView.swift
    ├── TradeDetailView.swift
    ├── BuildTradeOfferView.swift
    ├── TradeItemPickerView.swift
    ├── TradeMessagesView.swift
    └── TradeCompletionView.swift
```

---

## Files to Modify

| File | Change |
|---|---|
| `Services/CollectionLedgerService.swift` | Add `recordTradeOut(...)` method |
| `Services/KeychainStorage.swift` | Add Supabase session JWT storage key |
| `Services/AppServices.swift` | Register all 6 new social services |
| `BindrApp.swift` | Call `SocialAuthService.restoreSession()` on launch; APNs token registration |
| `Features/Root/AppTab.swift` | Add `.social` case |
| `Features/Root/RootView.swift` | Wire `.social` tab to `SocialRootView` |
| Collection / Wishlist / Deck screens | Add sharing status indicator + `ShareSettingsView` sheet trigger |
| `Features/Account/` (settings) | Add "Social Profile" row → `EditProfileView` |

**Never touch:** `CollectionLedgerModels.swift`, `WishlistModels.swift`, CloudKit `ModelContainer` config.

---

## Build-Test Phased Plan

This section is the working delivery plan. Each phase should be built, manually verified, and checked off before the next phase starts.

### Phase 1 — Backend Contract Freeze

**Build**
- [ ] Create Supabase project/environment config for dev
- [ ] Write SQL migrations for `profiles`
- [ ] Write SQL migrations for `trade_messages`
- [ ] Write SQL migrations for `notification_preferences`
- [ ] Write SQL migrations for `device_tokens`
- [ ] Write SQL migrations for `friendships`
- [ ] Write SQL migrations for `shared_content`
- [ ] Write SQL migrations for `reactions`
- [ ] Write SQL migrations for `comments`
- [ ] Write SQL migrations for `wishlist_matches`
- [ ] Write SQL migrations for `trade_offers`
- [ ] Write SQL migrations for `trade_offer_items`
- [ ] Write SQL migrations for `trade_offer_revisions`
- [ ] Add RLS policies for each table
- [ ] Document deep-link routes and payload contracts
- [ ] Add `payload_version` rules to every shared payload type
- [ ] Document block/cancel side effects in backend rules
- [ ] Document comment threading rules and max UI depth

**Test**
- [ ] Migrations run cleanly on a fresh database
- [ ] RLS blocks non-friend access to `shared_content`
- [ ] RLS allows only owners to edit `notification_preferences`
- [ ] Block action rules are validated at the data level

**Gate**
- [ ] Backend schema and contracts are frozen for app integration

### Phase 2 — iOS Social Foundation

**Build**
- [ ] Add `supabase-swift` dependency
- [ ] Add app config for Supabase URL/keys
- [ ] Create `SocialModels.swift`
- [ ] Add social service placeholders to `AppServices`
- [ ] Extend `KeychainStorage` for Supabase session storage
- [ ] Add app-level session/bootstrap wiring plan in `BindrApp.swift`
- [ ] Create lightweight mock/test service implementations for local development

**Test**
- [ ] App compiles with social services wired but feature-gated
- [ ] No regression to existing launch flow, CloudKit store, or browse bootstrapping
- [ ] Mock services can drive preview/test UI without live backend

**Gate**
- [ ] Social foundation is merged and stable without user-facing functionality enabled

### Phase 3 — Auth And Session Restore

**Build**
- [ ] Implement `SocialAuthService`
- [ ] Add Sign in with Apple to Supabase token exchange
- [ ] Persist Supabase session in Keychain
- [ ] Restore session on cold launch
- [ ] Add sign-out/session-clear handling
- [ ] Handle deep links by routing through auth/session restore first

**Test**
- [ ] Fresh install can sign in successfully
- [ ] Relaunch restores the same session
- [ ] Sign-out clears social session cleanly
- [ ] Deep link while signed out routes through auth and resumes safely

**Gate**
- [ ] Auth/session flow is reliable enough for profile work

### Phase 4 — Profile Creation And Editing

**Build**
- [ ] Implement `SocialProfileService`
- [ ] Create/fetch `profiles` row on first social launch
- [ ] Create default `notification_preferences` row
- [ ] Build `EditProfileView`
- [ ] Add username validation and uniqueness checks
- [ ] Add immutable username setup flow
- [ ] Add avatar upload support via Cloudflare R2
- [ ] Add bio/display-name editing
- [ ] Add account/settings entry point to social profile

**Test**
- [ ] First social launch creates a profile successfully
- [ ] Username uniqueness errors are handled correctly
- [ ] Username remains fixed after setup
- [ ] Avatar/bio/profile edits persist across relaunch
- [ ] R2-backed avatar upload and display works reliably

**Gate**
- [ ] One user can fully create and maintain a social profile

### Phase 5 — Friend Graph Core

**Build**
- [ ] Implement `SocialFriendService.searchUsers`
- [ ] Implement `sendRequest`
- [ ] Implement `respond(accepted:)`
- [ ] Implement `fetchFriends`
- [ ] Implement `fetchPending`
- [ ] Enforce free-tier friend cap using both pending and accepted relationships
- [ ] Build `FriendsListView`
- [ ] Build `FriendSearchView`
- [ ] Build `FriendRequestView`

**Test**
- [ ] User A can find User B by username
- [ ] User A can send a friend request
- [ ] User B can accept or decline
- [ ] Free-tier cap blocks creating an extra pending request
- [ ] Accepted friends appear correctly for both users

**Gate**
- [ ] Friend relationship flow works end to end for two accounts

### Phase 6 — Blocking And Relationship Enforcement

**Build**
- [ ] Implement `block` flow in `SocialFriendService`
- [ ] Cancel open trades on block at the service/backend layer
- [ ] Remove friend access when blocked
- [ ] Hide shared content/feed visibility when blocked
- [ ] Prevent blocked users from sending requests or trade offers

**Test**
- [ ] Blocking immediately removes friend access
- [ ] Shared content is no longer accessible after block
- [ ] Open non-completed trades are cancelled on block
- [ ] Blocked users cannot re-request or interact

**Gate**
- [ ] Relationship safety rules are enforced before content sharing goes live

### Phase 7 — Discovery, QR, And Deep Links

**Build**
- [ ] Build `QRProfileView`
- [ ] Generate QR from current profile identity
- [ ] Add QR scanning flow
- [ ] Register `bindr://profile/@username` route
- [ ] Route deep links into the friend/profile flow

**Test**
- [ ] QR generation works for current user
- [ ] Scanning a valid QR opens the correct profile flow
- [ ] Username deep links open the correct current profile
- [ ] Deep links require auth before content/profile access

**Gate**
- [ ] Social discovery paths are stable

### Phase 8 — Share Model Serialization

**Build**
- [ ] Implement `SocialShareService` serializer for wishlist
- [ ] Implement serializer for binders
- [ ] Implement serializer for decks
- [ ] Add `payload_version` and metadata to all payloads
- [ ] Define local-to-remote content identity mapping
- [ ] Define delete/unpublish behavior for removed local content

**Test**
- [ ] Each content type serializes to the agreed contract
- [ ] Private financial data is excluded by default
- [ ] `include_value` only affects allowed market-value fields
- [ ] Deleted local content unpublishes or archives correctly

**Gate**
- [ ] Content serialization is safe and contract-compliant

### Phase 9 — Share Settings And Publish Controls

**Build**
- [ ] Build `ShareSettingsView`
- [ ] Add enable/disable sharing per content item/type
- [ ] Add title/description editing
- [ ] Add visibility controls
- [ ] Add include-market-value toggle
- [ ] Add free-tier content gating rules
- [ ] Add sharing state indicators in local collection/wishlist/deck surfaces

**Test**
- [ ] User can publish and unpublish content intentionally
- [ ] Free-tier sharing limits are enforced
- [ ] Include-value toggle behaves correctly
- [ ] Shared state indicators match remote publish state

**Gate**
- [ ] Manual sharing controls are stable before auto-sync is enabled

### Phase 10 — Auto-Sync Shared Content

**Build**
- [ ] Observe local model/save events for shareable content
- [ ] Add 30-second debounced sync pipeline
- [ ] Add conflict/update strategy for existing shared records
- [ ] Add retry/error state handling
- [ ] Add sync logging/telemetry hooks

**Test**
- [ ] Editing shared content locally updates remote content after debounce
- [ ] Repeated edits collapse into a single sync burst where expected
- [ ] Failed syncs surface usable errors/retry state
- [ ] Unpublished content does not auto-republish unexpectedly

**Gate**
- [ ] Shared-content sync is reliable enough for friend-facing UI

### Phase 11 — Friend Profile And Shared Content Viewing

**Build**
- [ ] Build `FriendProfileView`
- [ ] Show avatar, username, bio, pinned card
- [ ] List friend `shared_content` entries by type
- [ ] Build `SharedContentView`
- [ ] Reuse browse/card UI components to render snapshots
- [ ] Add “I have this” entry point
- [ ] Keep “I have this” separate from trade-start CTA

**Test**
- [ ] Friends can view each other’s shared profiles/content
- [ ] Non-friends cannot access friends-only content
- [ ] Blocked users cannot access content
- [ ] Shared snapshots render correctly for each content type
- [ ] “I have this” sends the intended lightweight signal without forcing trade creation

**Gate**
- [ ] Friend-facing content browsing is working

### Phase 12 — Feed Read Model

**Build**
- [ ] Implement `SocialFeedService.fetchFeed()`
- [ ] Define feed item mapping from shared content / comments / reactions / friendship events
- [ ] Build `FeedView`
- [ ] Build `FeedItemView`
- [ ] Add pagination/cursor loading strategy
- [ ] Add unread-state tracking model
- [ ] Exclude private-only `collection_stats` from shared/feed models

**Test**
- [ ] Feed loads for a user with friend activity
- [ ] Feed paginates correctly
- [ ] Read/unread state behaves predictably
- [ ] Empty states and loading states are present

**Gate**
- [ ] Feed can be browsed safely before reactions/comments are added

### Phase 13 — Comments And Reactions

**Build**
- [ ] Implement `postReaction`
- [ ] Implement `fetchComments`
- [ ] Implement `postComment`
- [ ] Build `CommentsView`
- [ ] Add threaded replies
- [ ] Add comment/reaction moderation hooks for future reporting

**Test**
- [ ] Friends can react to shared content
- [ ] Friends can comment on binders and decks only
- [ ] Threaded replies render and post correctly
- [ ] Reaction counts and comment threads refresh correctly
- [ ] Non-friends cannot comment/react on protected content

**Gate**
- [ ] Social interaction layer is stable

### Phase 14 — Notification Preferences

**Build**
- [ ] Build notification preferences UI
- [ ] Load/save `notification_preferences`
- [ ] Add settings entry point
- [ ] Wire preference checks into local notification decision points

**Test**
- [ ] Preference toggles persist
- [ ] Disabled categories are no longer scheduled/sent by app logic
- [ ] Defaults are sensible for new users

**Gate**
- [ ] Notification preference model is complete before push delivery goes live

### Phase 15 — APNs And Deep-Link Push Delivery

**Build**
- [ ] Register APNs token with backend
- [ ] Build Supabase Edge Function for push delivery
- [ ] Add push events for friend requests
- [ ] Add push events for friend acceptances
- [ ] Add push events for shared content posts
- [ ] Add push events for comments
- [ ] Add push events for wishlist matches
- [ ] Add push events for trade updates
- [ ] Add push deep-link routing into app screens
- [ ] Add Social tab unread badge wiring

**Test**
- [ ] Pushes arrive for enabled categories
- [ ] Disabled categories respect preferences
- [ ] Tapping a push deep-links correctly
- [ ] Social badge updates and clears correctly

**Gate**
- [ ] Notification loop is complete and trustworthy

### Phase 16 — Trade Ledger Foundation

**Build**
- [ ] Add `CollectionLedgerService.recordTradeOut(...)`
- [ ] Define outgoing trade cost-lot consumption rules
- [ ] Define cash top-up ledger treatment precisely
- [ ] Add remote + local idempotency acknowledgement design to execution flow
- [ ] Define ownership/inventory validation rules before a trade can be proposed

**Test**
- [ ] `recordTradeOut(...)` creates correct `LedgerLine` data
- [ ] FIFO lot consumption is correct
- [ ] Trade-out does not corrupt unrelated collection items
- [ ] Duplicate execution attempts are safely ignored

**Gate**
- [ ] Ledger mutation safety is proven before trade UI exists

### Phase 17 — Trade Service Core

**Build**
- [ ] Implement `SocialTradeService.proposeTrade`
- [ ] Implement `counterOffer`
- [ ] Implement `acceptTrade`
- [ ] Implement `declineTrade`
- [ ] Implement `cancelTrade`
- [ ] Implement `markReceived`
- [ ] Implement `executeTrade`
- [ ] Implement trade message send/fetch
- [ ] Add trade validation for ownership and available quantity
- [ ] Persist full-snapshot trade revisions on propose/counter/accept/cancel events

**Test**
- [ ] Proposed trades persist correctly
- [ ] Counter-offer loop works
- [ ] Accept/decline/cancel transitions are enforced correctly
- [ ] Completed trades execute once per user only
- [ ] Trade messages are only visible to trade participants

**Gate**
- [ ] Trade engine is stable enough for UI exposure

### Phase 18 — Trade Composer UI

**Build**
- [ ] Build `BuildTradeOfferView`
- [ ] Build `TradeItemPickerView`
- [ ] Add offering/requesting panels
- [ ] Add quantity controls
- [ ] Add cash top-up controls
- [ ] Add validation and disabled-state messaging

**Test**
- [ ] User can compose a valid trade
- [ ] User cannot compose a trade with unavailable quantities
- [ ] Cash top-up fields validate correctly
- [ ] Invalid trades are blocked before submission

**Gate**
- [ ] Users can create safe valid offers

### Phase 19 — Trade Detail, Lists, And Completion Flow

**Build**
- [ ] Build `TradesListView`
- [ ] Build `TradeDetailView`
- [ ] Build `TradeCompletionView`
- [ ] Build `TradeMessagesView`
- [ ] Add status/action UI for proposed/countered/accepted/completed/cancelled
- [ ] Add physical exchange “Mark as Received” flow
- [ ] Add active-vs-history grouping

**Test**
- [ ] Active trades surface actions correctly
- [ ] Past trades render accurate outcomes
- [ ] Both users can complete the received-confirmation flow
- [ ] Completed trades update UI status correctly
- [ ] Trade chat is available inside the trade detail flow only

**Gate**
- [ ] Full trade UX works for the happy path

### Phase 20 — End-To-End Regression And Hardening

**Build**
- [ ] Add empty states, skeletons, and error handling across social surfaces
- [ ] Add analytics/logging for sync failures, push failures, and trade execution failures
- [ ] Add premium upgrade prompts at friend/share gates
- [ ] Add wishlist-match badges and polish items
- [ ] Review copy, accessibility, and loading behavior

**Test**
- [ ] Existing CloudKit wishlist, collection, pricing, and scanner flows still work
- [ ] Social flows degrade safely when CloudKit is unavailable
- [ ] Multi-device scenarios do not duplicate trade execution
- [ ] Block, auth, and friend-access privacy rules hold across all entry points
- [ ] Release checklist passes for profiles, sharing, feed, notifications, and trades

**Gate**
- [ ] Social/trading release candidate is ready

---

## Implementation Rule

The `Build-Test Phased Plan` above is now the single source of truth for implementation sequencing. AI should work phase by phase, complete the `Build` checklist, pass the `Test` checklist, and only then move through the `Gate` into the next phase.

---

## Release QA Checklist

- [ ] **Auth regression:** CloudKit sync, wishlist CRUD, pricing, scanner unchanged after `supabase-swift` added
- [ ] **Auth flow:** Fresh install → Sign in with Apple → Supabase session → username picker → `profiles` row created
- [ ] **Avatar storage:** R2-backed avatars upload, load, and cache correctly.
- [ ] **Friend limit:** Free user with 1 accepted friend cannot send a second request; upgrades via StoreKit then can
- [ ] **Sharing gate:** Free user cannot auto-sync a deck build; premium user can
- [ ] **Auto-sync:** Edit wishlist on device A → within 30s friend on device B sees updated snapshot in `FriendProfileView`
- [ ] **Feed delivery:** Publish content on device A → device B receives APNs push → taps notification → `FeedView` opens with fresh data. Feed also refreshes on tab open and when foregrounded after >5 min.
- [ ] **“I have this”:** Shared-content interactions can send an “I have this” signal without starting a trade automatically.
- [ ] **Comment scope:** Comments are only available on shared binders and decks; wishlist shares do not expose comments.
- [ ] **Threading:** Reply threads render correctly and blocked-user comments disappear immediately.
- [ ] **Trade happy path:** User A proposes trade → User B receives push → accepts → both confirm received → both apps update collections → `completed` status
- [ ] **Counter-offer:** User A proposes → User B counters → User A accepts → collections update correctly
- [ ] **Trade revisions:** Each propose/counter/accept/cancel event writes a full revision snapshot visible to both parties.
- [ ] **Trade chat:** Messages stay attached to the trade and are only visible to the two participants.
- [ ] **Trade ledger:** Completed trade creates matching `tradedIn` + `tradedOut` `LedgerLine` rows on both devices with shared `transactionGroupId` and market value prices
- [ ] **RLS:** Unauthenticated or non-friend Supabase query returns 0 rows for `shared_content` with `friends` visibility
- [ ] **Push:** All APNs trigger cases deliver alerts — friend request received, friend request accepted, new content from friend, "I have this" on wishlist, new comment, trade offer received, trade countered, trade accepted, counterparty marked items received, trade completed
