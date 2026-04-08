# PokeTrack iCloud Setup Checklist

## ✅ Xcode Configuration

### 1. Enable iCloud Capability
- [ ] Open your project in Xcode
- [ ] Select your target (PokeTrack)
- [ ] Go to "Signing & Capabilities" tab
- [ ] Click "+ Capability"
- [ ] Add "iCloud"
- [ ] Check ✅ "CloudKit"
- [ ] Xcode will create container: `iCloud.app1xy.PokeTrack`

### 2. Verify Entitlements
After enabling iCloud, Xcode should create/update `PokeTrack.entitlements`:
```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.app1xy.PokeTrack</string>
</array>
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
</array>
```

### 3. Update Info.plist (Optional)
Add usage description for clarity:
```xml
<key>NSUbiquitousContainers</key>
<dict>
    <key>iCloud.app1xy.PokeTrack</key>
    <dict>
        <key>NSUbiquitousContainerName</key>
        <string>PokeTrack</string>
        <key>NSUbiquitousContainerIsDocumentScopePublic</key>
        <false/>
    </dict>
</dict>
```

---

## ✅ Code Integration

### Files Already Created:
- [x] `WishlistItem.swift` - SwiftData models
- [x] `WishlistService.swift` - Business logic with premium gating
- [x] `CloudSettingsService.swift` - Settings sync (optional)
- [x] `WishlistView.swift` - Example UI
- [x] `PokeTrackApp.swift` - Updated with model container
- [x] `AppServices.swift` - Updated with wishlist service

### Files You Need to Update:

#### 1. Update AccountView.swift
**Option A:** Remove Sign in with Apple (not needed)
**Option B:** Add explanation:

```swift
Section("Sign in with Apple") {
    Text("Sign in with Apple is currently not required.")
        .font(.caption)
        .foregroundStyle(.secondary)
    
    Text("Your data is saved to your iCloud account automatically when you're signed into iCloud on your device (Settings → [Your Name]).")
        .font(.caption)
        .foregroundStyle(.secondary)
    
    // Keep existing Sign in with Apple button for future use
}
```

#### 2. Integrate WishlistView into your app navigation
Find where you have your main navigation (probably in `RootView.swift`) and add:
```swift
NavigationLink {
    WishlistView()
} label: {
    Label("Wishlist", systemImage: "star")
}
```

#### 3. Add iCloud status to AccountView (Optional)
```swift
Section("iCloud Sync") {
    if services.cloudSettings.isICloudAvailable {
        Label("iCloud connected", systemImage: "checkmark.icloud")
            .foregroundStyle(.green)
        Text("Your wishlists and collections sync automatically across your devices.")
            .font(.caption)
            .foregroundStyle(.secondary)
    } else {
        Label("iCloud not available", systemImage: "exclamationmark.icloud")
            .foregroundStyle(.orange)
        Text("Sign into iCloud in Settings to sync your data across devices.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

---

## ✅ Testing

### Test on Simulator:
1. [ ] Run app on simulator
2. [ ] Sign into iCloud (you may need to create test Apple ID)
3. [ ] Add wishlist items
4. [ ] Launch second simulator with same iCloud account
5. [ ] Verify items sync automatically

### Test on Real Device:
1. [ ] Install app on iPhone/iPad
2. [ ] Add wishlist items
3. [ ] Open CloudKit Dashboard (https://icloud.developer.apple.com/)
4. [ ] Verify data appears in CloudKit

### Test Premium Gating:
1. [ ] Without premium: Try adding 6th wishlist item
2. [ ] Should show paywall
3. [ ] With premium: Add unlimited items
4. [ ] Should work

### Test Offline Sync:
1. [ ] Enable Airplane Mode
2. [ ] Add wishlist items (saves locally)
3. [ ] Disable Airplane Mode
4. [ ] Items should sync to iCloud

---

## ✅ App Store Preparation

### Privacy Manifest (Required for App Store)
Create `PrivacyInfo.xcprivacy`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyCollectedDataTypes</key>
    <array>
        <!-- Add if you use Sign in with Apple -->
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeEmailAddress</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <false/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
            </array>
        </dict>
    </array>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

### App Privacy Details (App Store Connect):
When submitting to App Store, declare:
- **Data Linked to User:** None (if not using Sign in with Apple backend)
- **Data Not Linked to User:** Purchases (handled by Apple)
- **Data Stored in iCloud:** User's own iCloud account

---

## ✅ Common Issues & Solutions

### "Model container failed to initialize"
**Problem:** SwiftData models not found
**Solution:** Make sure all model classes are in your target's "Compile Sources"

### "CloudKit sync not working"
**Problem:** Container name mismatch
**Solution:** Check that `iCloud.app1xy.PokeTrack` matches your bundle ID prefix

### "iCloud not available" on simulator
**Problem:** Not signed into iCloud
**Solution:** iOS Simulator → Settings → Sign in with Apple ID (can use test account)

### Data not syncing between devices
**Problem:** Network delay or schema mismatch
**Solution:** 
- Wait 30 seconds for sync
- Check both devices have internet
- Verify same iCloud account on both devices

### "Wishlist service is nil"
**Problem:** `setupWishlist()` not called
**Solution:** Make sure `WishlistView` calls `services.setupWishlist(modelContext:)` in `.onAppear`

---

## ✅ Next Steps

### Immediate (This Week):
1. [ ] Enable iCloud in Xcode
2. [ ] Test wishlist on simulator
3. [ ] Integrate WishlistView into navigation
4. [ ] Test premium gating

### Short Term (Next Week):
5. [ ] Build collection management UI
6. [ ] Integrate with existing card catalog
7. [ ] Add card search to "Add to Wishlist" sheet
8. [ ] Test multi-device sync

### Future:
9. [ ] Add transaction logging
10. [ ] Build analytics/reports
11. [ ] Add export to CSV
12. [ ] Consider Sign in with Apple if building web portal

---

## ✅ Resources

- **CloudKit Dashboard:** https://icloud.developer.apple.com/
- **SwiftData Documentation:** https://developer.apple.com/documentation/swiftdata
- **CloudKit Documentation:** https://developer.apple.com/documentation/cloudkit
- **Testing iCloud:** https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitQuickStart/TestingYourCloudKitApp/TestingYourCloudKitApp.html

---

## ✅ Questions?

### "Do I need to pay for iCloud storage?"
No, users use their own iCloud storage quota. Development/testing is free.

### "What if user runs out of iCloud storage?"
They'll get a notification from iOS. Your app continues working with local data only (no sync).

### "Can I see what's stored in CloudKit?"
Yes, via CloudKit Dashboard. You can view, edit, and delete records.

### "How do I handle users switching iCloud accounts?"
SwiftData handles this automatically. Data from old account stops syncing, data from new account starts syncing.

### "Should I keep Sign in with Apple?"
Keep the code but consider hiding it from UI until you need a backend server.

---

## ✅ Status Tracker

Mark completed items with ✅:

- [ ] iCloud capability enabled
- [ ] Tested on simulator
- [ ] Tested on real device
- [ ] Wishlist UI integrated
- [ ] Premium gating tested
- [ ] Multi-device sync tested
- [ ] AccountView updated
- [ ] Privacy manifest created
- [ ] Ready for App Store
