This document describes a Pokémon TCG collection tracker app. Use it as full context when helping build the iOS version from scratch.

What the App Does
A Pokémon Trading Card Game collection management tool for collectors. Users can:

Track their card collection (what they own, condition, printing, price paid, grading)
Track a wishlist of cards they want
Browse all Pokémon TCG cards and sets
See current market prices (GBP) for their cards
View portfolio value over time with historical charts
Track sealed products (booster boxes, ETBs) with market pricing
Log transactions (purchases, trades, pack openings)
Share their collection with other users (read-only)
Scan physical cards with camera to identify and add them


Current Web App Tech Stack (for reference — iOS replaces this)

Frontend: Next.js 16 + React 19 + TypeScript + Tailwind CSS
Backend: Next.js App Router API routes (78 endpoints)
Database: Supabase (PostgreSQL) for user data
Auth: Supabase Auth (JWT/cookie-based)
Storage: Cloudflare R2 (S3-compatible) for card images, pricing JSON, sealed product data
Scraping: Nightly Node.js jobs scrape Scrydex/Pokedata, write results to R2
Currency: All prices displayed in GBP, sourced in USD from scrapers, converted via Frankfurter API


iOS App Stack (what we're building)

Language: Swift 5.10+, SwiftUI
Minimum iOS: 17.0 (required for mature SwiftData)
Devices: iPhone + iPad (universal)
User data storage: SwiftData + CloudKit (private database, synced across user's devices)
Auth: Sign in with Apple (AuthenticationServices framework)
Shared/static data: Cloudflare R2 (public CDN, read-only from app — no credentials in app)
Card data strategy: Hybrid — current sets bundled in app, new sets fetched from R2 and cached to disk
Currency: GBP display, fetch rate from https://api.frankfurter.app/latest?from=GBP&to=USD,EUR
FX fallback: USD→GBP = 0.79, EUR→GBP = 0.85


R2 Data Sources (public CDN, no auth required)
Replace {R2_BASE} with your Cloudflare R2 custom domain or r2.dev URL.
AssetURL PatternCard image (low res){R2_BASE}/cards/{setCode}-{localId}-low.pngCard image (high res){R2_BASE}/cards/{setCode}-{localId}-high.pngSet logo{R2_BASE}/{logoSrc} (e.g. sets/logo/sv01.webp)Set symbol{R2_BASE}/{symbolSrc} (e.g. sets/symbol/sv01.webp)Sets manifest{R2_BASE}/sets.json (used to detect new sets)Card pricing (per set){R2_BASE}/pricing/{setCode}.json — refresh daily, cache 24hSealed product catalog{R2_BASE}/sealed-products/pokedata/pokedata-english-pokemon-products.jsonSealed product prices{R2_BASE}/sealed-products/pokedata/pokedata-english-pokemon-prices.json

Static Data: Card JSON Schema
Each set has a JSON file ({setCode}.json) containing an array of cards. There are ~174 sets.
swiftstruct Card: Codable, Identifiable {
    var id: String { masterCardId }
    let masterCardId: String       // Internal stable ID (e.g. "918")
    let externalId: String?        // TCGdex ID (e.g. "base1-102") — used as pricing lookup key
    let tcgdex_id: String?         // Alt TCGdex reference
    let localId: String?           // Card's position within set (e.g. "102")
    let setCode: String            // Set identifier (e.g. "base1", "sv04pt")
    let setTcgdexId: String?       // TCGdex set ID for this card
    let cardNumber: String         // Display number (e.g. "102/102")
    let cardName: String           // Display name (e.g. "Charizard")
    let fullDisplayName: String?   // e.g. "Charizard 4/102 Base Set"
    let rarity: String?            // e.g. "Rare Holo", "Common", "Ultra Rare"
    let category: String?          // "Pokémon", "Trainer", "Energy"
    let stage: String?             // "Basic", "Stage 1", "Stage 2", "VMAX" etc.
    let hp: Int?
    let elementTypes: [String]?    // e.g. ["Fire"], ["Water", "Fighting"]
    let dexIds: [Int]?             // National Pokédex numbers
    let subtypes: [String]?
    let trainerType: String?       // e.g. "Item", "Supporter", "Stadium"
    let energyType: String?        // e.g. "Basic", "Special"
    let regulationMark: String?    // e.g. "G", "H", "I"
    let evolveFrom: String?        // Name of the Pokémon this evolves from
    let artist: String?
    let isActive: Bool
    let noPricing: Bool            // true = skip pricing lookups for this card
    let imageLowSrc: String        // Relative path: "cards/base1-102-low.png"
    let imageHighSrc: String?      // Relative path: "cards/base1-102-high.png"
}

Static Data: Set JSON Schema
sets.json — array of all sets, also available at {R2_BASE}/sets.json.
swiftstruct TCGSet: Codable, Identifiable {
    var id: String { tcgdexId ?? internalId }
    let internalId: String         // JSON field: "id" — internal numeric ID as string
    let name: String               // e.g. "Scarlet & Violet"
    let slug: String               // e.g. "scarlet-violet"
    let code: String?              // Set code if available
    let tcgdexId: String?          // e.g. "sv01" — used as setCode for R2 paths
    let releaseDate: String?       // ISO8601 string
    let isActive: Bool
    let cardCountTotal: Int?
    let cardCountOfficial: Int?
    let seriesName: String?        // e.g. "Scarlet & Violet"
    let seriesSlug: String?
    let logoSrc: String            // Relative path for logo image
    let symbolSrc: String?         // Relative path for symbol image

    enum CodingKeys: String, CodingKey {
        case internalId = "id"
        case name, slug, code, tcgdexId, releaseDate, isActive
        case cardCountTotal, cardCountOfficial, seriesName, seriesSlug
        case logoSrc, symbolSrc
    }
}

Pricing JSON Schema
File: {R2_BASE}/pricing/{setCode}.json
Top-level is a dictionary keyed by externalId (TCGdex card ID, e.g. "base1-4").
swift// SetPricingMap = [String: CardPricingEntry]
struct CardPricingEntry: Codable {
    let scrydex: ScrydexCardPricing?   // Scrydex pricing data
    let tcgplayer: AnyCodable?         // TCGPlayer pricing (already converted to GBP by scraper)
    let cardmarket: AnyCodable?        // Cardmarket pricing (already converted to GBP by scraper)
}

// ScrydexCardPricing = [variantKey: ScrydexVariantPricing]
// variantKey examples: "normal", "holofoil", "reverseHolofoil", "firstEdition"
struct ScrydexVariantPricing: Codable {
    let raw: Double?     // Raw ungraded price in USD (NOT yet converted)
    let psa10: Double?   // PSA 10 grade price in USD
    let ace10: Double?   // ACE 10 grade price in USD
}
Important: Scrydex prices are in USD — multiply by usdToGbp to convert. TCGPlayer/Cardmarket values in the JSON are already stored as GBP by the nightly scraper.
Pricing lookup key: Use card.externalId to look up in the pricing map. The external ID format is {setCode}-{localId} (e.g. "base1-4"). Some older sets use unpadded numbers.

Sealed Products JSON Schema
Catalog: {R2_BASE}/sealed-products/pokedata/pokedata-english-pokemon-products.json
swiftstruct SealedProductCatalogPayload: Codable {
    let scrapedAt: String
    let products: [SealedProductEntry]
}

struct SealedProductEntry: Codable, Identifiable {
    let id: Int
    let name: String
    let tcg: String?
    let language: String?
    let type: String?          // "BOOSTERBOX", "ELITETRAINERBOX", "BOOSTERPACK", "TIN" etc.
    let release_date: String?
    let year: Int?
    let series: String?
    let set_id: Int?
    let live: Bool             // Currently available
    let hot: Int               // Popularity score
    let image: SealedProductImage
}

struct SealedProductImage: Codable {
    let source_url: String?
    let r2_key: String?
    let public_url: String?    // Prefer this for image URL
}
Prices: {R2_BASE}/sealed-products/pokedata/pokedata-english-pokemon-prices.json
swiftstruct SealedProductPricesPayload: Codable {
    let prices: [String: SealedProductPriceEntry]  // Key is product ID as string
}

struct SealedProductPriceEntry: Codable {
    let id: Int
    let market_value: Double?   // USD — multiply by usdToGbp to convert
    let currency: String        // "USD"
    let live: Bool
}

Reference Data (hardcode these in Swift)
Card Conditions
swiftenum CardCondition: String, CaseIterable, Codable {
    case nearMint        = "near-mint"
    case lightlyPlayed   = "lightly-played"
    case moderatelyPlayed = "moderately-played"
    case heavilyPlayed   = "heavily-played"
    case damaged         = "damaged"
    case graded          = "graded-card"

    var displayName: String {
        switch self {
        case .nearMint:         return "Near Mint"
        case .lightlyPlayed:    return "Lightly Played"
        case .moderatelyPlayed: return "Moderately Played"
        case .heavilyPlayed:    return "Heavily Played"
        case .damaged:          return "Damaged"
        case .graded:           return "Graded"
        }
    }
}
Card Printings / Variants
Storage values (what gets saved) — display name in parentheses:

"Standard" (Standard / Normal)
"Holo" (Holofoil)
"Reverse Holo" (Reverse Holofoil)
"First Edition" (1st Edition)
"First Edition Holo" (1st Edition Holo)
"Unlimited" (Unlimited)
"Unlimited Holo" (Unlimited Holo)
"Shadowless" (Shadowless)
"Pokemon Day Stamp" (Pokémon Day Stamp)
"Pokémon Center Stamp" (Pokémon Center Stamp)
"Staff Stamp" (Staff Stamp)

These map to Scrydex pricing variant keys:
Standard→normal, Holo→holofoil, Reverse Holo→reverseHolofoil, etc.
Purchase Types
swiftenum PurchaseType: String, CaseIterable, Codable {
    case bought = "bought"
    case traded = "traded"
    case packed = "packed"   // Pulled from a pack
}
Sealed Product Types
Used to categorise sealed items in collection:

single-card, graded-card, booster-pack, elite-trainer-box
booster-box, collection-box, tin, premium-collection, other

Map from Pokedata type strings:

BOOSTERPACK / BLISTERPACK → booster-pack
ELITETRAINERBOX → elite-trainer-box
BOOSTERBOX → booster-box
COLLECTIONBOX / COLLECTIONCHEST / PINCOLLECTION → collection-box
TIN → tin
PREMIUMTRAINERBOX / SPECIALBOX → premium-collection
everything else → other


SwiftData Models
swiftimport SwiftData
import Foundation

@Model
class CollectionCard {
    var id: UUID
    var masterCardId: String       // Links to Card.masterCardId in static JSON
    var setCode: String            // For loading card details from bundled/cached JSON
    var quantity: Int
    var printing: String           // One of the printing values above (e.g. "Holo")
    var language: String           // e.g. "English", "Japanese"
    var conditionId: String        // CardCondition.rawValue
    var purchaseType: String?      // PurchaseType.rawValue
    var pricePaid: Double?         // GBP
    var purchaseDate: Date?
    var unlistedPrice: Double?     // Manual override price in GBP
    var gradingCompany: String?    // e.g. "PSA", "CGC", "ACE"
    var gradeValue: String?        // e.g. "10", "9.5", "Authentic"
    var gradedImageUrl: String?    // Custom photo URL if user uploaded one
    var gradedSerial: String?      // Grading cert serial number
    var addedAt: Date

    init(masterCardId: String, setCode: String, quantity: Int = 1,
         printing: String = "Standard", language: String = "English",
         conditionId: String = "near-mint", addedAt: Date = .now) {
        self.id = UUID()
        self.masterCardId = masterCardId
        self.setCode = setCode
        self.quantity = quantity
        self.printing = printing
        self.language = language
        self.conditionId = conditionId
        self.addedAt = addedAt
    }
}

@Model
class WishlistItem {
    var id: UUID
    var masterCardId: String
    var setCode: String
    var priority: Int              // 1 = highest priority
    var targetConditionId: String? // CardCondition.rawValue
    var targetPrinting: String?
    var notes: String?
    var addedAt: Date

    init(masterCardId: String, setCode: String, priority: Int = 3, addedAt: Date = .now) {
        self.id = UUID()
        self.masterCardId = masterCardId
        self.setCode = setCode
        self.priority = priority
        self.addedAt = addedAt
    }
}

@Model
class SealedCollectionItem {
    var id: UUID
    var pokedataProductId: Int     // Links to SealedProductEntry.id
    var productName: String        // Stored locally for offline display
    var productType: String        // e.g. "elite-trainer-box"
    var quantity: Int
    var sealedState: String        // "sealed" or "opened"
    var pricePaid: Double?         // GBP
    var purchaseDate: Date?
    var notes: String?
    var addedAt: Date

    init(pokedataProductId: Int, productName: String, productType: String,
         quantity: Int = 1, sealedState: String = "sealed", addedAt: Date = .now) {
        self.id = UUID()
        self.pokedataProductId = pokedataProductId
        self.productName = productName
        self.productType = productType
        self.quantity = quantity
        self.sealedState = sealedState
        self.addedAt = addedAt
    }
}

@Model
class Transaction {
    var id: UUID
    var direction: String          // "purchase" or "sale" or "trade"
    var description: String
    var productTypeId: String?     // e.g. "single-card", "booster-box"
    var quantity: Int
    var unitPrice: Double?         // GBP
    var totalPrice: Double?        // GBP
    var notes: String?
    var date: Date
    var sourceReference: String?   // e.g. "sealed-product:123"
    var addedAt: Date

    init(direction: String, description: String, quantity: Int = 1, date: Date = .now, addedAt: Date = .now) {
        self.id = UUID()
        self.direction = direction
        self.description = description
        self.quantity = quantity
        self.date = date
        self.addedAt = addedAt
    }
}

@Model
class PortfolioSnapshot {
    var id: UUID
    var date: Date
    var totalValueGBP: Double
    var cardCount: Int
    var sealedValueGBP: Double

    init(date: Date, totalValueGBP: Double, cardCount: Int, sealedValueGBP: Double = 0) {
        self.id = UUID()
        self.date = date
        self.totalValueGBP = totalValueGBP
        self.cardCount = cardCount
        self.sealedValueGBP = sealedValueGBP
    }
}

Freemium Model
Free tier:

Card browsing and search (all cards, all sets)
Collection — up to 10 cards maximum
Wishlist (unlimited)
Current portfolio value (no history)

Premium (single in-app purchase — "TCG Premium"):

Unlimited collection
Card scanner (camera-based OCR identification)
Portfolio history charts
Collection sharing with other users (CKShare)
Sealed products inventory
Transaction history
Home screen widget

Gate logic:

On "Add to Collection": check collectionCards.count >= 10 → show paywall if not premium
On scanner: show paywall on tap if not premium
Premium features gated with storeKitService.isPremium


App Architecture
Entry Point (TCGApp.swift)
swift@main
struct TCGApp: App {
    let modelContainer: ModelContainer = {
        let schema = Schema([
            CollectionCard.self,
            WishlistItem.self,
            SealedCollectionItem.self,
            Transaction.self,
            PortfolioSnapshot.self
        ])
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
Tab Structure
swiftTabView {
    CollectionView()
        .tabItem { Label("Collection", systemImage: "square.grid.2x2") }
    WishlistView()
        .tabItem { Label("Wishlist", systemImage: "heart") }
    BrowseView()
        .tabItem { Label("Cards", systemImage: "rectangle.stack") }
    PortfolioView()
        .tabItem { Label("Portfolio", systemImage: "chart.line.uptrend.xyaxis") }
    AccountView()
        .tabItem { Label("Account", systemImage: "person.circle") }
}
iPad Adaptation
Use NavigationSplitView on iPad (detected via @Environment(\.horizontalSizeClass)), NavigationStack on iPhone.

Key Services
CardDataService (@Observable)
Loads card JSON using hybrid strategy:

Try bundled JSON in app bundle first (Bundle.main.url(forResource: setCode, withExtension: "json"))
Check Documents/cards/{setCode}.json for previously downloaded sets
If new set detected from R2 sets.json — fetch {R2_BASE}/cards/{setCode}.json and cache to Documents

swift@Observable
class CardDataService {
    var sets: [TCGSet] = []
    var cardsBySet: [String: [Card]] = [:]  // keyed by setCode

    func loadSets() async { ... }
    func loadCards(forSetCode setCode: String) async -> [Card] { ... }
    func card(masterCardId: String, setCode: String) -> Card? { ... }
    func search(query: String) async -> [Card] { ... }
}
PricingService (@Observable)
swift@Observable
class PricingService {
    // Keyed by setCode → [externalId: CardPricingEntry]
    private var pricingCache: [String: SetPricingMap] = [:]

    func pricing(for card: Card) async -> CardPricingEntry? { ... }
    func gbpPrice(for card: Card, printing: String) async -> Double? { ... }
    var usdToGbp: Double = 0.79  // Refreshed from Frankfurter on launch
}
Pricing lookup flow:

Fetch {R2_BASE}/pricing/{card.setCode}.json (cache to disk, 24h TTL)
Look up card.externalId in the map
Find the matching variant key for the printing (e.g. "Holo" → "holofoil")
Take ScrydexVariantPricing.raw × usdToGbp

StoreKitService (@Observable)
swift@Observable
class StoreKitService {
    var isPremium: Bool = false
    static let premiumProductId = "com.yourname.tcgapp.premium"

    func checkEntitlements() async { ... }
    func purchase() async throws { ... }
    func restore() async throws { ... }
}

Card Scanner
Use Apple's Vision framework — no third-party OCR needed.
swift// In scanner view:
let request = VNRecognizeTextRequest { request, error in
    guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
    let strings = observations.compactMap { $0.topCandidates(1).first?.string }
    // Parse: look for card number pattern (e.g. "025/102") and card name
    // Match against CardDataService search index
}
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true
Required in Info.plist: NSCameraUsageDescription

Collection Sharing (CKShare — Premium)
swift// CloudKitSharingService.swift
import CloudKit

class CloudKitSharingService {
    let container = CKContainer(identifier: "iCloud.com.yourname.tcgapp")

    func createShare(for zone: CKRecordZone) async throws -> (CKShare, CKContainer) { ... }
    func fetchActiveShares() async throws -> [CKShare] { ... }
    func deleteShare(_ share: CKShare) async throws { ... }
}
Handle acceptance in AppDelegate:
swiftfunc application(_ application: UIApplication,
                 userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
    let container = CKContainer(identifier: cloudKitShareMetadata.containerIdentifier)
    container.accept(cloudKitShareMetadata) { _, _ in }
}

Portfolio Value Calculation
swiftfunc calculatePortfolioValue(
    cards: [CollectionCard],
    cardDataService: CardDataService,
    pricingService: PricingService
) async -> Double {
    var total = 0.0
    for collectionCard in cards {
        guard let card = cardDataService.card(
            masterCardId: collectionCard.masterCardId,
            setCode: collectionCard.setCode
        ) else { continue }

        // Prefer unlisted price override
        if let manual = collectionCard.unlistedPrice {
            total += manual * Double(collectionCard.quantity)
            continue
        }

        if let price = await pricingService.gbpPrice(for: card, printing: collectionCard.printing) {
            total += price * Double(collectionCard.quantity)
        }
    }
    return total
}

Home Screen Widget (WidgetKit — Premium)
Separate Xcode target TCGWidget. Shares the same CloudKit ModelContainer.
swiftstruct PortfolioWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PortfolioWidget", provider: PortfolioProvider()) { entry in
            PortfolioWidgetView(entry: entry)
        }
        .configurationDisplayName("Portfolio Value")
        .description("Today's collection value")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

Required Xcode Capabilities
In Signing & Capabilities:

iCloud — enable CloudKit, add container iCloud.com.yourname.tcgapp
Push Notifications (required for CloudKit sync)
Sign in with Apple
In-App Purchase

In Info.plist:

NSCameraUsageDescription — "To scan and identify your Pokémon cards"
ITSAppUsesNonExemptEncryption → NO


Privacy Manifest (PrivacyInfo.xcprivacy)
Required by Apple for App Store submission:

Camera access: NSCameraUsageDescription
No third-party analytics/tracking SDKs used
iCloud sync declared (user's own data)
No data collected by developer


Build Order

Xcode project + capabilities + CloudKit setup
SwiftData models + ModelContainer
Sign in with Apple + Keychain storage
CardDataService — hybrid JSON loading (bundle + R2 fetch/cache)
PricingService — R2 fetch + disk cache + FX conversion
Tab bar + NavigationStack/SplitView structure
Card browse/search UI — LazyVGrid, AsyncImage, search bar
Collection CRUD — add/edit/delete with @Query, freemium gate at 10
Wishlist CRUD
Portfolio dashboard — total value, top cards
StoreKit 2 — premium purchase + restore
Card scanner — Vision framework OCR
Portfolio history charts — Swift Charts + PortfolioSnapshot
Sealed products — catalog browse + collection
Transaction history
Collection sharing — CKShare
WidgetKit target — portfolio value widget
Privacy manifest + App Store assets