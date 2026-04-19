# Bindr — Social Build Plan

---

## Project Snapshot

Part A (bindrs, decks, dashboard, navigation) is complete. The app has 5 tabs: Dashboard, Browse, Collect, Bindrs, More. Social is accessed via More → Social, which pushes `SocialRootView` (currently a placeholder). This document covers the social and trading build only.

**Current app structure (locked):**

| Tab | Content |
|---|---|
| Dashboard | Collection value, P&L, recent activity |
| Browse | Card catalog |
| Collect | Collection + Wishlist (segmented) |
| Bindrs | Binder organiser |
| More → Social | `SocialRootView` placeholder — full social build target |
| More → Deck Builder | `DecksRootView` |

Social stays in More. It does not become its own tab.

---

## Overall Plan Structure

- **Part A1 — Profiles:** Supabase setup, auth, profile creation and editing
- **Part A2 — Friends:** Friend graph, search, requests, blocking, QR/deep links
- **Part A3 — Sharing:** Content serialisation, publish controls, auto-sync, friend profile viewing
- **Part A4 — Feed:** Feed read model, reactions, comments, notifications, push
- **Part B — Trading:** Trade ledger, trade service, trade UI *(planned after Part A is complete)*

---

## Locked Decisions

- Usernames are immutable once chosen during first social setup.
- `link` visibility still requires authentication in V1.
- Free-tier friend limit counts both `pending` and `accepted` relationships (1 friend free, unlimited premium).
- Blocking unfriends both sides, hides shared content from both, and cancels any open trades.
- Comments are enabled on binders and decks only (not wishlist).
- Comments support threaded replies in V1.
- `collection_stats` is private and is not a shared content type in V1.
- Social remains usable when CloudKit is degraded.
- Avatar storage uses Cloudflare R2, not Supabase Storage.
- "I have this" is a lightweight signal only — does not auto-start a trade.
- Trade chat is scoped to the trade itself, not a general DM system.
- `payload_version` is a field inside shared JSONB payloads. Breaking changes bump the version; readers stay compatible with at least the previous version.
- All share-entry deep links route through auth/session restore first.
- Social badge: red dot on the More tab Social row for unread feed items, pending friend requests, and trades requiring action.

---

## Existing Code to Reuse

| Asset | Location | How Used |
|---|---|---|
| `KeychainStorage` | `Services/KeychainStorage.swift` | Extend for Supabase JWT storage |
| `AppServices` | `Services/AppServices.swift` | Register all new social services |
| `BindrApp.swift` | — | Call `SocialAuthService.restoreSession()` on launch |
| `StoreKitService.isPremium` | `Services/StoreKitService.swift` | Friend limit + content gates |
| Card grid/list components | `Features/Browse/` | Render friend's shared content snapshots |
| `CollectionLedgerService` | `Services/CollectionLedgerService.swift` | Add `recordTradeOut(...)` in Part B |
| `LedgerLine.transactionGroupId` | `CollectionLedgerModels.swift` | Group both legs of a trade in Part B |
| `PricingService` | `Services/` | Market value at trade offer creation time in Part B |
| `MoreView` / `SideMenuPage.social` | `Features/Root/MoreSheet.swift` | Social entry point — navigates to `SocialRootView` |

**Never touch:** `CollectionLedgerModels.swift`, `WishlistModels.swift`, CloudKit `ModelContainer` config.

---

# Part A1 — Profiles

## Goal
Users can sign in with Apple, create a Supabase-linked profile with username/avatar/bio, and the session persists across relaunches.

## Supabase Tables (this milestone)

```sql
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

create table device_tokens (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references profiles(id) on delete cascade,
  token      text not null,
  updated_at timestamptz default now(),
  unique(user_id, token)
);
```

**RLS:**
- `profiles`: readable by any authenticated user; writable by owner only
- `notification_preferences`: readable/writable by owner only
- `device_tokens`: readable/writable by owner only

## New Files

```
Bindr/Services/
├── SocialAuthService.swift       — Sign in with Apple → Supabase JWT; session restore
└── SocialProfileService.swift    — Profile CRUD, avatar upload to R2, APNs token registration

Bindr/Models/
└── SocialModels.swift            — Codable structs for profiles, notification_preferences, device_tokens (extended in later milestones)

Bindr/Features/Social/Profile/
├── EditProfileView.swift         — Username/avatar/bio setup (shown on first social launch)
└── MyProfileView.swift           — View own profile, link to edit
```

## Files to Modify

| File | Change |
|---|---|
| `BindrApp.swift` | Call `SocialAuthService.restoreSession()` on launch |
| `Services/AppServices.swift` | Register `SocialAuthService`, `SocialProfileService` |
| `Services/KeychainStorage.swift` | Add Supabase session JWT storage key |
| `Data/AppConfiguration.swift` | Add Supabase URL + anon key (loaded from xcconfig/Info.plist, not hardcoded) |
| `Features/Account/` | Add "Social Profile" settings row → `MyProfileView` |
| `Features/Social/SocialRootView.swift` | Gate on signed-in state; show `EditProfileView` on first launch if no profile |

## Phases

### Phase 1 — Supabase Project & Schema

**Build**
- [ ] Create Supabase project (dev environment)
- [ ] Store Supabase URL and anon key in xcconfig / Info.plist (not committed to git)
- [ ] Write SQL migration for `profiles`
- [ ] Write SQL migration for `notification_preferences`
- [ ] Write SQL migration for `device_tokens`
- [ ] Add RLS policies for all three tables

**Test**
- [ ] Migrations run cleanly on a fresh database
- [ ] RLS blocks unauthenticated reads on `notification_preferences`
- [ ] RLS allows any authenticated user to read `profiles`

**Gate**
- [ ] Schema is frozen and ready for iOS integration

---

### Phase 2 — iOS Social Foundation

**Build**
- [ ] Add `supabase-swift` Swift Package dependency to the Xcode project
- [ ] Add Supabase URL + anon key to `AppConfiguration.swift`
- [ ] Create `SocialModels.swift` with `Profile`, `NotificationPreferences`, `DeviceToken` Codable structs
- [ ] Add `SocialAuthService` and `SocialProfileService` stubs to `AppServices`
- [ ] Extend `KeychainStorage` with Supabase session JWT key
- [ ] Create lightweight mock implementations for local development/previews

**Test**
- [ ] App compiles with social services wired but no user-facing functionality active
- [ ] No regression to existing launch, CloudKit, browse, or pricing flows

**Gate**
- [ ] Foundation merged and stable

---

### Phase 3 — Sign in with Apple + Supabase Auth

**Build**
- [ ] Add Sign in with Apple capability to the Xcode target (entitlement + App ID)
- [ ] Implement `SocialAuthService.signInWithApple()` → Supabase JWT token exchange
- [ ] Persist Supabase session JWT in Keychain
- [ ] Implement `SocialAuthService.restoreSession()` — call from `BindrApp` on launch
- [ ] Implement `SocialAuthService.signOut()` — clears social session without touching CloudKit
- [ ] Route deep links through session restore before showing content

**Test**
- [ ] Fresh install: Sign in with Apple creates a Supabase session
- [ ] Relaunch: session restored from Keychain without requiring sign-in again
- [ ] Sign-out clears session cleanly; existing CloudKit data unaffected
- [ ] Deep link while signed out routes through auth then resumes

**Gate**
- [ ] Auth lifecycle is reliable before profile work begins

---

### Phase 4 — Profile Creation & Editing

**Build**
- [ ] Implement `SocialProfileService.fetchOrCreateProfile()` — called after first sign-in
- [ ] Create default `notification_preferences` row when profile is first created
- [ ] Build `EditProfileView` — username field, avatar picker, bio/display name
- [ ] Add username availability check (async, debounced) against Supabase
- [ ] Enforce username immutability after first save (field becomes read-only)
- [ ] Add avatar upload to Cloudflare R2 with signed URL flow
- [ ] Build `MyProfileView` — shows avatar, username, bio; links to edit
- [ ] Show `EditProfileView` on first social launch if no profile row exists
- [ ] Add "Social Profile" row in Account/Settings → `MyProfileView`

**Test**
- [ ] First social launch shows profile setup flow
- [ ] Username uniqueness errors surfaced clearly to user
- [ ] Username cannot be edited after first save
- [ ] Avatar upload to R2 succeeds; image loads from URL on next launch
- [ ] Bio and display name edits persist across relaunch
- [ ] Returning user with existing profile skips setup and sees their profile

**Gate**
- [ ] A single user can fully create and maintain a social profile

---

# Part A2 — Friends

## Goal
Users can find each other by username, send/accept/decline friend requests, block users, and discover friends via QR code or deep link.

## Supabase Tables (this milestone)

```sql
create table friendships (
  id           uuid primary key default gen_random_uuid(),
  requester_id uuid references profiles(id) on delete cascade,
  addressee_id uuid references profiles(id) on delete cascade,
  status       text check (status in ('pending', 'accepted', 'blocked')),
  created_at   timestamptz default now(),
  unique(requester_id, addressee_id)
);
```

**RLS:**
- Visible to both parties in the relationship
- Insert by any authenticated user
- Status update by addressee only
- Block action immediately revokes mutual visibility

## New Files

```
Bindr/Services/
└── SocialFriendService.swift     — Friend requests, accept/decline/block, search, QR

Bindr/Features/Social/Friends/
├── FriendsListView.swift
├── FriendSearchView.swift
├── FriendRequestView.swift
└── QRProfileView.swift           — Own QR display (CIFilter) + AVFoundation scanner

Bindr/Features/Social/Profile/
└── FriendProfileView.swift       — View another user's public profile (no shared content yet)
```

## Files to Modify

| File | Change |
|---|---|
| `SocialModels.swift` | Add `Friendship` Codable struct |
| `Services/AppServices.swift` | Register `SocialFriendService` |
| `Features/Social/SocialRootView.swift` | Add Friends entry point / tab within social root |

## Phases

### Phase 5 — Friend Graph Core

**Build**
- [ ] Write SQL migration for `friendships`
- [ ] Add RLS policies for `friendships`
- [ ] Add `Friendship` struct to `SocialModels.swift`
- [ ] Register `SocialFriendService` in `AppServices`
- [ ] Implement `SocialFriendService.searchUsers(query:)` — partial username match
- [ ] Implement `sendRequest(to:)`
- [ ] Implement `respond(to:accepted:)`
- [ ] Implement `fetchFriends()`
- [ ] Implement `fetchPendingRequests()`
- [ ] Enforce free-tier cap: check total of `pending` + `accepted` before allowing a new request
- [ ] Build `FriendSearchView`
- [ ] Build `FriendRequestView` — incoming request with accept/decline
- [ ] Build `FriendsListView` — accepted friends + pending requests
- [ ] Build `FriendProfileView` — public profile (avatar, username, bio; no shared content yet)

**Test**
- [ ] User A finds User B by partial username
- [ ] User A sends a friend request; User B sees it in pending
- [ ] User B can accept — both users now appear in each other's friends list
- [ ] User B can decline — request disappears for both
- [ ] Free-tier cap blocks sending a second request (counting pending + accepted)
- [ ] Premium user is not blocked by the cap

**Gate**
- [ ] Friend relationship flow works end-to-end for two accounts

---

### Phase 6 — Blocking & Relationship Enforcement

**Build**
- [ ] Implement `SocialFriendService.block(userID:)`
- [ ] On block: update friendship status to `blocked`, revoke mutual friend access
- [ ] Blocked users cannot send friend requests or interact
- [ ] Hide all shared content and feed entries between blocked parties (enforced at RLS level)
- [ ] *(Trade cancellation on block deferred to Part B)*

**Test**
- [ ] Blocking immediately removes friend access for both sides
- [ ] Blocked user no longer appears in search or friend lists
- [ ] Blocked user cannot send a new request
- [ ] Block is reflected in RLS: Supabase returns 0 rows for blocked-user content

**Gate**
- [ ] Relationship safety rules enforced before content sharing goes live

---

### Phase 7 — Discovery, QR & Deep Links

**Build**
- [ ] Build `QRProfileView` — generate QR code from `bindr://profile/@username` using CIFilter
- [ ] Add QR scanning flow using AVFoundation
- [ ] Register `bindr://profile/@username` URL scheme in the app
- [ ] Route incoming deep links through session restore → `FriendProfileView`

**Test**
- [ ] QR code generates correctly for current user
- [ ] Scanning a friend's QR opens their `FriendProfileView`
- [ ] Username deep link opens the correct profile
- [ ] Deep link while signed out authenticates first, then opens the profile

**Gate**
- [ ] All friend discovery paths are stable

---

# Part A3 — Sharing

## Goal
Users can publish their binders, decks, and wishlist to Supabase. Friends can view those snapshots. Content auto-syncs 30 seconds after a local save.

## Supabase Tables (this milestone)

```sql
create table shared_content (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid references profiles(id) on delete cascade,
  content_type  text check (content_type in ('binder', 'wishlist', 'deck')),
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
```

**RLS:**
- `friends` visibility: readable only when an accepted friendship exists between owner and reader
- `link` visibility: readable by any authenticated user who has the UUID
- Writable by owner only

## JSONB Payload Schemas

All payloads include `payload_version: 1` and `generated_at`. Breaking changes bump the version; readers stay compatible with the previous version.

**Binder:**
```json
{ "payload_version": 1, "generated_at": "...", "brand": "pokemon", "items": [{ "cardID": "sv3pt5-001", "variantKey": "holofoil", "quantity": 2, "cardName": "Pikachu" }] }
```

**Wishlist:**
```json
{ "payload_version": 1, "generated_at": "...", "items": [{ "cardID": "sv3pt5-001", "variantKey": "normal", "cardName": "Pikachu", "notes": "Want PSA 10" }] }
```

**Deck:**
```json
{ "payload_version": 1, "generated_at": "...", "format": "Standard", "brand": "pokemon", "cards": [{ "cardID": "sv3pt5-001", "variantKey": "normal", "quantity": 4, "cardName": "Pikachu" }] }
```

## New Files

```
Bindr/Services/
└── SocialShareService.swift      — Serialise SwiftData → JSONB; 30s debounced auto-sync; publish/unpublish

Bindr/Features/Social/Sharing/
├── ShareSettingsView.swift       — Title, description, visibility, include_value toggle, publish/unpublish
└── SharedContentView.swift       — Render a friend's binder/wishlist/deck snapshot using existing browse UI
```

## Files to Modify

| File | Change |
|---|---|
| `SocialModels.swift` | Add `SharedContent` Codable struct |
| `Services/AppServices.swift` | Register `SocialShareService` |
| `Features/Social/Profile/FriendProfileView.swift` | Add list of friend's shared content; tap → `SharedContentView` |
| Binder/Deck/Wishlist screens | Add sharing status indicator + `ShareSettingsView` sheet trigger |

## Phases

### Phase 8 — Share Model Serialisation

**Build**
- [ ] Write SQL migration for `shared_content`
- [ ] Add RLS policies for `shared_content`
- [ ] Add `SharedContent` struct to `SocialModels.swift`
- [ ] Implement `SocialShareService` serialiser for wishlist → JSONB payload
- [ ] Implement serialiser for binders → JSONB payload
- [ ] Implement serialiser for decks → JSONB payload
- [ ] Include `payload_version: 1`, `generated_at`, and local content identity in all payloads
- [ ] Define local-to-remote content identity mapping (so edits update rather than duplicate)
- [ ] Define delete/unpublish behaviour when local content is deleted

**Test**
- [ ] Each content type serialises to the agreed JSONB contract
- [ ] Private financial data (cost basis, purchase price) is excluded by default
- [ ] `include_value` only adds market value fields, nothing else
- [ ] Deleting local content unpublishes or archives remote record correctly

**Gate**
- [ ] Serialisation is safe and contract-compliant

---

### Phase 9 — Share Settings & Publish Controls

**Build**
- [ ] Build `ShareSettingsView` — title, description, visibility picker, include-value toggle, publish/unpublish button
- [ ] Add sharing state indicator in `BinderDetailView`, `DeckDetailView`, and Wishlist view
- [ ] Implement publish/unpublish in `SocialShareService`
- [ ] Enforce free-tier content limits (wishlist + 1 binder; premium = all types)
- [ ] Register `SocialShareService` in `AppServices`

**Test**
- [ ] User can manually publish a binder; shared record appears in Supabase
- [ ] User can unpublish; record is removed/archived
- [ ] Free-tier limit blocks sharing a second binder; paywall shown
- [ ] Include-value toggle correctly includes/excludes market value from payload
- [ ] Sharing status indicator on local screens matches remote publish state

**Gate**
- [ ] Manual sharing controls stable before auto-sync is enabled

---

### Phase 10 — Auto-Sync Shared Content

**Build**
- [ ] Observe SwiftData save events for binders, decks, and wishlist items
- [ ] Implement 30-second debounce: coalesce rapid saves into a single sync
- [ ] On debounce fire: re-serialise and upsert the remote `shared_content` record
- [ ] Only sync content the user has explicitly published (respect publish state)
- [ ] Add retry/error state for failed syncs
- [ ] Add sync logging hook for observability

**Test**
- [ ] Editing a published binder triggers a remote update within ~30 seconds
- [ ] Multiple rapid edits produce a single sync call, not one per save
- [ ] Unpublished content is never auto-synced
- [ ] A failed sync surfaces a visible error/retry state

**Gate**
- [ ] Auto-sync is reliable before friend-facing content viewing is built

---

### Phase 11 — Friend Profile & Shared Content Viewing

**Build**
- [ ] Update `FriendProfileView` to list friend's published `shared_content` entries by type
- [ ] Build `SharedContentView` — renders binder/wishlist/deck snapshot using existing browse/card UI components
- [ ] Add "I have this" action on wishlist shared content — sends a lightweight signal (writes to `wishlist_matches`, no trade created)

**Test**
- [ ] Friend's published binders, decks, and wishlist appear on their profile
- [ ] Tapping a shared item renders the correct snapshot
- [ ] Non-friends cannot load `friends`-visibility content (RLS returns 0 rows)
- [ ] Blocked users cannot access content
- [ ] "I have this" writes a `wishlist_matches` row without creating a trade

**Gate**
- [ ] Friend-facing content browsing is working end-to-end

---

# Part A4 — Feed

## Goal
Users see a chronological feed of friend activity (new content, reactions, comments). Push notifications deliver updates. A notification preferences screen lets users control what they receive.

## Supabase Tables (this milestone)

```sql
create table reactions (
  id            uuid primary key default gen_random_uuid(),
  content_id    uuid references shared_content(id) on delete cascade,
  user_id       uuid references profiles(id) on delete cascade,
  reaction_type text check (reaction_type in ('like', 'fire', 'wow')),
  created_at    timestamptz default now(),
  unique(content_id, user_id)
);

create table comments (
  id         uuid primary key default gen_random_uuid(),
  content_id uuid references shared_content(id) on delete cascade,
  author_id  uuid references profiles(id) on delete cascade,
  parent_id  uuid references comments(id) on delete cascade,
  body       text not null,
  created_at timestamptz default now()
);

create table wishlist_matches (
  id         uuid primary key default gen_random_uuid(),
  content_id uuid references shared_content(id) on delete cascade,
  card_id    text not null,
  sender_id  uuid references profiles(id) on delete cascade,
  seen       boolean default false,
  created_at timestamptz default now()
);
```

**RLS:**
- `reactions`, `comments`, `wishlist_matches`: readable/insertable by authenticated users with friend access to the parent `shared_content`
- Comments support arbitrary parent/child nesting in storage; UI enforces a shallow depth limit

## New Files

```
Bindr/Services/
└── SocialFeedService.swift       — Feed fetch, pagination, unread state, reactions, comments

Bindr/Features/Social/
├── SocialRootView.swift          — Replace placeholder: top-level feed/friends/profile navigation
├── Feed/
│   ├── FeedView.swift
│   ├── FeedItemView.swift
│   └── CommentsView.swift        — Threaded comments + reply composer
```

## Files to Modify

| File | Change |
|---|---|
| `SocialModels.swift` | Add `Reaction`, `Comment`, `WishlistMatch` structs |
| `Services/AppServices.swift` | Register `SocialFeedService` |
| `Features/Social/SocialRootView.swift` | Replace with real feed/friends navigation |

## Phases

### Phase 12 — Feed Read Model

**Build**
- [ ] Write SQL migrations for `reactions`, `comments`, `wishlist_matches`
- [ ] Add RLS policies for all three tables
- [ ] Add `Reaction`, `Comment`, `WishlistMatch` structs to `SocialModels.swift`
- [ ] Implement `SocialFeedService.fetchFeed()` — pull on open, cursor-based pagination
- [ ] Define feed item types: new shared content, reactions, comments, friendship events, wishlist matches
- [ ] Build `FeedView` — scrollable list, pull-to-refresh, load-more
- [ ] Build `FeedItemView` — renders each feed item type
- [ ] Add unread-state tracking (local, cleared on view)
- [ ] Replace `SocialRootView` placeholder with real root that houses the feed

**Test**
- [ ] Feed loads and displays activity from accepted friends
- [ ] Feed paginates correctly on scroll
- [ ] Pull-to-refresh fetches new items
- [ ] Unread state clears when user views the feed
- [ ] Empty state and loading skeleton are present

**Gate**
- [ ] Feed can be browsed before reactions/comments are added

---

### Phase 13 — Reactions & Comments

**Build**
- [ ] Implement `SocialFeedService.postReaction(type:to:)` and remove/toggle
- [ ] Implement `SocialFeedService.fetchComments(for:)`
- [ ] Implement `SocialFeedService.postComment(body:parentID:to:)`
- [ ] Build `CommentsView` — flat list with reply indentation, reply composer
- [ ] Enforce comments on binders and decks only (no comment UI on wishlist shared content)
- [ ] Immediately hide comments/reactions from blocked users without refresh

**Test**
- [ ] User can react to a friend's shared content; reaction count updates
- [ ] User can post a top-level comment on a binder or deck
- [ ] User can reply to a comment; thread renders correctly
- [ ] Wishlist shared content has no comment entry point
- [ ] Blocked user's reactions and comments disappear immediately

**Gate**
- [ ] Social interaction layer is stable

---

### Phase 14 — Notification Preferences UI

**Build**
- [ ] Build notification preferences screen (toggle per category)
- [ ] Load/save `notification_preferences` row via `SocialProfileService`
- [ ] Add entry point in Account/Settings → Notification Preferences
- [ ] Wire preference checks into local notification decision points (stubs for push until Phase 15)

**Test**
- [ ] Toggling a preference saves and persists across relaunch
- [ ] Disabled category no longer triggers local notification logic
- [ ] New user defaults are all-on except marketing

**Gate**
- [ ] Preference model is complete before APNs work begins

---

### Phase 15 — APNs & Push Delivery

**Build**
- [ ] Register APNs device token with backend on sign-in (`device_tokens` table)
- [ ] Build Supabase Edge Function for push delivery
- [ ] Add push trigger: friend request received
- [ ] Add push trigger: friend request accepted
- [ ] Add push trigger: friend publishes new shared content
- [ ] Add push trigger: new comment on your content
- [ ] Add push trigger: "I have this" on your wishlist
- [ ] Add push deep-link routing — tap notification opens relevant screen
- [ ] Wire Social badge (red dot on More → Social row) for unread items

**Test**
- [ ] Push arrives for each enabled trigger category
- [ ] Disabled categories send no push
- [ ] Tapping a push navigates to the correct screen
- [ ] Social badge appears and clears correctly

**Gate**
- [ ] Part A4 complete; Part A is shippable

---

# Part B — Trading

*Detailed phasing will be written when Part A is complete. High-level scope only is recorded here.*

## Scope
- Single cards + cash top-up only (V1)
- Multi-card both sides; counter-offer negotiate loop
- Two-stage flow: agreement → physical exchange confirmation → collection execution
- Trade ledger via `CollectionLedgerService.recordTradeOut(...)` (new method) + existing `recordSingleCardAcquisition(kind: .trade)`
- Full revision history per trade
- Trade chat scoped to the trade

## Tables Required
`trade_offers`, `trade_offer_items`, `trade_offer_revisions`, `trade_messages`

## New Services Required
`SocialTradeService`

## New UI Required
`TradesListView`, `TradeDetailView`, `BuildTradeOfferView`, `TradeItemPickerView`, `TradeMessagesView`, `TradeCompletionView`

---

## Release QA Checklist (Part A)

- [ ] CloudKit sync, wishlist CRUD, pricing, and scanner flows unaffected after `supabase-swift` added
- [ ] Fresh install: Sign in with Apple → Supabase session → username setup → profile created
- [ ] Username cannot be changed after first save
- [ ] R2-backed avatar uploads, loads, and caches correctly
- [ ] Free-tier friend cap: 1 accepted friend; second request blocked before send
- [ ] Free-tier sharing cap: wishlist + 1 binder; second binder blocked with paywall
- [ ] Auto-sync: edit a published binder on device A → friend on device B sees update within 30s
- [ ] Blocking: shared content and feed entries from blocked user disappear immediately
- [ ] RLS: non-friend Supabase query returns 0 rows for `friends`-visibility `shared_content`
- [ ] Feed: new content from friend appears in feed on next open / pull-to-refresh
- [ ] Feed: APNs push arrives on device B when friend publishes content; tap deep-links correctly
- [ ] Comments: available on binders and decks only; not on wishlist shares
- [ ] Threaded replies render correctly
- [ ] "I have this": sends signal without creating a trade
- [ ] Notification preferences: disabled categories send no push
- [ ] Social badge: appears and clears correctly on More → Social row
