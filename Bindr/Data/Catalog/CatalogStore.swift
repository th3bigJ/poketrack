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

    /// Serial queue for all writes (INSERT / UPDATE / DELETE / DDL).
    private let queue = DispatchQueue(label: "com.bindr.catalog.sqlite.write", qos: .utility)
    /// Concurrent queue for read-only queries. WAL mode allows readers to run
    /// concurrently with the writer without blocking or being blocked.
    private let readQueue = DispatchQueue(label: "com.bindr.catalog.sqlite.read", qos: .userInitiated, attributes: .concurrent)
    private var db: OpaquePointer?
    /// Separate read-only connection used exclusively on `readQueue`.
    private var readDb: OpaquePointer?
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()

    /// In-memory mirror of the `sync_meta` table. Loaded at open time; writes update both SQLite and this dict.
    /// Protected by `metaCacheLock` so reads never dispatch to `queue`.
    private var metaCache: [String: String] = [:]
    private let metaCacheLock = NSLock()

    private init() {}

    func open() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.openLocked()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Synchronous open — for launch-path use only (e.g. called from `init` before async context exists).
    func openSync() {
        try? queue.sync { try self.openLocked() }
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
        sqlite3_exec(db, "PRAGMA cache_size = -8000;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA mmap_size = 67108864;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA foreign_keys=ON;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA busy_timeout = 5000;", nil, nil, nil)
        // Load after migrations (which may have written/deleted sync_meta rows directly).
        loadMetaCacheLocked()

        // Open a second read-only connection on the same WAL database.
        var rHandle: OpaquePointer?
        let rFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_SHAREDCACHE
        if sqlite3_open_v2(path, &rHandle, rFlags, nil) == SQLITE_OK, let rh = rHandle {
            sqlite3_exec(rh, "PRAGMA cache_size = -4000;", nil, nil, nil)
            sqlite3_exec(rh, "PRAGMA mmap_size = 67108864;", nil, nil, nil)
            sqlite3_exec(rh, "PRAGMA busy_timeout = 5000;", nil, nil, nil)
            readDb = rh
        }
    }

    /// Dispatch a read-only closure on the concurrent read queue using the read-only connection.
    /// Falls back to the write connection if the read connection has not been opened yet.
    private func readAsync<T>(
        _ continuation: CheckedContinuation<T, any Error>,
        body: @escaping (OpaquePointer) throws -> T
    ) {
        readQueue.async {
            let handle = self.readDb ?? self.db
            guard let handle else { continuation.resume(throwing: CatalogStoreError.notOpen); return }
            do { continuation.resume(returning: try body(handle)) }
            catch { continuation.resume(throwing: error) }
        }
    }

    private func readAsyncOptional<T>(
        _ continuation: CheckedContinuation<T?, Never>,
        body: @escaping (OpaquePointer) -> T?
    ) {
        readQueue.async {
            let handle = self.readDb ?? self.db
            guard let handle else { continuation.resume(returning: nil); return }
            continuation.resume(returning: body(handle))
        }
    }

    private func loadMetaCacheLocked() {
        guard let db else { return }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT key, value FROM sync_meta;", -1, &stmt, nil) == SQLITE_OK else { return }
        var cache: [String: String] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let k = sqlite3_column_text(stmt, 0), let v = sqlite3_column_text(stmt, 1) else { continue }
            cache[String(cString: k)] = String(cString: v)
        }
        metaCacheLock.withLock { metaCache = cache }
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
        CREATE TABLE IF NOT EXISTS catalog_aux_blobs (
            key TEXT PRIMARY KEY NOT NULL,
            json BLOB NOT NULL,
            fetched_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS processed_pricing_buckets (
            bucket_key TEXT PRIMARY KEY NOT NULL,
            processed_at REAL NOT NULL
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS catalog_cards_fts USING fts5(
            master_card_id UNINDEXED,
            set_code UNINDEXED,
            brand UNINDEXED,
            body,
            tokenize='ascii'
        );
        CREATE TABLE IF NOT EXISTS card_prices (
            brand TEXT NOT NULL,
            set_code TEXT NOT NULL,
            card_key TEXT NOT NULL,
            json BLOB NOT NULL,
            fetched_at REAL NOT NULL,
            PRIMARY KEY (brand, set_code, card_key)
        );
        CREATE INDEX IF NOT EXISTS idx_card_prices_key ON card_prices(brand, card_key);
        CREATE TABLE IF NOT EXISTS price_history_points (
            brand TEXT NOT NULL,
            set_code TEXT NOT NULL,
            card_key TEXT NOT NULL,
            variant TEXT NOT NULL,
            grade TEXT NOT NULL,
            period_type TEXT NOT NULL,
            period_key TEXT NOT NULL,
            price REAL NOT NULL,
            PRIMARY KEY (brand, set_code, card_key, variant, grade, period_type, period_key)
        );
        CREATE INDEX IF NOT EXISTS idx_php_card ON price_history_points(brand, card_key);
        """
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, ddl, nil, nil, &err) == SQLITE_OK else {
            if let e = err { sqlite3_free(e) }
            throw CatalogStoreError.migrationFailed
        }
        try migrateBrandPartitionIfNeededLocked()
        try migrateCardSchemaIfNeededLocked()
    }

    /// Bump when catalog payload structure changes so franchises re-download into SQLite.
    /// This catches new fields (e.g. set abbreviations, abilities / rules / flavor text) even when cache fingerprints linger.
    private func migrateCardSchemaIfNeededLocked() throws {
        guard let db else { throw CatalogStoreError.notOpen }
        let currentVersion = 2
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT value FROM sync_meta WHERE key = 'catalog_card_schema_version' LIMIT 1;", -1, &stmt, nil) == SQLITE_OK else { return }
        let storedVersion: Int
        if sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) {
            storedVersion = Int(String(cString: c)) ?? 0
        } else {
            storedVersion = 0
        }
        sqlite3_finalize(stmt)
        stmt = nil
        guard storedVersion < currentVersion else { return }

        // Clear sync fingerprints so CatalogSyncCoordinator re-downloads card JSON for both brands.
        let clear = "DELETE FROM sync_meta WHERE key IN ('catalog_sets_sha256', 'catalog_etag', 'onepiece_catalog_row_fingerprint', 'onepiece_catalog_sets_sha256', 'onepiece_catalog_sets_etag');"
        var mErr: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, clear, nil, nil, &mErr)
        if let e = mErr { sqlite3_free(e) }

        let upsert = "INSERT INTO sync_meta(key, value) VALUES('catalog_card_schema_version', '\(currentVersion)') ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
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

    /// Synchronous read from the in-memory cache — safe to call from any context.
    func metaSync(_ key: String) -> String? {
        metaCacheLock.withLock { metaCache[key] }
    }

    /// Asynchronous read — reads from the in-memory cache directly (no queue hop).
    func meta(_ key: String) async -> String? {
        metaCacheLock.withLock { metaCache[key] }
    }

    func setMeta(_ key: String, _ value: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let db = self.db else { throw CatalogStoreError.notOpen }
                    var stmt: OpaquePointer?
                    defer { sqlite3_finalize(stmt) }
                    let sql = "INSERT INTO sync_meta(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
                    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
                    key.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                    value.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
                    guard sqlite3_step(stmt) == SQLITE_DONE else { throw CatalogStoreError.execFailed }
                    self.metaCacheLock.withLock { self.metaCache[key] = value }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Synchronous read — for launch-path use only.
    func dailyBlobFetchedAtSync(key: String) -> Date? {
        queue.sync {
            guard let db else { return nil }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "SELECT fetched_at FROM daily_blobs WHERE key = ? LIMIT 1;", -1, &stmt, nil) == SQLITE_OK else { return nil }
            key.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0))
        }
    }

    func setMetaData(_ key: String, data: Data) async throws {
        guard let value = String(data: data, encoding: .utf8) else { throw CatalogStoreError.encodeFailed }
        try await setMeta(key, value)
    }
    
    func metaData(_ key: String) async -> Data? {
        guard let value = await meta(key) else { return nil }
        return value.data(using: .utf8)
    }

    // MARK: - Catalog

    func hasAnyCards(for brand: TCGBrand) async throws -> Bool {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            queue.async {
                do {
                    guard let db = self.db else { throw CatalogStoreError.notOpen }
                    var stmt: OpaquePointer?
                    defer { sqlite3_finalize(stmt) }
                    let sql = "SELECT COUNT(*) FROM catalog_cards WHERE brand = ?;"
                    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                        throw CatalogStoreError.prepareFailed
                    }
                    brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                    guard sqlite3_step(stmt) == SQLITE_ROW else {
                        continuation.resume(returning: false)
                        return
                    }
                    continuation.resume(returning: sqlite3_column_int64(stmt, 0) > 0)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Returns set codes that are registered in `catalog_sets` but have no rows in `catalog_cards` for the given brand.
    /// Used to detect sets whose card download failed during a previous sync (e.g. new set added but network timed out).
    func fetchSetCodesWithNoCards(for brand: TCGBrand) async throws -> [String] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], Error>) in
            queue.async {
                do {
                    guard let db = self.db else { throw CatalogStoreError.notOpen }
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
                    continuation.resume(returning: out)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Deletes SQLite rows for one franchise only. Does **not** clear ``sync_meta`` (hash / ETag / fingerprint).
    /// Use before re-importing so a failed import can still resume skip logic on the next launch.
    func purgeCatalogTables(for brand: TCGBrand) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let db = self.db else { throw CatalogStoreError.notOpen }
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
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Removes all catalog + pricing rows for one franchise (toggle off / account).
    /// Also clears brand-specific ``sync_meta`` keys so the next sync must re-fetch from the network (no skip-the-download fast path).
    func purgeCatalogData(for brand: TCGBrand) async throws {
        try await purgeCatalogTables(for: brand)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let db = self.db else { throw CatalogStoreError.notOpen }
                    let keys: [String]
                    switch brand {
                    case .pokemon:
                        keys = [
                            "catalog_sets_sha256",
                            "catalog_etag",
                            "catalog_import_at",
                            "pokemon_national_dex_json",
                            "pokemon_national_dex_etag",
                        ]
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
                    }
                    for key in keys {
                        var stmt: OpaquePointer?
                        defer { sqlite3_finalize(stmt) }
                        let sql = "DELETE FROM sync_meta WHERE key = ?;"
                        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
                        key.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                        _ = sqlite3_step(stmt)
                    }
                    self.metaCacheLock.withLock {
                        for key in keys { self.metaCache.removeValue(forKey: key) }
                    }
                    if brand == .pokemon {
                        var auxStmt: OpaquePointer?
                        defer { sqlite3_finalize(auxStmt) }
                        let auxSQL = "DELETE FROM catalog_aux_blobs WHERE key = ?;"
                        guard sqlite3_prepare_v2(db, auxSQL, -1, &auxStmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
                        "pokemon_national_dex_json".withCString { _ = sqlite3_bind_text(auxStmt, 1, $0, -1, CatalogSQLite.transient) }
                        _ = sqlite3_step(auxStmt)
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func upsertSet(_ set: TCGSet, brand: TCGBrand) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let data = try self.jsonEncoder.encode(set)
                    guard let json = String(data: data, encoding: .utf8) else { throw CatalogStoreError.encodeFailed }
                    try self.upsertSetRawLocked(brand: brand, setCode: set.setCode, json: json)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func upsertSets(_ sets: [TCGSet], brand: TCGBrand) async throws {
        guard !sets.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let db = self.db else { throw CatalogStoreError.notOpen }
                    guard sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else { throw CatalogStoreError.execFailed }
                    do {
                        for set in sets {
                            let data = try self.jsonEncoder.encode(set)
                            guard let json = String(data: data, encoding: .utf8) else { throw CatalogStoreError.encodeFailed }
                            try self.upsertSetRawLocked(brand: brand, setCode: set.setCode, json: json)
                        }
                    } catch {
                        sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                        throw error
                    }
                    guard sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
                        sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                        throw CatalogStoreError.execFailed
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
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

    func deleteCards(forSet setCode: String, brand: TCGBrand) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let db = self.db else { throw CatalogStoreError.notOpen }
                    for sql in [
                        "DELETE FROM catalog_cards WHERE brand = ? AND set_code = ?;",
                        "DELETE FROM catalog_cards_fts WHERE brand = ? AND set_code = ?;",
                    ] {
                        var stmt: OpaquePointer?
                        defer { sqlite3_finalize(stmt) }
                        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                            throw CatalogStoreError.prepareFailed
                        }
                        brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                        setCode.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
                        _ = sqlite3_step(stmt)
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func insertCards(_ cards: [Card], setCode: String, brand: TCGBrand) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let db = self.db else { throw CatalogStoreError.notOpen }
                    // Begin transaction for batch insert
                    guard sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else { throw CatalogStoreError.execFailed }
                    
                    var stmt: OpaquePointer?
                    defer {
                        sqlite3_finalize(stmt)
                        // Commit or Rollback is handled manually below
                    }
                    
                    let sql = """
                    INSERT OR REPLACE INTO catalog_cards(brand, set_code, master_card_id, json) VALUES(?, ?, ?, ?);
                    """
                    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                        sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                        throw CatalogStoreError.prepareFailed
                    }

                    var ftsStmt: OpaquePointer?
                    defer { sqlite3_finalize(ftsStmt) }
                    let ftsSql = """
                    INSERT INTO catalog_cards_fts(master_card_id, set_code, brand, body) VALUES(?, ?, ?, ?);
                    """
                    _ = sqlite3_prepare_v2(db, ftsSql, -1, &ftsStmt, nil)

                    for card in cards {
                        let blob = try self.jsonEncoder.encode(card)
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
                        if let ftsStmt {
                            sqlite3_reset(ftsStmt)
                            sqlite3_clear_bindings(ftsStmt)
                            card.masterCardId.withCString { _ = sqlite3_bind_text(ftsStmt, 1, $0, -1, CatalogSQLite.transient) }
                            setCode.withCString { _ = sqlite3_bind_text(ftsStmt, 2, $0, -1, CatalogSQLite.transient) }
                            brand.rawValue.withCString { _ = sqlite3_bind_text(ftsStmt, 3, $0, -1, CatalogSQLite.transient) }
                            card.searchIndexBlob.withCString { _ = sqlite3_bind_text(ftsStmt, 4, $0, -1, CatalogSQLite.transient) }
                            _ = sqlite3_step(ftsStmt)
                        }
                    }
                    // Commit transaction
                    guard sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
                        sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                        throw CatalogStoreError.execFailed
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func upsertPricing(setCode: String, json: Data, brand: TCGBrand) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let db = self.db else { throw CatalogStoreError.notOpen }
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
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func fetchAllSets(for brand: TCGBrand) async throws -> [TCGSet] {
        try await withCheckedThrowingContinuation { continuation in
            self.readAsync(continuation) { db in
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                let sql = "SELECT json FROM catalog_sets WHERE brand = ? ORDER BY set_code;"
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
                brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                var out: [TCGSet] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let c = sqlite3_column_text(stmt, 0) else { continue }
                    let s = String(cString: c)
                    guard let d = s.data(using: .utf8), let set = try? self.jsonDecoder.decode(TCGSet.self, from: d) else { continue }
                    out.append(set)
                }
                return out
            }
        }
    }

    func fetchCards(setCode: String, brand: TCGBrand) async throws -> [Card] {
        try await withCheckedThrowingContinuation { continuation in
            self.readAsync(continuation) { db in
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
                    guard let d = s.data(using: .utf8), let card = try? self.jsonDecoder.decode(Card.self, from: d) else { continue }
                    out.append(card)
                }
                return out
            }
        }
    }

    func fetchAllCards(for brand: TCGBrand) async throws -> [Card] {
        try await withCheckedThrowingContinuation { continuation in
            self.readAsync(continuation) { db in
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                let sql = "SELECT json FROM catalog_cards WHERE brand = ? ORDER BY set_code, master_card_id;"
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
                brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                var out: [Card] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let c = sqlite3_column_text(stmt, 0) else { continue }
                    let s = String(cString: c)
                    guard let d = s.data(using: .utf8), let card = try? self.jsonDecoder.decode(Card.self, from: d) else { continue }
                    out.append(card)
                }
                return out
            }
        }
    }

    func fetchAllBrowseFilterCards(for brand: TCGBrand) async throws -> [BrowseFilterCard] {
        try await withCheckedThrowingContinuation { continuation in
            self.readAsync(continuation) { db in
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
                          let card = try? self.jsonDecoder.decode(BrowseFilterCard.self, from: d) else { continue }
                    out.append(card)
                }
                return out
            }
        }
    }

    /// Single card by catalog id for a known franchise (browse / wishlist resolve).
    func fetchCard(masterCardId: String, brand: TCGBrand) async throws -> Card? {
        try await withCheckedThrowingContinuation { continuation in
            self.readAsync(continuation) { db in
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                let sql = "SELECT json FROM catalog_cards WHERE brand = ? AND master_card_id = ? LIMIT 1;"
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
                brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                masterCardId.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
                guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else { return nil }
                let s = String(cString: c)
                guard let d = s.data(using: .utf8) else { return nil }
                return try self.jsonDecoder.decode(Card.self, from: d)
            }
        }
    }

    /// Bulk card lookup by catalog id for a known franchise.
    /// Uses chunked `IN` queries to stay within SQLite parameter limits.
    func fetchCards(masterCardIDs: [String], brand: TCGBrand) async throws -> [Card] {
        let ids = Array(Set(masterCardIDs))
        guard !ids.isEmpty else { return [] }

        return try await withCheckedThrowingContinuation { continuation in
            self.readAsync(continuation) { db in
                let chunkSize = 240
                var out: [Card] = []
                out.reserveCapacity(ids.count)
                var index = 0
                while index < ids.count {
                    let upper = min(index + chunkSize, ids.count)
                    let chunk = Array(ids[index..<upper])
                    let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                    let sql = "SELECT json FROM catalog_cards WHERE brand = ? AND master_card_id IN (\(placeholders));"
                    var stmt: OpaquePointer?
                    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
                    brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                    for (bindIndex, id) in chunk.enumerated() {
                        id.withCString { _ = sqlite3_bind_text(stmt, Int32(bindIndex + 2), $0, -1, CatalogSQLite.transient) }
                    }
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        guard let c = sqlite3_column_text(stmt, 0) else { continue }
                        let s = String(cString: c)
                        guard let d = s.data(using: .utf8),
                              let card = try? self.jsonDecoder.decode(Card.self, from: d) else { continue }
                        out.append(card)
                    }
                    sqlite3_finalize(stmt)
                    index = upper
                }
                return out
            }
        }
    }

    func fetchAllCardRefs(for brand: TCGBrand) async throws -> [CardRef] {
        try await withCheckedThrowingContinuation { continuation in
            self.readAsync(continuation) { db in
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
    }

    // MARK: - Per-card pricing (normalized rows)

    func upsertCardPrices(setCode: String, brand: TCGBrand, entries: [(cardKey: String, json: Data)]) async throws {
        guard !entries.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let db = self.db else { throw CatalogStoreError.notOpen }
                    guard sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else { throw CatalogStoreError.execFailed }
                    var stmt: OpaquePointer?
                    let sql = """
                    INSERT INTO card_prices(brand, set_code, card_key, json, fetched_at) VALUES(?, ?, ?, ?, ?)
                    ON CONFLICT(brand, set_code, card_key) DO UPDATE SET json = excluded.json, fetched_at = excluded.fetched_at;
                    """
                    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                        sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                        throw CatalogStoreError.prepareFailed
                    }
                    defer { sqlite3_finalize(stmt) }
                    let now = Date().timeIntervalSince1970
                    for entry in entries {
                        sqlite3_reset(stmt)
                        sqlite3_clear_bindings(stmt)
                        brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                        setCode.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
                        entry.cardKey.withCString { _ = sqlite3_bind_text(stmt, 3, $0, -1, CatalogSQLite.transient) }
                        entry.json.withUnsafeBytes { buf in
                            _ = sqlite3_bind_blob(stmt, 4, buf.baseAddress, Int32(entry.json.count), CatalogSQLite.transient)
                        }
                        _ = sqlite3_bind_double(stmt, 5, now)
                        guard sqlite3_step(stmt) == SQLITE_DONE else {
                            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                            throw CatalogStoreError.execFailed
                        }
                    }
                    guard sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
                        sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                        throw CatalogStoreError.execFailed
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    struct CardPriceRow: Sendable {
        let cardKey: String
        let json: Data
    }

    func fetchCardPrice(cardKey: String, brand: TCGBrand) async -> Data? {
        await withCheckedContinuation { continuation in
            readQueue.async {
                guard let handle = self.readDb ?? self.db else { continuation.resume(returning: nil); return }
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                let sql = "SELECT json FROM card_prices WHERE brand = ? AND card_key = ? LIMIT 1;"
                guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: nil); return
                }
                brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                cardKey.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
                guard sqlite3_step(stmt) == SQLITE_ROW else { continuation.resume(returning: nil); return }
                let n = sqlite3_column_bytes(stmt, 0)
                guard let p = sqlite3_column_blob(stmt, 0) else { continuation.resume(returning: nil); return }
                continuation.resume(returning: Data(bytes: p, count: Int(n)))
            }
        }
    }

    func fetchCardPricesForSet(setCode: String, brand: TCGBrand) async -> [CardPriceRow] {
        let normalizedSet = setCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedSet.isEmpty else { return [] }
        return await withCheckedContinuation { continuation in
            readQueue.async {
                guard let handle = self.readDb ?? self.db else { continuation.resume(returning: []); return }
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                let sql = "SELECT card_key, json FROM card_prices WHERE brand = ? AND set_code = ?;"
                guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: []); return
                }
                brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                normalizedSet.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
                var rows: [CardPriceRow] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let keyC = sqlite3_column_text(stmt, 0) else { continue }
                    let key = String(cString: keyC)
                    let n = sqlite3_column_bytes(stmt, 1)
                    guard let p = sqlite3_column_blob(stmt, 1) else { continue }
                    rows.append(CardPriceRow(cardKey: key, json: Data(bytes: p, count: Int(n))))
                }
                continuation.resume(returning: rows)
            }
        }
    }

    /// Fetches every card_prices row for a brand in one query. Returns card_key → json blob.
    func fetchAllCardPrices(brand: TCGBrand) async -> [String: Data] {
        await withCheckedContinuation { continuation in
            readQueue.async {
                guard let handle = self.readDb ?? self.db else { continuation.resume(returning: [:]); return }
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                let sql = "SELECT card_key, json FROM card_prices WHERE brand = ?;"
                guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: [:]); return
                }
                brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                var result: [String: Data] = [:]
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let keyC = sqlite3_column_text(stmt, 0) else { continue }
                    let key = String(cString: keyC)
                    let n = sqlite3_column_bytes(stmt, 1)
                    guard let p = sqlite3_column_blob(stmt, 1) else { continue }
                    result[key] = Data(bytes: p, count: Int(n))
                }
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Normalized price history points

    struct PriceHistoryPoint {
        let cardKey: String
        let variant: String
        let grade: String
        let periodType: String
        let periodKey: String
        let price: Double
    }

    func upsertPriceHistoryPoints(brand: TCGBrand, setCode: String, points: [PriceHistoryPoint]) async throws {
        guard !points.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let db = self.db else { throw CatalogStoreError.notOpen }
                    guard sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else { throw CatalogStoreError.execFailed }
                    var stmt: OpaquePointer?
                    let sql = """
                    INSERT INTO price_history_points(brand, set_code, card_key, variant, grade, period_type, period_key, price)
                    VALUES(?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(brand, set_code, card_key, variant, grade, period_type, period_key) DO UPDATE SET price = excluded.price;
                    """
                    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                        sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                        throw CatalogStoreError.prepareFailed
                    }
                    defer { sqlite3_finalize(stmt) }
                    for pt in points {
                        sqlite3_reset(stmt)
                        sqlite3_clear_bindings(stmt)
                        brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                        setCode.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
                        pt.cardKey.withCString { _ = sqlite3_bind_text(stmt, 3, $0, -1, CatalogSQLite.transient) }
                        pt.variant.withCString { _ = sqlite3_bind_text(stmt, 4, $0, -1, CatalogSQLite.transient) }
                        pt.grade.withCString { _ = sqlite3_bind_text(stmt, 5, $0, -1, CatalogSQLite.transient) }
                        pt.periodType.withCString { _ = sqlite3_bind_text(stmt, 6, $0, -1, CatalogSQLite.transient) }
                        pt.periodKey.withCString { _ = sqlite3_bind_text(stmt, 7, $0, -1, CatalogSQLite.transient) }
                        _ = sqlite3_bind_double(stmt, 8, pt.price)
                        guard sqlite3_step(stmt) == SQLITE_DONE else {
                            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                            throw CatalogStoreError.execFailed
                        }
                    }
                    guard sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
                        sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                        throw CatalogStoreError.execFailed
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func fetchPriceHistoryPoints(brand: TCGBrand, setCode: String) async -> [PriceHistoryPoint] {
        let normalizedSet = setCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedSet.isEmpty else { return [] }
        return await withCheckedContinuation { continuation in
            readQueue.async {
                guard let handle = self.readDb ?? self.db else { continuation.resume(returning: []); return }
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                let sql = "SELECT card_key, variant, grade, period_type, period_key, price FROM price_history_points WHERE brand = ? AND set_code = ? ORDER BY period_key ASC;"
                guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: []); return
                }
                brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                normalizedSet.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
                var results: [PriceHistoryPoint] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                    func str(_ col: Int32) -> String {
                        guard let c = sqlite3_column_text(stmt, col) else { return "" }
                        return String(cString: c)
                    }
                    results.append(PriceHistoryPoint(
                        cardKey: str(0),
                        variant: str(1),
                        grade: str(2),
                        periodType: str(3),
                        periodKey: str(4),
                        price: sqlite3_column_double(stmt, 5)
                    ))
                }
                continuation.resume(returning: results)
            }
        }
    }

    func fetchPriceHistoryPoints(brand: TCGBrand, cardKey: String) async -> [PriceHistoryPoint] {
        await withCheckedContinuation { continuation in
            readQueue.async {
                guard let handle = self.readDb ?? self.db else { continuation.resume(returning: []); return }
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                let sql = "SELECT card_key, variant, grade, period_type, period_key, price FROM price_history_points WHERE brand = ? AND card_key = ? ORDER BY period_key ASC;"
                guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: []); return
                }
                brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                cardKey.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
                var results: [PriceHistoryPoint] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                    func str(_ col: Int32) -> String {
                        guard let c = sqlite3_column_text(stmt, col) else { return "" }
                        return String(cString: c)
                    }
                    results.append(PriceHistoryPoint(
                        cardKey: str(0),
                        variant: str(1),
                        grade: str(2),
                        periodType: str(3),
                        periodKey: str(4),
                        price: sqlite3_column_double(stmt, 5)
                    ))
                }
                continuation.resume(returning: results)
            }
        }
    }

    /// FTS5 prefix search: returns (masterCardId, setCode) pairs ordered by FTS rank.
    /// The query string is tokenized by FTS5's ascii tokenizer; a trailing `*` enables prefix matching.
    func searchCards(query: String, brand: TCGBrand) async -> [CardRef] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let ftsQuery = trimmed.split(whereSeparator: \.isWhitespace)
            .map { String($0) + "*" }
            .joined(separator: " ")
        return await withCheckedContinuation { continuation in
            readQueue.async {
                guard let handle = self.readDb ?? self.db else { continuation.resume(returning: []); return }
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                let sql = "SELECT master_card_id, set_code FROM catalog_cards_fts WHERE brand = ? AND catalog_cards_fts MATCH ? ORDER BY rank LIMIT 200;"
                guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: [])
                    return
                }
                brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                ftsQuery.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
                var out: [CardRef] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let mid = sqlite3_column_text(stmt, 0), let sc = sqlite3_column_text(stmt, 1) else { continue }
                    out.append(CardRef(masterCardId: String(cString: mid), setCode: String(cString: sc)))
                }
                continuation.resume(returning: out)
            }
        }
    }

    func fetchPricingData(setCode: String, brand: TCGBrand) async -> Data? {
        await withCheckedContinuation { continuation in
            readQueue.async {
                guard let handle = self.readDb ?? self.db else { continuation.resume(returning: nil); return }
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                let sql = "SELECT json FROM card_pricing WHERE brand = ? AND set_code = ? LIMIT 1;"
                guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: nil); return
                }
                brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                setCode.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
                guard sqlite3_step(stmt) == SQLITE_ROW else { continuation.resume(returning: nil); return }
                let n = sqlite3_column_bytes(stmt, 0)
                guard let p = sqlite3_column_blob(stmt, 0) else { continuation.resume(returning: nil); return }
                continuation.resume(returning: Data(bytes: p, count: Int(n)))
            }
        }
    }

    /// Per-set price history JSON (`pricing/price-history/…` or ONE PIECE `pricing/history/…`), refreshed with daily market pricing after 03:00 local.
    func upsertPriceHistory(setCode: String, json: Data, brand: TCGBrand) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let db = self.db else { throw CatalogStoreError.notOpen }
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
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func fetchPriceHistoryData(setCode: String, brand: TCGBrand) async -> Data? {
        await withCheckedContinuation { continuation in
            readQueue.async {
                guard let handle = self.readDb ?? self.db else { continuation.resume(returning: nil); return }
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                let sql = "SELECT json FROM card_price_history WHERE brand = ? AND set_code = ? LIMIT 1;"
                guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: nil); return
                }
                brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                setCode.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
                guard sqlite3_step(stmt) == SQLITE_ROW else { continuation.resume(returning: nil); return }
                let n = sqlite3_column_bytes(stmt, 0)
                guard let p = sqlite3_column_blob(stmt, 0) else { continuation.resume(returning: nil); return }
                continuation.resume(returning: Data(bytes: p, count: Int(n)))
            }
        }
    }

    /// Per-set price trends JSON (`pricing/price-trends/…` or ONE PIECE `pricing/trends/…`), refreshed with daily market pricing after 03:00 local.
    func upsertPriceTrends(setCode: String, json: Data, brand: TCGBrand) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let db = self.db else { throw CatalogStoreError.notOpen }
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
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func fetchPriceTrendsData(setCode: String, brand: TCGBrand) async -> Data? {
        await withCheckedContinuation { continuation in
            readQueue.async {
                guard let handle = self.readDb ?? self.db else { continuation.resume(returning: nil); return }
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                let sql = "SELECT json FROM card_price_trends WHERE brand = ? AND set_code = ? LIMIT 1;"
                guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: nil); return
                }
                brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                setCode.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
                guard sqlite3_step(stmt) == SQLITE_ROW else { continuation.resume(returning: nil); return }
                let n = sqlite3_column_bytes(stmt, 0)
                guard let p = sqlite3_column_blob(stmt, 0) else { continuation.resume(returning: nil); return }
                continuation.resume(returning: Data(bytes: p, count: Int(n)))
            }
        }
    }

    /// Fetches all price-trends rows for a brand in one query. Returns a dict of set_code → json blob.
    func fetchAllPriceTrendsData(brand: TCGBrand) async -> [String: Data] {
        await withCheckedContinuation { continuation in
            readQueue.async {
                guard let handle = self.readDb ?? self.db else { continuation.resume(returning: [:]); return }
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                let sql = "SELECT set_code, json FROM card_price_trends WHERE brand = ?;"
                guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: [:]); return
                }
                brand.rawValue.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                var result: [String: Data] = [:]
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let keyC = sqlite3_column_text(stmt, 0) else { continue }
                    let key = String(cString: keyC)
                    let n = sqlite3_column_bytes(stmt, 1)
                    guard let p = sqlite3_column_blob(stmt, 1) else { continue }
                    result[key] = Data(bytes: p, count: Int(n))
                }
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Daily blobs

    func upsertDailyBlob(key: String, data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let db = self.db else { throw CatalogStoreError.notOpen }
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
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func dailyBlob(key: String) async -> Data? {
        await withCheckedContinuation { continuation in
            readQueue.async {
                guard let handle = self.readDb ?? self.db else { continuation.resume(returning: nil); return }
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                guard sqlite3_prepare_v2(handle, "SELECT json FROM daily_blobs WHERE key = ? LIMIT 1;", -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: nil); return
                }
                key.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                guard sqlite3_step(stmt) == SQLITE_ROW else { continuation.resume(returning: nil); return }
                let n = sqlite3_column_bytes(stmt, 0)
                guard let p = sqlite3_column_blob(stmt, 0) else { continuation.resume(returning: nil); return }
                continuation.resume(returning: Data(bytes: p, count: Int(n)))
            }
        }
    }

    func dailyBlobFetchedAt(key: String) async -> Date? {
        await withCheckedContinuation { continuation in
            readQueue.async {
                guard let handle = self.readDb ?? self.db else { continuation.resume(returning: nil); return }
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                guard sqlite3_prepare_v2(handle, "SELECT fetched_at FROM daily_blobs WHERE key = ? LIMIT 1;", -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: nil); return
                }
                key.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                guard sqlite3_step(stmt) == SQLITE_ROW else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0)))
            }
        }
    }

    /// Bumps `fetched_at` without replacing the blob (used after HTTP `304 Not Modified`).
    /// Resets `fetched_at` to epoch 0 so the daily freshness gate treats the blob as stale,
    /// forcing re-download on the next sync even if the blob was already fetched today.
    func staleDailyBlobFetchedAt(key: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                guard let db = self.db else { continuation.resume(); return }
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                guard sqlite3_prepare_v2(db, "UPDATE daily_blobs SET fetched_at = 0 WHERE key = ?;", -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(); return
                }
                key.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                _ = sqlite3_step(stmt)
                continuation.resume()
            }
        }
    }

    func touchDailyBlobFetchedAt(key: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let db = self.db else { throw CatalogStoreError.notOpen }
                    var stmt: OpaquePointer?
                    defer { sqlite3_finalize(stmt) }
                    let sql = "UPDATE daily_blobs SET fetched_at = ? WHERE key = ?;"
                    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
                    _ = sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
                    key.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
                    guard sqlite3_step(stmt) == SQLITE_DONE else { throw CatalogStoreError.execFailed }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Aux blobs (non-set metadata payloads)

    func upsertAuxBlob(key: String, data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let db = self.db else { throw CatalogStoreError.notOpen }
                    var stmt: OpaquePointer?
                    defer { sqlite3_finalize(stmt) }
                    let sql = """
                    INSERT INTO catalog_aux_blobs(key, json, fetched_at) VALUES(?, ?, ?)
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
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func auxBlob(key: String) async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let db = self.db else {
                    continuation.resume(returning: nil)
                    return
                }
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                guard sqlite3_prepare_v2(db, "SELECT json FROM catalog_aux_blobs WHERE key = ? LIMIT 1;", -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: nil)
                    return
                }
                key.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                guard sqlite3_step(stmt) == SQLITE_ROW else {
                    continuation.resume(returning: nil)
                    return
                }
                let n = sqlite3_column_bytes(stmt, 0)
                guard let p = sqlite3_column_blob(stmt, 0) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Data(bytes: p, count: Int(n)))
            }
        }
    }

    func touchAuxBlobFetchedAt(key: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let db = self.db else { throw CatalogStoreError.notOpen }
                    var stmt: OpaquePointer?
                    defer { sqlite3_finalize(stmt) }
                    let sql = "UPDATE catalog_aux_blobs SET fetched_at = ? WHERE key = ?;"
                    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
                    _ = sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
                    key.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
                    guard sqlite3_step(stmt) == SQLITE_DONE else { throw CatalogStoreError.execFailed }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func deleteAuxBlob(key: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let db = self.db else { throw CatalogStoreError.notOpen }
                    var stmt: OpaquePointer?
                    defer { sqlite3_finalize(stmt) }
                    let sql = "DELETE FROM catalog_aux_blobs WHERE key = ?;"
                    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
                    key.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                    guard sqlite3_step(stmt) == SQLITE_DONE else { throw CatalogStoreError.execFailed }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Pricing bucket tracking

    func markBucketProcessed(key: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let db = self.db else { throw CatalogStoreError.notOpen }
                    var stmt: OpaquePointer?
                    defer { sqlite3_finalize(stmt) }
                    let sql = """
                    INSERT INTO processed_pricing_buckets(bucket_key, processed_at) VALUES(?, ?)
                    ON CONFLICT(bucket_key) DO UPDATE SET processed_at = excluded.processed_at;
                    """
                    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
                    key.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                    _ = sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
                    guard sqlite3_step(stmt) == SQLITE_DONE else { throw CatalogStoreError.execFailed }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func isBucketProcessed(key: String) async -> Bool {
        await withCheckedContinuation { continuation in
            readQueue.async {
                guard let handle = self.readDb ?? self.db else { continuation.resume(returning: false); return }
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                guard sqlite3_prepare_v2(handle, "SELECT 1 FROM processed_pricing_buckets WHERE bucket_key = ? LIMIT 1;", -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: false); return
                }
                key.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                continuation.resume(returning: sqlite3_step(stmt) == SQLITE_ROW)
            }
        }
    }

    func unprocessedBucketKeys(from candidates: [String]) async -> [String] {
        guard !candidates.isEmpty else { return [] }
        return await withCheckedContinuation { continuation in
            readQueue.async {
                guard let handle = self.readDb ?? self.db else { continuation.resume(returning: candidates); return }
                let placeholders = candidates.map { _ in "?" }.joined(separator: ",")
                let sql = "SELECT bucket_key FROM processed_pricing_buckets WHERE bucket_key IN (\(placeholders));"
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: candidates); return
                }
                for (i, key) in candidates.enumerated() {
                    key.withCString { _ = sqlite3_bind_text(stmt, Int32(i + 1), $0, -1, CatalogSQLite.transient) }
                }
                var processed = Set<String>()
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let cStr = sqlite3_column_text(stmt, 0) { processed.insert(String(cString: cStr)) }
                }
                continuation.resume(returning: candidates.filter { !processed.contains($0) })
            }
        }
    }

    func unmarkBucketProcessed(key: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                guard let db = self.db else { continuation.resume(); return }
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                guard sqlite3_prepare_v2(db, "DELETE FROM processed_pricing_buckets WHERE bucket_key = ?;", -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(); return
                }
                key.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                _ = sqlite3_step(stmt)
                continuation.resume()
            }
        }
    }

    /// Returns the set of all bucket keys that start with `prefix` — used by backfill to avoid
    /// building a huge candidate list when most periods are already processed.
    func processedBucketKeys(withPrefix prefix: String) async -> Set<String> {
        return await withCheckedContinuation { continuation in
            readQueue.async {
                guard let handle = self.readDb ?? self.db else { continuation.resume(returning: []); return }
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                let sql = "SELECT bucket_key FROM processed_pricing_buckets WHERE bucket_key LIKE ? ESCAPE '\\';"
                guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: []); return
                }
                let escaped = prefix.replacingOccurrences(of: "\\", with: "\\\\")
                                    .replacingOccurrences(of: "%", with: "\\%")
                                    .replacingOccurrences(of: "_", with: "\\_") + "%"
                escaped.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                var result = Set<String>()
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let cStr = sqlite3_column_text(stmt, 0) { result.insert(String(cString: cStr)) }
                }
                continuation.resume(returning: result)
            }
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
