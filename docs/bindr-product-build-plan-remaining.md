# Bindr - Social Build Plan (Remaining Work Only)

This file tracks only unfinished work.

Completed:
- Part A1 Profiles
- Part A2 Friends
- Part A3 Sharing
- Part A4 Phases 12-14 (feed, reactions/comments, notification preferences UI)
- Part A4 Phase 15 backend wiring (Edge Function + DB triggers + logging table)

---

## What Is Left Now

1. Finalize Part A4 Phase 15 runtime configuration + device validation
2. Run full A1-A4 QA and sign-off
3. Start Part B (Trading)

---

## Part A4 - Remaining (Phase 15)

### Goal
Complete production-grade push delivery and final social readiness for ship.

### Build
- [x] Deploy Supabase Edge Function `social-push` for push delivery.
- [x] Add push trigger: friend request received.
- [x] Add push trigger: friend request accepted.
- [x] Add push trigger: friend publishes new shared content.
- [x] Add push trigger: new comment on your content.
- [x] Add push trigger: "I have this" on your wishlist.
- [x] Ensure `notification_preferences` gating is implemented in push delivery logic.
- [x] Include deep-link target data in push payload shape.
- [ ] Configure APNs runtime secrets in Supabase (`APNS_TOPIC`, `APNS_ENV`, `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_PRIVATE_KEY`).
- [ ] Runtime verification: test push no longer logs `missing APNs secrets or topic`.
- [ ] Validate push deep-link routing opens the correct in-app destination.
- [ ] Validate Social badge behavior under all unread states.
- [x] Add push observability table (`push_delivery_log`) for sent/skipped/failed records.

### Test
- [ ] Push arrives for each enabled trigger category.
- [ ] Disabled categories do not send push.
- [ ] Push tap deep-links to correct destination in foreground/background/cold-start states.
- [ ] Social unread indicator appears and clears correctly.
- [ ] Duplicate push sends are prevented where expected.
- [ ] Push failure paths are observable in `push_delivery_log`.

### Gate
- [ ] Part A4 complete.
- [ ] Part A is shippable.

---

## Part A Sign-Off Checklist (Consolidated)

Use this doc for full execution:
- `docs/part-a1-a4-testing-checklist.md`

Required before Part B begins:
- [ ] A1-A4 checklist completed end-to-end.
- [ ] Friend/non-friend/blocked scenarios verified.
- [ ] At least one clean install and one relaunch run pass.
- [ ] Physical-device APNs flow verified.

---

## Part B - Trading (Not Started)

Detailed phasing will be added after Part A ship gate is passed.

### Scope
- Single cards + cash top-up only (V1)
- Multi-card both sides; counter-offer negotiate loop
- Two-stage flow: agreement -> physical exchange confirmation -> collection execution
- Trade ledger via `CollectionLedgerService.recordTradeOut(...)` + existing `recordSingleCardAcquisition(kind: .trade)`
- Full revision history per trade
- Trade chat scoped to the trade

### Tables Required
`trade_offers`, `trade_offer_items`, `trade_offer_revisions`, `trade_messages`

### New Service Required
`SocialTradeService`

### New UI Required
`TradesListView`, `TradeDetailView`, `BuildTradeOfferView`, `TradeItemPickerView`, `TradeMessagesView`, `TradeCompletionView`
