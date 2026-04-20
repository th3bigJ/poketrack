# Part A1-A4 Social - End-to-End Testing Checklist

Use this checklist to validate Part A (A1 through A4) before moving to Part B trading work.

---

## 0) Test Environment Setup

- [ ] Supabase project is healthy and reachable.
- [ ] Migrations applied:
  - [ ] `20260420_part_a2_friendships.sql`
  - [ ] `20260420_part_a3_shared_content.sql`
  - [ ] `20260420_part_a3_rls_initplan_optimizations.sql`
  - [ ] `20260420_part_a4_feed_notifications_push.sql`
  - [ ] `20260420_part_a4_phase15_push_triggers.sql`
- [ ] `BINDR_SUPABASE_URL` and `BINDR_SUPABASE_PUBLISHABLE_KEY` are present in `Bindr/Info.plist`.
- [ ] App builds in Debug (`Bindr` scheme) with no compile errors.
- [ ] At least 2 active test clients available (2 simulators, or simulator + physical device).
- [ ] Test accounts prepared:
  - [ ] User A (free tier)
  - [ ] User B (free tier)
  - [ ] User C (non-friend control user)
  - [ ] Optional User D (premium tier)
- [ ] Phase 15 backend deployment is present in Supabase:
  - [ ] Edge Function `social-push` is deployed and `ACTIVE`.
  - [ ] Push triggers exist for `friendships`, `shared_content`, `comments`, and `wishlist_matches`.
  - [ ] `push_delivery_log` table exists and receives delivery/skipped/failed log rows.

---

## 1) A1 Profiles + Auth

### Sign In and Session Lifecycle
- [ ] Fresh install -> Social -> Sign in with Apple succeeds.
- [ ] Supabase session is created and user enters social flow.
- [ ] Force-close and relaunch app; session restores without re-auth prompt.
- [ ] Sign out from social profile and confirm:
  - [ ] social session is cleared
  - [ ] app does not crash
  - [ ] local collection/browse data is unaffected

### Profile Creation and Editing
- [ ] First social entry for new user presents profile creation flow.
- [ ] Username availability check blocks duplicates with clear error text.
- [ ] Username is immutable after initial save.
- [ ] Display name and bio save and persist after relaunch.
- [ ] Existing user skips setup and lands in normal social flow.

### Notification Preferences Defaults
- [ ] A default `notification_preferences` row exists after profile creation.
- [ ] Default values are correct:
  - [ ] social categories ON
  - [ ] marketing OFF

---

## 2) A2 Friends

### Discovery and Requests
- [ ] User A searches partial username and finds User B.
- [ ] User A sends request to User B.
- [ ] User B sees incoming pending request.
- [ ] User B accepts; both users appear in each other friend list.
- [ ] Repeat with decline path and verify request disappears for both.

### Free Tier Friend Cap
- [ ] Free user with one pending/accepted relationship cannot send another request.
- [ ] Premium user can exceed free-tier cap.

### Blocking Enforcement
- [ ] User A blocks User B.
- [ ] Blocked users disappear from active friend list/search as expected.
- [ ] Blocked users cannot send new requests.
- [ ] Any friend-based access between blocked users is revoked immediately.

### QR + Deep Links
- [ ] QR profile renders with expected format: `bindr://profile/@username`.
- [ ] Scanning QR opens correct friend profile.
- [ ] Manual deep link opens profile:
  - `xcrun simctl openurl booted "bindr://profile/@<username>"`
- [ ] Deep-link while signed out routes through auth and resumes correctly.

---

## 3) A3 Sharing

### Publish/Unpublish Controls
- [ ] User can open share settings from binder, deck, and wishlist.
- [ ] User can edit title, description, visibility, and include-value toggle.
- [ ] Publish creates/updates remote `shared_content`.
- [ ] Unpublish removes visibility as expected.

### Tier Limits
- [ ] Free-tier sharing limit enforced (wishlist + 1 binder).
- [ ] Premium account bypasses free-tier sharing limit.

### Payload Integrity
- [ ] With include-value OFF, payload excludes sensitive/private finance data.
- [ ] With include-value ON, payload includes only intended market value fields.
- [ ] `payload_version` and `generated_at` are present.

### Auto-Sync (Debounced)
- [ ] Editing published content syncs remotely within roughly 30 seconds.
- [ ] Multiple rapid edits coalesce into a single sync burst.
- [ ] Unpublished content does not auto-sync.

### Friend Content Viewing and RLS
- [ ] Friend (User B) can view User A shared content.
- [ ] Non-friend (User C) cannot read `friends` visibility content.
- [ ] Blocked user content access is revoked immediately.

### Wishlist Match Signal
- [ ] `I have this` writes to `wishlist_matches`.
- [ ] `I have this` does not create a trade or chat.

---

## 4) A4 Feed + Reactions + Comments + Notifications + Push

### Feed Read Model
- [ ] Feed loads activity from accepted friends.
- [ ] Pull-to-refresh fetches latest activity.
- [ ] Pagination/load-more works at list bottom.
- [ ] Empty state appears for new/no-activity accounts.
- [ ] Unread state clears after viewing feed.

### Reactions
- [ ] User can add reaction to friend shared content.
- [ ] Toggle/remove reaction works.
- [ ] Reaction count updates after add/remove.

### Comments
- [ ] User can add top-level comment on binder.
- [ ] User can reply to comment and thread indentation appears.
- [ ] Deck comments behave the same as binder comments.
- [ ] Wishlist shares do not expose comment entry point.
- [ ] Blocked user comments/reactions stop appearing immediately.

### Notification Preferences UI
- [ ] Notification Preferences screen opens from Settings.
- [ ] Each toggle saves and persists across relaunch.
- [ ] Disabling a category updates preference row and decision logic.

### APNs + Deep Link Routing
- [ ] APNs registration token is captured and written to `device_tokens`.
- [ ] APNs function secrets are configured (`APNS_TOPIC`, `APNS_ENV`, `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_PRIVATE_KEY`).
- [ ] Push function honors `notification_preferences` for each category.
- [ ] Receiving push with `deep_link` navigates to correct in-app destination.
- [ ] Tapping push while app closed/backgrounded routes correctly.
- [ ] Validate each trigger path end-to-end:
  - [ ] friend request received
  - [ ] friend request accepted
  - [ ] friend publishes shared content
  - [ ] comment on your content
  - [ ] wishlist "I have this" match

### Social Badge
- [ ] Social indicator appears when unread feed exists.
- [ ] Badge clears after user views feed/social destination.

---

## 5) Security and RLS Verification

- [ ] All social tables in `public` have RLS enabled.
- [ ] `profiles` read is authenticated-only; writes are owner-only.
- [ ] `friendships` visibility/update rules match requester/addressee expectations.
- [ ] `shared_content` respects `friends` and `link` rules.
- [ ] `reactions`, `comments`, `wishlist_matches` require access to parent content.
- [ ] `notification_preferences` and `device_tokens` are owner-only.
- [ ] Blocked users cannot read each other's friend-scoped content/feed interactions.

---

## 6) Regression Sweep (Must Pass)

- [ ] Dashboard, Browse, Collect, Binders, and More still behave correctly.
- [ ] Scanner, pricing, wishlist, and collection flows unaffected by social changes.
- [ ] Launch and relaunch stability confirmed on at least 2 devices.
- [ ] No crash when camera permission is denied in QR scanner.
- [ ] No crash when offline during social actions (clear error states shown).

---

## Exit Gate

Part A1-A4 is test-complete when:

- [ ] all sections above pass,
- [ ] at least one clean-install run is green,
- [ ] at least one relaunch/recovery run is green,
- [ ] friend vs non-friend vs blocked-user scenarios are all validated,
- [ ] push + deep-link behavior is confirmed on a physical device.
