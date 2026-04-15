import Foundation
import SQLite3

/// SQLite copy destructor; kept in a trivial type so it is not tied to actor / main-actor inference.
private enum CatalogSQLite {
    static let transient: sqlite3_destructor_type = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

/// Local SQLite catalog: sets, cards, per-set card pricing JSON, per-set price history/trends JSON, and daily blob payloads (Pokedata / sealed aggregates).
///
/// All `sqlite3_*` calls run on a **single serial queue**. Swift’s `actor` executor can hop OS threads
/// between calls; that still satisfies SQLite’s mutex mode but can trigger internal `SQLITE_MISUSE`
/// logging on some Apple builds. A dedicated queue matches the usual “one serial queue per connection” pattern.
final class CatalogStore: @unchecked Sendable {
    static let shared = CatalogStore()

    private let queue = DispatchQueue(label: "com.bindr.catalog.sqlite", qos: .utility)
    private var db: OpaquePointer?
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()

    private init() {}

    func open() throws {
        try queue.sync {
            try openLocked()
        }
    }

    private func openLocked() throws {
        guard db == nil else { return }
        let dir = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Bindr", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("catalog.sqlite").path
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let h = handle else {
            throw CatalogStoreError.openFailed
        }
        db = h
        do {
            try migrateLocked()
        } catch {
            sqlite3_close(h)
            db = nil
            throw error
        }
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA foreign_keys=ON;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA busy_timeout = 5000;", nil, nil, nil)
    }

    private func migrateLocked() throws {
        let ddl = """
        CREATE TABLE IF NOT EXISTS sync_meta (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS catalog_sets (
            set_code TEXT PRIMARY KEY NOT NULL,
            json TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS catalog_cards (
            set_code TEXT NOT NULL,
            master_card_id TEXT NOT NULL,
            json TEXT NOT NULL,
            PRIMARY KEY (set_code, master_card_id)
        );
        CREATE INDEX IF NOT EXISTS idx_catalog_cards_set ON catalog_cards(set_code);
        CREATE INDEX IF NOT EXISTS idx_catalog_cards_master_id ON catalog_cards(master_card_id);
        CREATE TABLE IF NOT EXISTS card_pricing (
            set_code TEXT PRIMARY KEY NOT NULL,
            json BLOB NOT NULL,
            fetched_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS daily_blobs (
            key TEXT PRIMARY KEY NOT NULL,
            json BLOB NOT NULL,
            fetched_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS card_price_history (
            brand TEXT NOT NULL,
            set_code TEXT NOT NULL,
            json BLOB NOT NULL,
            fetched_at REAL NOT NULL,
            PRIMARY KEY (brand, set_code)
        );
        CREATE TABLE IF NOT EXISTS card_price_trends (
            brand TEXT NOT NULL,
            set_code TEXT NOT NULL,
            json BLOB NOT NULL,
            fetched_at REAL NOT NULL,
            PRIMARY KEY (brand, set_code)
        );
        """
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, ddl, nil, nil, &err) == SQLITE_OK else {
            if let e = err { sqlite3_free(e) }
            throw CatalogStoreError.migrationFailed
        }
        try migrateBrandPartitionIfNeededLocked()
        try migrateOnePieceCardSchemaIfNeededLocked()
        try migrateLorcanaCardSchemaIfNeededLocked()
    }

    /// v3: card schema version bump — when new fields are added to the OP card JSON (e.g. opAttributes,
    /// opCost, opCounter, opLife), bump `onePieceCardSchemaVersion` so the cached SQLite data is
    /// invalidated and the sync coordinator re-downloads fresh card JSON.
    private func migrateOnePieceCardSchemaIfNeededLocked() throws {
        guard let db else { throw CatalogStoreError.notOpen }
        let currentVersion = 2  // bump this whenever new OP Card fields are added
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT value FROM sync_meta WHERE key = 'onepiece_card_schema_version' LIMIT 1;", -1, &stmt, nil) == SQLITE_OK else { return }
        let storedVersion: Int
        if sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) {
            storedVersion = Int(String(cString: c)) ?? 0
        } else {
            storedVersion = 0
        }
        sqlite3_finalize(stmt)
        stmt = nil
        guard storedVersion < currentVersion else { return }

        // Clear the OP fingerprint so CatalogSyncCoordinator re-downloads all OP cards.
        let clear = "DELETE FROM sync_meta WHERE key IN ('onepiece_catalog_row_fingerprint', 'onepiece_catalog_sets_sha256', 'onepiece_catalog_sets_etag');"
        var mErr: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, clear, nil, nil, &mErr)
        if let e = mErr { sqlite3_free(e) }

        let upsert = "INSERT INTO sync_meta(key, value) VALUES('onepiece_card_schema_version', '\(currentVersion)') ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
        var uErr: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, upsert, nil, nil, &uErr)
        if let e = uErr { sqlite3_free(e) }
    }

    /// When new fields are added to Lorcana card JSON (e.g. `lcCost`, `lcLore`), bump
    /// `lorcanaCardSchemaVersion` so cached SQLite rows are invalidated and sync re-imports cards.
    private func migrateLorcanaCardSchemaIfNeededLocked() throws {
        guard let db else { throw CatalogStoreError.notOpen }
        let currentVersion = 1
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT value FROM sync_meta WHERE key = 'lorcana_card_schema_version' LIMIT 1;", -1, &stmt, nil) == SQLITE_OK else { return }
        let storedVersion: Int
        if sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) {
            storedVersion = Int(String(cString: c)) ?? 0
        } else {
            storedVersion = 0
        }
        sqlite3_finalize(stmt)
        stmt = nil
        guard storedVersion < currentVersion else { return }

        let clear = "DELETE FROM sync_meta WHERE key IN ('lorcana_catalog_row_fingerprint', 'lorcana_catalog_sets_sha256', 'lorcana_catalog_sets_etag');"
        var mErr: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, clear, nil, nil, &mErr)
        if let e = mErr { sqlite3_free(e) }

        let upsert = "INSERT INTO sync_meta(key, value) VALUES('lorcana_card_schema_version', '\(currentVersion)') ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
        var uErr: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, upsert, nil, nil, &uErr)
        if let e = uErr { sqlite3_free(e) }
    }

    /// v2: `brand` column (`pokemon` | `onepiece`) so franchises can be purged independently.
    private func migrateBrandPartitionIfNeededLocked() throws {
        guard let db else { throw CatalogStoreError.notOpen }
        if tableHasColumnLocked(db, table: "catalog_sets", column: "brand") { return }

        let statements: [String] = [
            """
            CREATE TABLE catalog_sets_new (
                brand TEXT NOT NULL,
                set_code TEXT NOT NULL,
                json TEXT NOT NULL,
                PRIMARY KEY (brand, set_code)
            );
            """,
            """
            INSERT INTO catalog_sets_new SELECT 'pokemon', set_code, json FROM catalog_sets;
            """,
            "DROP TABLE catalog_sets;",
            "ALTER TABLE catalog_sets_new RENAME TO catalog_sets;",

            """
            CREATE TABLE catalog_cards_new (
                brand TEXT NOT NULL,
                set_code TEXT NOT NULL,
                master_card_id TEXT NOT NULL,
                json TEXT NOT NULL,
                PRIMARY KEY (brand, set_code, master_card_id)
            );
            """,
            """
            INSERT INTO catalog_cards_new SELECT 'pokemon', set_code, master_card_id, json FROM catalog_cards;
            """,
            "DROP TABLE catalog_cards;",
            "ALTER TABLE catalog_cards_new RENAME TO catalog_cards;",

            """
            CREATE TABLE card_pricing_new (
                brand TEXT NOT NULL,
                set_code TEXT NOT NULL,
                json BLOB NOT NULL,
                fetched_at REAL NOT NULL,
                PRIMARY KEY (brand, set_code)
            );
            """,
            """
            INSERT INTO card_pricing_new SELECT 'pokemon', set_code, json, fetched_at FROM card_pricing;
            """,
            "DROP TABLE card_pricing;",
            "ALTER TABLE card_pricing_new RENAME TO card_pricing;",

            "CREATE INDEX IF NOT EXISTS idx_catalog_cards_set ON catalog_cards(brand, set_code);",
            "CREATE INDEX IF NOT EXISTS idx_catalog_cards_master_id ON catalog_cards(master_card_id);",
        ]
        for sql in statements {
            var mErr: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(db, sql, nil, nil, &mErr) == SQLITE_OK else {
                if let e = mErr { sqlite3_free(e) }
                throw CatalogStoreError.migrationFailed
            }
        }
    }

    private func tableHasColumnLocked(_ db: OpaquePointer, table: String, column: String) -> Bool {
        let sql = "PRAGMA table_info(\(table));"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard sqlite3_column_text(stmt, 1) != nil else { continue }
            let name = String(cString: sqlite3_column_text(stmt, 1))
            if name == column { return true }
        }
        return false
    }

    // MARK: - Meta

    func meta(_ key: String) -> String? {
        queue.sync {
            guard let db else { return nil }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "SELECT value FROM sync_meta WHERE key = ? LIMIT 1;", -1, &stmt, nil) == SQLITE_OK else { return nil }
            key.withCString { cstr in
                _ = sqlite3_bind_text(stmt, 1, cstr, -1, CatalogSQLite.transient)
            }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            guard let c = sqlite3_column_text(stmt, 0) else { return nil }
            return String(cString: c)
        }
    }

    func setMeta(_ key: String, _ value: String) throws {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = "INSERT INTO sync_meta(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
            key.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
            value.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw CatalogStoreError.execFailed }
        }
    }

    func setMetaData(_ key: String, data: Data) throws {
        guard let value = String(data: data, encoding: .utf8) else { throw CatalogStoreError.encodeFailed }
        try setMeta(key, value)
    }

    func metaData(_ key: String) -> Data? {
        guard let value = meta(key) else { return nil }
        return value.data(using: .utf8)
    }

    // MARK: - Catalog

    func hasAnyCards(for brand: TCGBrand) throws -> Bool {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = "SELECT COUNT(*) FROM catalog_cards WHERE brand = ?;"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw CatalogStoreError.prepareFailed
            }
            brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return false }
            return sqlite3_column_int64(stmt, 0) > 0
        }
    }

    /// Returns set codes that are registered in `catalog_sets` but have no rows in `catalog_cards` for the given brand.
    /// Used to detect sets whose card download failed during a previous sync (e.g. new set added but network timed out).
    func fetchSetCodesWithNoCards(for brand: TCGBrand) throws -> [String] {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = """
            SELECT s.set_code FROM catalog_sets s
            WHERE s.brand = ?
              AND NOT EXISTS (
                SELECT 1 FROM catalog_cards c
                WHERE c.brand = s.brand AND c.set_code = s.set_code
              );
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw CatalogStoreError.prepareFailed
            }
            brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
            var out: [String] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let c = sqlite3_column_text(stmt, 0) else { continue }
                out.append(String(cString: c))
            }
            return out
        }
    }

    /// Deletes SQLite rows for one franchise only. Does **not** clear ``sync_meta`` (hash / ETag / fingerprint).
    /// Use before re-importing so a failed import can still resume skip logic on the next launch.
    func purgeCatalogTables(for brand: TCGBrand) throws {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            let b = brand.rawValue
            for sql in [
                "DELETE FROM catalog_cards WHERE brand = ?;",
                "DELETE FROM catalog_sets WHERE brand = ?;",
                "DELETE FROM card_pricing WHERE brand = ?;",
                "DELETE FROM card_price_history WHERE brand = ?;",
                "DELETE FROM card_price_trends WHERE brand = ?;",
            ] {
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
                b.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                _ = sqlite3_step(stmt)
            }
        }
    }

    /// Removes all catalog + pricing rows for one franchise (toggle off / account).
    /// Also clears brand-specific ``sync_meta`` keys so the next sync must re-fetch from the network (no skip-the-download fast path).
    func purgeCatalogData(for brand: TCGBrand) throws {
        try purgeCatalogTables(for: brand)
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            let keys: [String]
            switch brand {
            case .pokemon:
                keys = ["catalog_sets_sha256", "catalog_etag", "catalog_import_at"]
            case .onePiece:
                keys = [
                    "onepiece_catalog_sets_sha256",
                    "onepiece_catalog_sets_etag",
                    "onepiece_catalog_row_fingerprint",
                    "onepiece_character_names_json",
                    "onepiece_character_names_etag",
                    "onepiece_character_subtypes_json",
                    "onepiece_character_subtypes_etag",
                ]
            case .lorcana:
                keys = [
                    "lorcana_catalog_sets_sha256",
                    "lorcana_catalog_sets_etag",
                    "lorcana_catalog_row_fingerprint",
                ]
            }
            for key in keys {
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                let sql = "DELETE FROM sync_meta WHERE key = ?;"
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
                key.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                _ = sqlite3_step(stmt)
            }
        }
    }

    func upsertSet(_ set: TCGSet, brand: TCGBrand) throws {
        try queue.sync {
            let data = try jsonEncoder.encode(set)
            guard let json = String(data: data, encoding: .utf8) else { throw CatalogStoreError.encodeFailed }
            try upsertSetRawLocked(brand: brand, setCode: set.setCode, json: json)
        }
    }

    private func upsertSetRawLocked(brand: TCGBrand, setCode: String, json: String) throws {
        guard let db else { throw CatalogStoreError.notOpen }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = """
        INSERT INTO catalog_sets(brand, set_code, json) VALUES(?, ?, ?)
        ON CONFLICT(brand, set_code) DO UPDATE SET json = excluded.json;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
        brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
        setCode.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
        json.withCString { _ = sqlite3_bind_text(stmt, 3, $0, -1, CatalogSQLite.transient) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw CatalogStoreError.execFailed }
    }

    func deleteCards(forSet setCode: String, brand: TCGBrand) throws {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = "DELETE FROM catalog_cards WHERE brand = ? AND set_code = ?;"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw CatalogStoreError.prepareFailed
            }
            brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
            setCode.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
            _ = sqlite3_step(stmt)
        }
    }

    func insertCards(_ cards: [Card], setCode: String, brand: TCGBrand) throws {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            // Begin transaction for batch insert
            guard sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else { throw CatalogStoreError.execFailed }
            defer {
                // Ensure transaction is ended even if we throw
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = """
            INSERT OR REPLACE INTO catalog_cards(brand, set_code, master_card_id, json) VALUES(?, ?, ?, ?);
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
            for card in cards {
                let blob = try jsonEncoder.encode(card)
                guard let j = String(data: blob, encoding: .utf8) else { continue }
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                setCode.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
                card.masterCardId.withCString { _ = sqlite3_bind_text(stmt, 3, $0, -1, CatalogSQLite.transient) }
                j.withCString { _ = sqlite3_bind_text(stmt, 4, $0, -1, CatalogSQLite.transient) }
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                    throw CatalogStoreError.execFailed
                }
            }
            // Commit transaction
            guard sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
                throw CatalogStoreError.execFailed
            }
        }
    }

    func upsertPricing(setCode: String, json: Data, brand: TCGBrand) throws {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = """
            INSERT INTO card_pricing(brand, set_code, json, fetched_at) VALUES(?, ?, ?, ?)
            ON CONFLICT(brand, set_code) DO UPDATE SET json = excluded.json, fetched_at = excluded.fetched_at;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
            brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
            setCode.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
            if json.isEmpty {
                _ = sqlite3_bind_blob(stmt, 3, nil, 0, CatalogSQLite.transient)
            } else {
                json.withUnsafeBytes { buf in
                    _ = sqlite3_bind_blob(stmt, 3, buf.baseAddress, Int32(json.count), CatalogSQLite.transient)
                }
            }
            _ = sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw CatalogStoreError.execFailed }
        }
    }

    func fetchAllSets(for brand: TCGBrand) throws -> [TCGSet] {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = "SELECT json FROM catalog_sets WHERE brand = ? ORDER BY set_code;"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw CatalogStoreError.prepareFailed
            }
            brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
            var out: [TCGSet] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let c = sqlite3_column_text(stmt, 0) else { continue }
                let s = String(cString: c)
                guard let d = s.data(using: .utf8), let set = try? jsonDecoder.decode(TCGSet.self, from: d) else { continue }
                out.append(set)
            }
            return out
        }
    }

    func fetchCards(setCode: String, brand: TCGBrand) throws -> [Card] {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = "SELECT json FROM catalog_cards WHERE brand = ? AND set_code = ? ORDER BY master_card_id;"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
            brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
            setCode.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
            var out: [Card] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let c = sqlite3_column_text(stmt, 0) else { continue }
                let s = String(cString: c)
                guard let d = s.data(using: .utf8), let card = try? jsonDecoder.decode(Card.self, from: d) else { continue }
                out.append(card)
            }
            return out
        }
    }

    func fetchAllCards(for brand: TCGBrand) throws -> [Card] {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = "SELECT json FROM catalog_cards WHERE brand = ? ORDER BY set_code, master_card_id;"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
            brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
            var out: [Card] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let c = sqlite3_column_text(stmt, 0) else { continue }
                let s = String(cString: c)
                guard let d = s.data(using: .utf8), let card = try? jsonDecoder.decode(Card.self, from: d) else { continue }
                out.append(card)
            }
            return out
        }
    }

    func fetchAllBrowseFilterCards(for brand: TCGBrand) throws -> [BrowseFilterCard] {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = "SELECT json FROM catalog_cards WHERE brand = ? ORDER BY set_code, master_card_id;"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
            brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
            var out: [BrowseFilterCard] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let c = sqlite3_column_text(stmt, 0) else { continue }
                let s = String(cString: c)
                guard let d = s.data(using: .utf8),
                      let card = try? jsonDecoder.decode(BrowseFilterCard.self, from: d) else { continue }
                out.append(card)
            }
            return out
        }
    }

    /// Single card by catalog id for a known franchise (browse / wishlist resolve).
    func fetchCard(masterCardId: String, brand: TCGBrand) throws -> Card? {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = "SELECT json FROM catalog_cards WHERE brand = ? AND master_card_id = ? LIMIT 1;"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
            brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
            masterCardId.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            guard let c = sqlite3_column_text(stmt, 0) else { return nil }
            let s = String(cString: c)
            guard let d = s.data(using: .utf8) else { return nil }
            return try jsonDecoder.decode(Card.self, from: d)
        }
    }

    func fetchAllCardRefs(for brand: TCGBrand) throws -> [CardRef] {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = "SELECT set_code, master_card_id FROM catalog_cards WHERE brand = ?;"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
            brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
            var out: [CardRef] = []
            out.reserveCapacity(10_000)
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let sc = sqlite3_column_text(stmt, 0), let mid = sqlite3_column_text(stmt, 1) else { continue }
                out.append(CardRef(masterCardId: String(cString: mid), setCode: String(cString: sc)))
            }
            return out
        }
    }

    func fetchPricingData(setCode: String, brand: TCGBrand) -> Data? {
        queue.sync {
            guard let db else { return nil }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = "SELECT json FROM card_pricing WHERE brand = ? AND set_code = ? LIMIT 1;"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                return nil
            }
            brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
            setCode.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let n = sqlite3_column_bytes(stmt, 0)
            guard let p = sqlite3_column_blob(stmt, 0) else { return nil }
            return Data(bytes: p, count: Int(n))
        }
    }

    /// Per-set price history JSON (`pricing/price-history/…` or ONE PIECE `pricing/history/…`), refreshed with daily market pricing after 03:00 local.
    func upsertPriceHistory(setCode: String, json: Data, brand: TCGBrand) throws {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = """
            INSERT INTO card_price_history(brand, set_code, json, fetched_at) VALUES(?, ?, ?, ?)
            ON CONFLICT(brand, set_code) DO UPDATE SET json = excluded.json, fetched_at = excluded.fetched_at;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
            brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
            setCode.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
            if json.isEmpty {
                _ = sqlite3_bind_blob(stmt, 3, nil, 0, CatalogSQLite.transient)
            } else {
                json.withUnsafeBytes { buf in
                    _ = sqlite3_bind_blob(stmt, 3, buf.baseAddress, Int32(json.count), CatalogSQLite.transient)
                }
            }
            _ = sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw CatalogStoreError.execFailed }
        }
    }

    func fetchPriceHistoryData(setCode: String, brand: TCGBrand) -> Data? {
        queue.sync {
            guard let db else { return nil }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = "SELECT json FROM card_price_history WHERE brand = ? AND set_code = ? LIMIT 1;"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
            setCode.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let n = sqlite3_column_bytes(stmt, 0)
            guard let p = sqlite3_column_blob(stmt, 0) else { return nil }
            return Data(bytes: p, count: Int(n))
        }
    }

    /// Per-set price trends JSON (`pricing/price-trends/…` or ONE PIECE `pricing/trends/…`), refreshed with daily market pricing after 03:00 local.
    func upsertPriceTrends(setCode: String, json: Data, brand: TCGBrand) throws {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = """
            INSERT INTO card_price_trends(brand, set_code, json, fetched_at) VALUES(?, ?, ?, ?)
            ON CONFLICT(brand, set_code) DO UPDATE SET json = excluded.json, fetched_at = excluded.fetched_at;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
            brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
            setCode.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
            if json.isEmpty {
                _ = sqlite3_bind_blob(stmt, 3, nil, 0, CatalogSQLite.transient)
            } else {
                json.withUnsafeBytes { buf in
                    _ = sqlite3_bind_blob(stmt, 3, buf.baseAddress, Int32(json.count), CatalogSQLite.transient)
                }
            }
            _ = sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw CatalogStoreError.execFailed }
        }
    }

    func fetchPriceTrendsData(setCode: String, brand: TCGBrand) -> Data? {
        queue.sync {
            guard let db else { return nil }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = "SELECT json FROM card_price_trends WHERE brand = ? AND set_code = ? LIMIT 1;"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
            setCode.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let n = sqlite3_column_bytes(stmt, 0)
            guard let p = sqlite3_column_blob(stmt, 0) else { return nil }
            return Data(bytes: p, count: Int(n))
        }
    }

    // MARK: - Daily blobs

    func upsertDailyBlob(key: String, data: Data) throws {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = """
            INSERT INTO daily_blobs(key, json, fetched_at) VALUES(?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET json = excluded.json, fetched_at = excluded.fetched_at;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
            key.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
            if data.isEmpty {
                _ = sqlite3_bind_blob(stmt, 2, nil, 0, CatalogSQLite.transient)
            } else {
                data.withUnsafeBytes { buf in
                    _ = sqlite3_bind_blob(stmt, 2, buf.baseAddress, Int32(data.count), CatalogSQLite.transient)
                }
            }
            _ = sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw CatalogStoreError.execFailed }
        }
    }

    func dailyBlob(key: String) -> Data? {
        queue.sync {
            guard let db else { return nil }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "SELECT json FROM daily_blobs WHERE key = ? LIMIT 1;", -1, &stmt, nil) == SQLITE_OK else {
                return nil
            }
            key.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let n = sqlite3_column_bytes(stmt, 0)
            guard let p = sqlite3_column_blob(stmt, 0) else { return nil }
            return Data(bytes: p, count: Int(n))
        }
    }

    func dailyBlobFetchedAt(key: String) -> Date? {
        queue.sync {
            guard let db else { return nil }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "SELECT fetched_at FROM daily_blobs WHERE key = ? LIMIT 1;", -1, &stmt, nil) == SQLITE_OK else {
                return nil
            }
            key.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0))
        }
    }

    /// Bumps `fetched_at` without replacing the blob (used after HTTP `304 Not Modified`).
    func touchDailyBlobFetchedAt(key: String) throws {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = "UPDATE daily_blobs SET fetched_at = ? WHERE key = ?;"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
            _ = sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
            key.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw CatalogStoreError.execFailed }
        }
    }
}

enum CatalogStoreError: Error {
    case openFailed
    case migrationFailed
    case notOpen
    case prepareFailed
    case execFailed
    case encodeFailed
}
