import Foundation
import SQLite3

/// SQLite copy destructor; kept in a trivial type so it is not tied to actor / main-actor inference.
private enum CatalogSQLite {
    static let transient: sqlite3_destructor_type = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

/// Local SQLite catalog: sets, cards, per-set card pricing JSON, and daily blob payloads (Pokedata / trends).
///
/// All `sqlite3_*` calls run on a **single serial queue**. Swift’s `actor` executor can hop OS threads
/// between calls; that still satisfies SQLite’s mutex mode but can trigger internal `SQLITE_MISUSE`
/// logging on some Apple builds. A dedicated queue matches the usual “one serial queue per connection” pattern.
final class CatalogStore: @unchecked Sendable {
    static let shared = CatalogStore()

    private let queue = DispatchQueue(label: "com.poketrack.catalog.sqlite", qos: .utility)
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
        ).appendingPathComponent("PokeTrack", isDirectory: true)
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
        """
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, ddl, nil, nil, &err) == SQLITE_OK else {
            if let e = err { sqlite3_free(e) }
            throw CatalogStoreError.migrationFailed
        }
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

    // MARK: - Catalog

    func hasAnyCards() throws -> Bool {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM catalog_cards;", -1, &stmt, nil) == SQLITE_OK else {
                throw CatalogStoreError.prepareFailed
            }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return false }
            return sqlite3_column_int64(stmt, 0) > 0
        }
    }

    func clearCatalog() throws {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            sqlite3_exec(db, "DELETE FROM catalog_cards;", nil, nil, nil)
            sqlite3_exec(db, "DELETE FROM catalog_sets;", nil, nil, nil)
            sqlite3_exec(db, "DELETE FROM card_pricing;", nil, nil, nil)
        }
    }

    func upsertSet(_ set: TCGSet) throws {
        try queue.sync {
            let data = try jsonEncoder.encode(set)
            guard let json = String(data: data, encoding: .utf8) else { throw CatalogStoreError.encodeFailed }
            try upsertSetRawLocked(setCode: set.setCode, json: json)
        }
    }

    private func upsertSetRawLocked(setCode: String, json: String) throws {
        guard let db else { throw CatalogStoreError.notOpen }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "INSERT INTO catalog_sets(set_code, json) VALUES(?, ?) ON CONFLICT(set_code) DO UPDATE SET json = excluded.json;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
        setCode.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
        json.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw CatalogStoreError.execFailed }
    }

    func deleteCards(forSet setCode: String) throws {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "DELETE FROM catalog_cards WHERE set_code = ?;", -1, &stmt, nil) == SQLITE_OK else {
                throw CatalogStoreError.prepareFailed
            }
            setCode.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
            _ = sqlite3_step(stmt)
        }
    }

    func insertCards(_ cards: [Card], setCode: String) throws {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = "INSERT OR REPLACE INTO catalog_cards(set_code, master_card_id, json) VALUES(?, ?, ?);"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
            for card in cards {
                let blob = try jsonEncoder.encode(card)
                guard let j = String(data: blob, encoding: .utf8) else { continue }
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                setCode.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
                card.masterCardId.withCString { _ = sqlite3_bind_text(stmt, 2, $0, -1, CatalogSQLite.transient) }
                j.withCString { _ = sqlite3_bind_text(stmt, 3, $0, -1, CatalogSQLite.transient) }
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw CatalogStoreError.execFailed }
            }
        }
    }

    func upsertPricing(setCode: String, json: Data) throws {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = """
            INSERT INTO card_pricing(set_code, json, fetched_at) VALUES(?, ?, ?)
            ON CONFLICT(set_code) DO UPDATE SET json = excluded.json, fetched_at = excluded.fetched_at;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
            setCode.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
            if json.isEmpty {
                _ = sqlite3_bind_blob(stmt, 2, nil, 0, CatalogSQLite.transient)
            } else {
                json.withUnsafeBytes { buf in
                    _ = sqlite3_bind_blob(stmt, 2, buf.baseAddress, Int32(json.count), CatalogSQLite.transient)
                }
            }
            _ = sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw CatalogStoreError.execFailed }
        }
    }

    func fetchAllSets() throws -> [TCGSet] {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "SELECT json FROM catalog_sets ORDER BY set_code;", -1, &stmt, nil) == SQLITE_OK else {
                throw CatalogStoreError.prepareFailed
            }
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

    func fetchCards(setCode: String) throws -> [Card] {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(
                db,
                "SELECT json FROM catalog_cards WHERE set_code = ? ORDER BY master_card_id;",
                -1,
                &stmt,
                nil
            ) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
            setCode.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
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

    /// Lightweight index of every card row (for browse grids, shuffles, etc.).
    func fetchAllCardRefs() throws -> [CardRef] {
        try queue.sync {
            guard let db else { throw CatalogStoreError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(
                db,
                "SELECT set_code, master_card_id FROM catalog_cards;",
                -1,
                &stmt,
                nil
            ) == SQLITE_OK else { throw CatalogStoreError.prepareFailed }
            var out: [CardRef] = []
            out.reserveCapacity(10_000)
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let sc = sqlite3_column_text(stmt, 0), let mid = sqlite3_column_text(stmt, 1) else { continue }
                out.append(CardRef(masterCardId: String(cString: mid), setCode: String(cString: sc)))
            }
            return out
        }
    }

    func fetchPricingData(setCode: String) -> Data? {
        queue.sync {
            guard let db else { return nil }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "SELECT json FROM card_pricing WHERE set_code = ? LIMIT 1;", -1, &stmt, nil) == SQLITE_OK else {
                return nil
            }
            setCode.withCString { _ = sqlite3_bind_text(stmt, 1, $0, -1, CatalogSQLite.transient) }
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
}

enum CatalogStoreError: Error {
    case openFailed
    case migrationFailed
    case notOpen
    case prepareFailed
    case execFailed
    case encodeFailed
}
