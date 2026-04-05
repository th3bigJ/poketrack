Context
The user has an existing Next.js web app (TCG collection tracker) and wants to build a companion native iOS app (iPhone + iPad) from scratch using Swift/SwiftUI. The web app stays live. The iOS app shares the same R2 pricing backend but replaces Supabase with iCloud/SwiftData for user data and Sign in with Apple for auth. The user is new to Swift so this plan includes detail on Swift-specific patterns.
Key decisions:

SwiftData + CloudKit for all user data (synced across devices automatically)
Sign in with Apple (no Supabase, no JWT, no cookies)
R2 public CDN for card images and pricing JSON (read-only, no credentials in app)
Hybrid card data: bundle current sets in app, fetch new sets from R2 at launch
CKShare for collection sharing between users
Apple Vision framework for card scanner (replaces Tesseract.js + ONNX)
Swift Charts for portfolio history
StoreKit 2 for freemium in-app purchases
WidgetKit for home screen portfolio widget
Universal app: iPhone + iPad with adaptive layouts
Minimum deployment: iOS 17 (required for mature SwiftData)


Freemium Split
FreePremium (in-app purchase)Card browsing & searchCollection beyond 10 cards (unlimited)Collection up to 10 cardsCard scannerWishlist (unlimited)Portfolio history chartsCurrent portfolio valueCollection sharing (CKShare)Sealed products inventoryTransaction historyHome screen widget
Key gates:

On add card: check collectionCards.count >= 10 → show upgrade prompt if not premium
Scanner: show upgrade prompt on tap if not premium (can show UI, just gate the session start)
All other premium features hidden behind a "Premium" badge with unlock prompt


Project Structure
TCGApp/
├── App/
│   ├── TCGApp.swift              # Entry point, ModelContainer + CloudKit setup
│   └── AppDelegate.swift         # CKShare acceptance handling
├── Models/                       # SwiftData models (auto-sync to iCloud)
│   ├── CollectionCard.swift
│   ├── WishlistItem.swift
│   ├── SealedItem.swift
│   ├── Transaction.swift
│   ├── PortfolioSnapshot.swift
│   └── UserPreferences.swift
├── Data/
│   ├── CardDataService.swift     # Hybrid JSON loading (bundle + R2 fetch)
│   ├── PricingService.swift      # Fetches pricing/{setCode}.json from R2
│   └── Static/                  # Bundled card JSON files (current sets)
├── Features/
│   ├── Collection/               # Add/edit/delete cards, grid view
│   ├── Wishlist/                 # Wishlist management
│   ├── Sealed/                   # Sealed products (premium)
│   ├── Portfolio/                # Value dashboard + Swift Charts (history premium)
│   ├── Scanner/                  # Vision framework card scanner
│   ├── Sharing/                  # CKShare management (premium)
│   ├── Cards/                    # Browse/search all cards
│   └── Account/                  # Sign in with Apple, preferences, purchases
├── Components/                   # Reusable SwiftUI views (CardGridItem, PriceTag etc)
├── Services/
│   ├── CloudKitSharingService.swift
│   └── StoreKitService.swift     # StoreKit 2 purchase handling
└── Widget/                       # Separate Xcode target for WidgetKit

Build Phases (in order)
Phase 1 — Foundation (Week 1)

Xcode project setup

New SwiftUI project, iOS 17 minimum, Universal (iPhone + iPad)
Add CloudKit capability in Signing & Capabilities
Add iCloud capability, enable CloudKit
Configure CloudKit container identifier (e.g. iCloud.com.yourname.tcg)


SwiftData models

swift   @Model class CollectionCard {
       var masterCardId: String
       var setCode: String
       var quantity: Int
       var printing: String       // "Normal", "Holo", "Reverse Holo"
       var language: String
       var conditionId: String
       var purchaseType: String
       var pricePaid: Double?
       var unlistedPrice: Double?
       var gradingCompany: String?
       var gradeValue: String?
       var gradedImageUrl: String?
       var gradedSerial: String?
       var addedAt: Date
   }

   @Model class WishlistItem {
       var masterCardId: String
       var priority: Int
       var targetConditionId: String?
       var targetPrinting: String?
       var addedAt: Date
   }

   @Model class SealedItem { ... }
   @Model class Transaction { ... }
   @Model class PortfolioSnapshot { var date: Date; var valueGBP: Double }

ModelContainer setup in TCGApp.swift

swift   @main struct TCGApp: App {
       let container: ModelContainer = {
           let schema = Schema([CollectionCard.self, WishlistItem.self, ...])
           let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
           return try! ModelContainer(for: schema, configurations: [config])
       }()
       var body: some Scene {
           WindowGroup { ContentView() }
               .modelContainer(container)
       }
   }

Sign in with Apple

ASAuthorizationAppleIDButton on onboarding screen
Store Apple user ID in Keychain (not UserDefaults)
No server call needed — identity is the Apple user ID
AuthenticationServices framework, no third-party SDK



Phase 2 — Card Data & Pricing (Week 1-2)

Hybrid card data loading (CardDataService.swift)

Bundle current sets JSON in app (copy from /data/cards/*.json)
On launch: fetch https://cdn.yourdomain.com/sets.json from R2 to check for new sets
If new set found that's not bundled → fetch and cache to Documents/ directory
@Observable class with cards: [String: [Card]] dictionary keyed by setCode


Pricing service (PricingService.swift)

Fetch https://cdn.yourdomain.com/pricing/{setCode}.json per set (same R2 path as web)
Cache to disk with 24hr TTL
GBP conversion using fetched rate (or fallback constant)
Async/await with URLSession


Static data models (Codable structs, NOT SwiftData)

swift   struct Card: Codable, Identifiable {
       var masterCardId: String
       var setCode: String
       var cardNumber: String
       var cardName: String
       var rarity: String
       var elementTypes: [String]
       // etc.
   }
Phase 3 — Core UI (Weeks 2-4)

Tab bar structure

swift   TabView {
       CollectionView()     .tabItem { Label("Collection", systemImage: "square.grid.2x2") }
       WishlistView()       .tabItem { Label("Wishlist", systemImage: "heart") }
       CardsView()          .tabItem { Label("Cards", systemImage: "rectangle.stack") }
       PortfolioView()      .tabItem { Label("Portfolio", systemImage: "chart.line.uptrend.xyaxis") }
       AccountView()        .tabItem { Label("Account", systemImage: "person.circle") }
   }

Collection grid — LazyVGrid with GridItem(.adaptive(minimum: 100)), AsyncImage for card images from R2, @Query to fetch SwiftData records
iPad adaptation — Use NavigationSplitView on iPad (sidebar + detail), NavigationStack on iPhone. SwiftUI handles this with horizontalSizeClass environment value.
Add/Edit card sheet — Same fields as web app (condition, printing, language, price paid, grading)
Card search & browse — Filter/search across bundled + cached card JSON, sorted by set/number

Phase 4 — Portfolio (Week 3-4)

Portfolio dashboard

Current total value in GBP (sum of collection × latest prices)
Top cards by value
Set breakdown


Portfolio history charts (premium feature)

Chart from Swift Charts framework
Data from PortfolioSnapshot SwiftData records
Nightly snapshot: app takes snapshot when opened after midnight (no server cron needed for this)



Phase 5 — Card Scanner (Week 4-5)

Vision framework scanner

AVCaptureSession for camera feed
VNRecognizeTextRequest to OCR card name + number from live feed
Match OCR result against card JSON index (card name → card lookup)
Much cleaner than Tesseract.js — Apple handles model updates
NSCameraUsageDescription in Info.plist required



Phase 6 — Sealed Products (Week 5, premium)

Same CRUD pattern as collection but for SealedItem SwiftData model
Sealed pricing fetched from R2 (same scraper writes sealed-pricing.json)

Phase 7 — Transactions (Week 5-6, premium)

Transaction SwiftData model: type (purchase/trade/pack), date, notes, amount
Simple list view with add/edit

Phase 8 — Collection Sharing (Week 6, premium)

CKShare implementation

Owner creates CKShare for their collection zone
Standard iOS share sheet to send link (no hardcoded channel)
Recipient taps link → app opens → userDidAcceptCloudKitShareWith in AppDelegate
Recipient views owner's collection/wishlist read-only
Owner manages active shares (list + revoke)
CloudKitSharingService.swift wraps CKContainer operations



Phase 9 — Widget (Week 6-7, premium)

WidgetKit target — separate Xcode target, shares SwiftData container

Small widget: current portfolio value + daily change
Medium widget: top 3 cards by value
AppIntentTimelineProvider for automatic refresh



Phase 10 — StoreKit 2 & Polish (Week 7)

StoreKit 2 setup

swift    @Observable class StoreKitService {
        var isPremium: Bool = false
        func purchase(_ productId: String) async throws { ... }
        func restorePurchases() async throws { ... }
    }
- Single "TCG Premium" product ID configured in App Store Connect
- Gate premium features with `if storeKitService.isPremium`
- Restore purchases button in Account tab
23. Privacy Manifest (PrivacyInfo.xcprivacy) — declare camera usage, iCloud sync, no third-party tracking

App Store assets — icon (1024×1024), screenshots for 6.9" iPhone and 11" iPad


What the Existing Scraper Backend Needs (minimal changes)

Add sealed-pricing.json endpoint to R2 if not already there
No auth changes (R2 stays public read)
Web app continues running independently — no conflicts


Key Swift Patterns (new to Swift)

@Model — marks a class as a SwiftData persistent model
@Query — fetches SwiftData records reactively in a SwiftUI view
@Observable — replaces @ObservableObject, triggers view updates
@Environment(\.modelContext) — access the SwiftData context for insert/delete
async/await — used for all network calls (no callbacks)
NavigationStack — push/pop navigation on iPhone
NavigationSplitView — sidebar/detail split on iPad


Verification Checklist

 Sign in with Apple works on device (not just simulator)
 Collection cards persist after app restart
 Collection syncs between two devices via iCloud
 Pricing JSON fetched and displayed correctly from R2
 New set JSON fetched and cached from R2 (test with a fake new set entry)
 Card scanner identifies a card correctly
 CKShare link opens app and shows owner collection read-only
 Widget updates portfolio value on home screen
 Premium purchase gates correct features
 iPad NavigationSplitView works correctly
 App passes App Store privacy checks (no issues in Xcode Organizer)