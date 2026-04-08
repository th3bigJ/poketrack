# PokeTrack Data Flow Architecture

## System Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         PokeTrack App                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────┐     ┌────────────────┐                     │
│  │  WishlistView  │     │ CollectionView │                     │
│  │                │     │                │                     │
│  │  - Add cards   │     │  - View owned  │                     │
│  │  - View list   │     │  - Add/remove  │                     │
│  │  - Delete      │     │  - Track price │                     │
│  └────────┬───────┘     └────────┬───────┘                     │
│           │                      │                              │
│           └──────────┬───────────┘                              │
│                      │                                          │
│           ┌──────────▼───────────┐                             │
│           │   WishlistService    │                             │
│           │                      │                             │
│           │  - Premium gating    │                             │
│           │  - Business logic    │                             │
│           │  - Validation        │                             │
│           └──────────┬───────────┘                             │
│                      │                                          │
│           ┌──────────▼───────────┐                             │
│           │   SwiftData Models   │                             │
│           │                      │                             │
│           │  - WishlistItem      │                             │
│           │  - CollectionItem    │                             │
│           │  - TransactionRecord │                             │
│           └──────────┬───────────┘                             │
│                      │                                          │
│           ┌──────────▼───────────┐                             │
│           │   ModelContainer     │                             │
│           │   (SQLite + Cloud)   │                             │
│           └──────────┬───────────┘                             │
│                      │                                          │
└──────────────────────┼──────────────────────────────────────────┘
                       │
                       │ Automatic Sync
                       │
            ┌──────────▼──────────┐
            │   CloudKit (iCloud) │
            │                     │
            │  - User's iCloud    │
            │  - Cross-device     │
            │  - Automatic backup │
            └─────────────────────┘
```

---

## Data Storage Breakdown

```
┌─────────────────────────────────────────────────────────────────┐
│                      Storage Locations                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. SwiftData (Local SQLite)                                    │
│     ┌───────────────────────────────────────┐                  │
│     │ WishlistItem                          │                  │
│     │ CollectionItem                        │                  │
│     │ TransactionRecord                     │                  │
│     └───────────────────────────────────────┘                  │
│     Location: App's Documents folder                            │
│     Syncs to: CloudKit (if enabled)                            │
│                                                                  │
│  2. UserDefaults                                               │
│     ┌───────────────────────────────────────┐                  │
│     │ Currency preference (USD/GBP)         │                  │
│     │ Onboarding state                      │                  │
│     │ Other UI preferences                  │                  │
│     └───────────────────────────────────────┘                  │
│     Location: ~/Library/Preferences/                            │
│     Syncs to: iCloud Backup (automatic)                        │
│                                                                  │
│  3. Keychain                                                    │
│     ┌───────────────────────────────────────┐                  │
│     │ Sign in with Apple user ID            │                  │
│     │ (currently unused)                    │                  │
│     └───────────────────────────────────────┘                  │
│     Location: Secure Enclave                                    │
│     Syncs to: iCloud Keychain (if enabled)                     │
│                                                                  │
│  4. StoreKit                                                    │
│     ┌───────────────────────────────────────┐                  │
│     │ Premium subscription status           │                  │
│     │ Purchase receipts                     │                  │
│     └───────────────────────────────────────┘                  │
│     Location: Apple's servers                                   │
│     Syncs to: Always (tied to Apple ID)                        │
│                                                                  │
│  5. NSUbiquitousKeyValueStore (Optional)                       │
│     ┌───────────────────────────────────────┐                  │
│     │ Currency preference (synced)          │                  │
│     │ Other settings                        │                  │
│     └───────────────────────────────────────┘                  │
│     Location: iCloud                                            │
│     Syncs to: All user's devices (automatic)                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Premium Feature Gating Flow

```
User taps "Add to Wishlist"
           │
           ▼
    ┌─────────────┐
    │ WishlistView│
    └──────┬──────┘
           │
           ▼
    Check: Can add item?
           │
     ┌─────┴─────┐
     │           │
     ▼           ▼
Is Premium?   Count < 5?
     │           │
  YES│           │YES
     │           │
     ▼           ▼
  ┌──────────────────┐
  │  Add card to     │
  │  wishlist        │
  └────────┬─────────┘
           │
           ▼
    Save to SwiftData
           │
           ▼
    Sync to CloudKit
           │
           ▼
      ┌────────┐
      │ Success│
      └────────┘

           │
     NO    │    NO
     ├─────┴─────┤
     │           │
     ▼           ▼
  ┌─────────────────┐
  │ Show paywall    │
  └─────────────────┘
```

---

## iCloud Sync Flow

```
Device A                     CloudKit                    Device B
────────                     ────────                    ────────

User adds
wishlist item
    │
    ▼
Save to
SwiftData
    │
    ▼
Detect change
    │
    ▼
Upload to
CloudKit ──────────────────▶ Store in
                             iCloud ──────────────────▶ Receive
                                                        change
                                                           │
                                                           ▼
                                                        Download
                                                           │
                                                           ▼
                                                        Merge with
                                                        local data
                                                           │
                                                           ▼
                                                        Update UI
                                                           │
                                                           ▼
                                                        User sees
                                                        new item!
```

---

## Sign in with Apple vs iCloud Storage

```
┌─────────────────────────────────────────────────────────────────┐
│                  Sign in with Apple                              │
├─────────────────────────────────────────────────────────────────┤
│  Purpose:      Identify user for YOUR backend                   │
│  Gives you:    User ID, email (optional), name (optional)       │
│  Requires:     User to click "Sign in with Apple" button        │
│  Use cases:    - Web portal                                     │
│                - Custom backend server                          │
│                - Cross-platform (Android, web)                  │
│                - Social features                                │
│  Current use:  NONE (you're storing ID but not using it)        │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                  iCloud / CloudKit Storage                       │
├─────────────────────────────────────────────────────────────────┤
│  Purpose:      Store user data in their iCloud                  │
│  Gives you:    Free cloud storage, automatic sync               │
│  Requires:     User signed into iCloud on device (Settings)     │
│  Use cases:    - App data sync                                  │
│                - Cross-device for same user                     │
│                - Automatic backup                               │
│                - No server needed                               │
│  Current use:  READY (SwiftData + CloudKit configured)          │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                       Recommendation                             │
├─────────────────────────────────────────────────────────────────┤
│  For wishlists & collections:                                   │
│  ✅ Use iCloud/CloudKit (already implemented)                   │
│  ❌ Don't need Sign in with Apple                               │
│                                                                  │
│  Keep Sign in with Apple for future:                            │
│  - If you build a web portal                                    │
│  - If you need a custom backend                                 │
│  - If you want user accounts on YOUR server                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## User Journey: First Time Setup

```
Step 1: User downloads PokeTrack
           │
           ▼
Step 2: User opens app
           │
           ▼
Step 3: App checks: Is user signed into iCloud?
           │
     ┌─────┴─────┐
     │           │
   YES           NO
     │           │
     ▼           ▼
 ┌─────────┐  ┌──────────────────┐
 │ CloudKit│  │ Show message:    │
 │ enabled │  │ "Sign into iCloud│
 │         │  │  to sync data"   │
 └────┬────┘  └──────────────────┘
      │               │
      │               │ (User can still use app,
      │               │  data saves locally only)
      │               │
      ▼               ▼
User adds wishlist items
      │               │
      ▼               ▼
  Syncs to          Saves
  iCloud            locally
      │               │
      ▼               │
  ✅ Data backed     │
     up and          │
     synced          │
                     │
                     ▼
          User signs into iCloud later
                     │
                     ▼
          Local data syncs to iCloud
                     │
                     ▼
                 ✅ Backed up!
```

---

## Multi-Device Sync Example

```
Scenario: User has iPhone and iPad

iPhone                        iCloud                      iPad
──────                        ──────                      ────

Opens app                                                 (Closed)
    │
    ▼
Adds "Charizard"
to wishlist
    │
    ▼
Saves locally
    │
    ▼
Uploads to                    Receives
CloudKit ─────────────────▶   "Charizard"
                              record
                                  │
                                  │
                                  │         Opens app
                                  │              │
                                  │              ▼
                                  │         Checks for
                                  │         updates
                                  │              │
                                  │              ▼
                              Downloads    Pulls from
                              "Charizard" ◀────CloudKit
                                  │
                                  ▼
                              Updates local
                              SwiftData
                                  │
                                  ▼
                              UI refreshes
                                  │
                                  ▼
                              User sees
                              "Charizard"!

Time elapsed: Usually < 30 seconds
```

---

## Offline Support

```
Scenario: User has no internet

User opens app (offline)
    │
    ▼
Adds wishlist items
    │
    ▼
Saves to local SwiftData
    │
    ▼
CloudKit sync queued
(waits for connection)
    │
    │ ... user goes online ...
    │
    ▼
CloudKit detects connection
    │
    ▼
Uploads queued changes
    │
    ▼
✅ Synced!

Note: App works 100% offline.
Sync happens automatically when online.
```

---

## Premium vs Free Comparison

```
┌─────────────────────────┬──────────────┬──────────────┐
│ Feature                 │ Free         │ Premium      │
├─────────────────────────┼──────────────┼──────────────┤
│ Wishlist items          │ 5 max        │ Unlimited    │
│ Collection items        │ Unlimited    │ Unlimited    │
│ Transaction history     │ Unlimited    │ Unlimited    │
│ iCloud sync             │ ✅           │ ✅           │
│ Currency conversion     │ ✅           │ ✅           │
│ Price tracking          │ ✅           │ ✅           │
│ Card catalog            │ ✅           │ ✅           │
└─────────────────────────┴──────────────┴──────────────┘

Logic implemented in WishlistService.swift:
    var canAddItem: Bool {
        if store.isPremium {
            return true // Unlimited
        }
        return items.count < Self.freeWishlistLimit
    }
```

---

## Files You Created

```
PokeTrack/
├── Models/
│   └── WishlistItem.swift ────────────┐
│       - WishlistItem                  │
│       - CollectionItem                │
│       - TransactionRecord             │
│                                       │
├── Services/                           │
│   ├── WishlistService.swift ──────────┼─ Core Logic
│   ├── CloudSettingsService.swift     │
│   └── AppServices.swift (updated)    │
│                                       │
├── Views/                              │
│   ├── WishlistView.swift ─────────────┼─ UI
│   └── AccountView.swift (update)     │
│                                       │
├── App/                                │
│   └── PokeTrackApp.swift (updated)───┘─ Setup
│
└── Documentation/
    ├── STORAGE_ARCHITECTURE.md ─────────── Full guide
    └── SETUP_CHECKLIST.md ──────────────── Step-by-step
```

---

## Quick Reference: Where to Store What

```
Setting/Data                    Storage Method              Syncs?
─────────────────────────────── ─────────────────────────── ──────
Wishlist items                  SwiftData + CloudKit        ✅ Yes
Collection items                SwiftData + CloudKit        ✅ Yes
Transaction records             SwiftData + CloudKit        ✅ Yes
Currency preference             UserDefaults                ⚠️  Via iCloud Backup
Premium status                  StoreKit                    ✅ Yes (automatic)
Sign in with Apple ID           Keychain                    ✅ Yes (iCloud Keychain)
Onboarding completed            UserDefaults                ⚠️  Via iCloud Backup
Last sync date                  UserDefaults                ⚠️  Via iCloud Backup
Card catalog (downloaded)       File system                 ❌ No (re-download)
Card images cache               File system                 ❌ No (re-download)

Legend:
✅ Real-time sync across devices
⚠️  Backed up but not real-time
❌ Not synced (re-downloaded on new device)
```

---

## Next Steps Summary

1. **Enable iCloud in Xcode** (5 minutes)
   - Target → Signing & Capabilities → + iCloud → CloudKit

2. **Test on simulator** (10 minutes)
   - Run app, add wishlist items
   - Check they save and load

3. **Integrate WishlistView** (20 minutes)
   - Add to your main navigation
   - Connect with existing card catalog

4. **Test premium gating** (5 minutes)
   - Try adding 6th item without premium
   - Should show paywall

5. **Test multi-device sync** (15 minutes)
   - Two simulators or devices
   - Same iCloud account
   - Add item on one, see on other

6. **Update AccountView** (10 minutes)
   - Add iCloud status section
   - Optionally hide/explain Sign in with Apple

Total time: ~1 hour to get wishlists fully working!
