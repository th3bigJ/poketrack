# PokeTrack Data Storage Architecture

## Overview
This document outlines the data storage strategy for PokeTrack, including user data, settings, and iCloud sync.

---

## Storage Solutions Summary

### 1. **SwiftData + CloudKit** (Wishlists, Collections, Transactions)
- **What:** User's saved cards, wishlists, and transaction history
- **Where:** Local SQLite + iCloud (via CloudKit)
- **Requires:** User signed into iCloud on device (no "Sign in with Apple" needed)
- **Benefits:** 
  - Automatic sync across user's devices
  - No backend server required
  - Handles conflicts automatically
  - Free for developers (iCloud storage quota is user's responsibility)

### 2. **UserDefaults** (App Preferences)
- **What:** Currency selection, UI preferences, onboarding state
- **Where:** Local device storage
- **Requires:** Nothing
- **Benefits:** Simple, fast, automatic backup to iCloud Backup

### 3. **NSUbiquitousKeyValueStore** (Optional - Settings Sync)
- **What:** Sync settings across devices
- **Where:** iCloud key-value storage
- **Requires:** User signed into iCloud
- **Benefits:** Lightweight, perfect for small settings
- **Limit:** 1MB total, 1024 keys max

### 4. **Keychain** (Sensitive Data)
- **What:** Sign in with Apple user ID, tokens
- **Where:** Secure enclave on device
- **Requires:** Nothing
- **Benefits:** Secure, survives app reinstall, syncs via iCloud Keychain

### 5. **StoreKit** (Purchases & Subscriptions)
- **What:** Premium subscription status
- **Where:** Apple's servers
- **Requires:** User's Apple ID (automatic)
- **Benefits:** Apple handles everything, works offline, syncs automatically

---

## Sign in with Apple - Do You Need It?

### **Short Answer: NO (for your current use case)**

### When You DON'T Need Sign in with Apple:
- ✅ Storing data in iCloud/CloudKit
- ✅ In-app purchases (StoreKit handles this)
- ✅ User settings and preferences
- ✅ Local app data

### When You DO Need Sign in with Apple:
- ❌ You have your own backend server
- ❌ You want to identify users across platforms (web + mobile)
- ❌ You need to associate data with specific user accounts on YOUR server
- ❌ You want social features (friends, sharing)

### What You Currently Have:
Your "Sign in with Apple" button is functional but **not required** for any current features. You're storing the user ID in the Keychain but not using it anywhere.

### Recommendation:
**Option A (Simple):** Remove the Sign in with Apple section entirely until you need it for a backend.

**Option B (Future-Proof):** Keep it but explain to users:
- "Optional - Only needed if you plan to access your collection from the web"
- Currently it does nothing except store their Apple ID locally

---

## iCloud Setup Requirements

### For Users:
1. Settings → [Their Name] → Must be signed into iCloud
2. Settings → [Their Name] → iCloud → iCloud Drive → Enable for PokeTrack
3. That's it! No "Sign in with Apple" needed.

### For Developers (You):
1. **Xcode:** Enable iCloud capability
   - Target → Signing & Capabilities → + Capability → iCloud
   - Check "CloudKit"
   - Xcode will create a default container: `iCloud.app1xy.PokeTrack`

2. **Info.plist:** No changes needed (Xcode handles this)

3. **SwiftData Models:** Already set up in `WishlistItem.swift`

4. **App Entitlements:** Xcode adds automatically

---

## Data Storage Decision Tree

```
Is it user-generated content (wishlists, collections)?
├─ YES → SwiftData + CloudKit
│   └─ Should it sync across devices?
│       ├─ YES → Enable CloudKit (already done in PokeTrackApp.swift)
│       └─ NO → Just SwiftData (remove CloudKit container)
│
└─ NO → Is it a setting or preference?
    ├─ YES → UserDefaults (optionally sync with NSUbiquitousKeyValueStore)
    │
    └─ NO → Is it sensitive (tokens, passwords)?
        ├─ YES → Keychain
        └─ NO → Is it a purchase?
            ├─ YES → StoreKit
            └─ NO → File system / Core Data
```

---

## Premium Feature Implementation

### Wishlist Limit:
- **Free:** 5 cards max
- **Premium:** Unlimited

### Implementation:
Already handled in `WishlistService.swift`:
```swift
var canAddItem: Bool {
    if store.isPremium {
        return true // Unlimited
    }
    return items.count < Self.freeWishlistLimit
}
```

### Collections & Transactions:
- **Recommendation:** Keep unlimited for all users
- **Why:** Tracking actual owned cards shouldn't be paywalled
- **Alternative:** Limit transaction history depth (e.g., last 50 for free, unlimited for premium)

---

## Migration Plan

### Current State:
- ✅ StoreKit (premium subscription)
- ✅ UserDefaults (currency setting)
- ✅ Keychain (Apple user ID - unused)
- ❌ No user data storage yet

### Next Steps:

#### Phase 1: Wishlists (This Week)
1. ✅ SwiftData models created (`WishlistItem.swift`)
2. ✅ Model container added to app (`PokeTrackApp.swift`)
3. ✅ WishlistService with premium gating
4. ⏳ Build wishlist UI
5. ⏳ Test CloudKit sync

#### Phase 2: Collections (Next Sprint)
1. ⏳ Build collection management UI
2. ⏳ Integrate with existing card catalog
3. ⏳ Add import/export for backup

#### Phase 3: Transactions (Future)
1. ⏳ Transaction entry UI
2. ⏳ Reports and analytics
3. ⏳ Export to CSV

#### Phase 4: Settings Sync (Optional)
1. ⏳ Integrate CloudSettingsService
2. ⏳ Sync currency across devices
3. ⏳ Add "Reset to Cloud Settings" button

---

## Privacy Considerations

### What You Need to Declare:
- **iCloud:** "Your wishlists and collections are stored in your iCloud account"
- **StoreKit:** "Purchase history is managed by Apple"

### What Users Control:
- iCloud sync: Settings → iCloud → iCloud Drive → PokeTrack (on/off)
- Storage: Uses their iCloud storage quota

### Data Deletion:
If user deletes the app:
- SwiftData: Deleted from device
- CloudKit: Remains in iCloud (can be deleted via Settings → Apple ID → iCloud → Manage Storage)
- Purchases: Always recoverable via "Restore Purchases"

---

## Testing iCloud Sync

### Simulator:
1. Sign into iCloud on simulator
2. Run app, add wishlist items
3. Open second simulator, sign into same iCloud account
4. Launch app → items should sync automatically

### Real Devices:
1. Same process as simulator
2. Better for testing cellular vs Wi-Fi sync
3. Can test what happens when offline

### CloudKit Dashboard:
- [https://icloud.developer.apple.com/](https://icloud.developer.apple.com/)
- View synced data
- Manually delete records for testing
- Monitor sync errors

---

## Common Issues & Solutions

### "iCloud not available"
- User not signed into iCloud
- App doesn't have iCloud capability enabled
- User disabled iCloud Drive for your app

### Data not syncing
- Check `FileManager.default.ubiquityIdentityToken != nil`
- Verify CloudKit container name matches
- Check for schema mismatches between devices

### Sync conflicts
- SwiftData handles automatically
- Last-write-wins by default
- For complex conflict resolution, use CloudKit directly

---

## Code Examples

### Check if iCloud is available:
```swift
var isICloudAvailable: Bool {
    FileManager.default.ubiquityIdentityToken != nil
}
```

### Access SwiftData from a View:
```swift
struct WishlistView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WishlistItem.dateAdded) private var items: [WishlistItem]
    
    var body: some View {
        List(items) { item in
            Text(item.cardID)
        }
    }
}
```

### Add to wishlist with premium check:
```swift
Button("Add to Wishlist") {
    do {
        try wishlistService.addItem(cardID: "sv3pt5-1")
    } catch WishlistError.limitReached {
        // Show paywall
        showPaywall = true
    } catch {
        // Show error
    }
}
```

---

## Recommended Changes to Existing Code

### AccountView.swift:
**Option 1:** Remove "Sign in with Apple" section (not needed yet)
**Option 2:** Add explanation that it's optional

### PriceDisplaySettings.swift:
Optionally integrate with `CloudSettingsService` to sync across devices:
```swift
// In AppServices.swift
let cloudSettings = CloudSettingsService()

// In PriceDisplaySettings.swift
var currency: PriceDisplayCurrency {
    didSet {
        UserDefaults.standard.set(currency.rawValue, forKey: Self.defaultsKey)
        // Optionally sync to iCloud
        cloudSettings?.saveCurrency(currency)
    }
}
```

---

## Summary & Recommendations

### What to Do Right Now:

1. **Enable iCloud capability in Xcode** (if not already done)
   - Target → Signing & Capabilities → + iCloud → ☑️ CloudKit

2. **Build wishlist UI** using the provided models and service

3. **Test on two devices** signed into same iCloud to verify sync

4. **Keep "Sign in with Apple" for now** but add a note in UI that it's optional

5. **Save settings locally only** for now (UserDefaults is fine)

### What to Do Later:

6. **Add collections & transactions** when wishlists are working

7. **Consider Sign in with Apple** only if you build a web portal or backend

8. **Sync settings via CloudSettingsService** if users request it

9. **Add export/import** as a backup option for users who don't use iCloud

---

## Questions?

- **Will this work offline?** Yes! SwiftData works offline, syncs when online
- **What if user isn't signed into iCloud?** Data saves locally, syncs when they sign in
- **Can I test without paying for iCloud storage?** Yes, Apple provides free developer testing
- **Do I need to handle sync conflicts?** SwiftData/CloudKit handle this automatically
- **Can users access data on web?** Not with this approach (would need Sign in with Apple + custom backend)
