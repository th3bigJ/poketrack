# Quick Fix: Build Errors

## ❌ The Problem
You're seeing errors like:
- "Cannot find 'WishlistItem' in scope"
- "Cannot find 'CloudSettingsService' in scope"
- "Cannot infer key path type from context"

## ✅ The Solution
You need to manually create these 2 files in Xcode:

---

## 1️⃣ Create WishlistModels.swift

**Steps:**
1. In Xcode, right-click your project folder
2. **New File** → **Swift File**
3. Name it: `WishlistModels.swift`
4. Make sure **PokeTrack target is checked**
5. Paste this code:

```swift
import Foundation
import SwiftData

/// A card that the user wants to collect
@Model
final class WishlistItem {
    var cardID: String
    var dateAdded: Date
    var notes: String
    var collectionName: String?
    
    init(cardID: String, dateAdded: Date = Date(), notes: String = "", collectionName: String? = nil) {
        self.cardID = cardID
        self.dateAdded = dateAdded
        self.notes = notes
        self.collectionName = collectionName
    }
}

/// A card in the user's collection (for future use)
@Model
final class CollectionItem {
    var cardID: String
    var dateAcquired: Date
    var purchasePrice: Double?
    var condition: String
    var quantity: Int
    var notes: String
    
    @Relationship(deleteRule: .cascade, inverse: \TransactionRecord.collectionItem)
    var transactions: [TransactionRecord] = []
    
    init(
        cardID: String,
        dateAcquired: Date = Date(),
        purchasePrice: Double? = nil,
        condition: String = "Near Mint",
        quantity: Int = 1,
        notes: String = ""
    ) {
        self.cardID = cardID
        self.dateAcquired = dateAcquired
        self.purchasePrice = purchasePrice
        self.condition = condition
        self.quantity = quantity
        self.notes = notes
    }
}

/// Transaction log (for future use)
@Model
final class TransactionRecord {
    var id: UUID
    var date: Date
    var type: String
    var amountUSD: Double
    var notes: String
    var collectionItem: CollectionItem?
    
    init(
        id: UUID = UUID(),
        date: Date = Date(),
        type: String,
        amountUSD: Double,
        notes: String = ""
    ) {
        self.id = id
        self.date = date
        self.type = type
        self.amountUSD = amountUSD
        self.notes = notes
    }
}
```

---

## 2️⃣ Create CloudSettingsService.swift

**Steps:**
1. In Xcode, right-click your project folder
2. **New File** → **Swift File**
3. Name it: `CloudSettingsService.swift`
4. Make sure **PokeTrack target is checked**
5. Paste this code:

```swift
import Foundation
import Observation

/// Syncs user preferences to iCloud
@Observable
@MainActor
final class CloudSettingsService {
    private let store = NSUbiquitousKeyValueStore.default
    
    private enum Keys {
        static let currency = "priceDisplayCurrency"
    }
    
    init() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.handleExternalChange()
        }
        store.synchronize()
    }
    
    func saveCurrency(_ currency: PriceDisplayCurrency) {
        store.set(currency.rawValue, forKey: Keys.currency)
        store.synchronize()
    }
    
    func loadCurrency() -> PriceDisplayCurrency? {
        guard let raw = store.string(forKey: Keys.currency) else { return nil }
        return PriceDisplayCurrency(rawValue: raw)
    }
    
    var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
    
    private func handleExternalChange() {
        NotificationCenter.default.post(name: .cloudSettingsDidChange, object: nil)
    }
}

extension Notification.Name {
    static let cloudSettingsDidChange = Notification.Name("cloudSettingsDidChange")
}
```

---

## 3️⃣ Clean and Rebuild

After creating both files:

1. **Product** → **Clean Build Folder** (Cmd + Shift + K)
2. **Product** → **Build** (Cmd + B)
3. All errors should be gone!

---

## ✅ Files Already Fixed

These files are already updated and should work:
- ✅ `PokeTrackApp.swift` - Model container added
- ✅ `AppServices.swift` - CloudSettingsService integrated
- ✅ `WishlistService.swift` - Premium gating logic
- ✅ `WishlistView.swift` - Fixed usdToGbp reference

---

## 🎯 After This Works

Once the build is clean:

1. **Enable iCloud in Xcode**
   - Target → Signing & Capabilities → + Capability → iCloud
   - Check ✅ CloudKit

2. **Fix the Team Issue**
   - Select your **paid developer team** (not "Personal Team")
   - See `FIX_PERSONAL_TEAM_ERROR.md` for details

3. **Test the app**
   - Run on simulator
   - Try adding wishlist items

---

## 🐛 If You Still Get Errors

### Error: "Cannot find type 'Card'"
The `WishlistView.swift` example references your existing `Card` type. If you haven't integrated it with your card catalog yet, you can comment out the card loading section temporarily.

### Error: Missing target membership
Right-click each new file → **Target Membership** → Check ✅ **PokeTrack**

### Error: Module not found
Make sure you have `import SwiftData` at the top of files that use `@Model`

---

## 📝 Quick Reference

**Files you need to create manually:**
1. `WishlistModels.swift` - SwiftData models
2. `CloudSettingsService.swift` - iCloud settings sync

**Files already updated:**
- ✅ PokeTrackApp.swift
- ✅ AppServices.swift  
- ✅ WishlistService.swift
- ✅ WishlistView.swift

**Next steps:**
1. Create the 2 files above
2. Clean build (Cmd + Shift + K)
3. Build (Cmd + B)
4. Enable iCloud capability
5. Fix team selection issue
