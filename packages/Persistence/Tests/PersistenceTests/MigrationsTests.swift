import XCTest
@testable import Persistence
import GRDB

final class MigrationsTests: XCTestCase {

    func testMigratesFreshDB() throws {
        let store = try SQLiteStore.makeInMemory()
        let tables: [String] = try store.queue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
            )
        }
        // sqlite_sequence and grdb_migrations are infra; assert the v1 set
        // is present.
        let expected: Set<String> = [
            "accounts", "cards", "categories", "import_batches",
            "merchants", "transactions",
        ]
        XCTAssertTrue(expected.isSubset(of: Set(tables)), "missing: \(expected.subtracting(Set(tables)))")
    }

    func testForeignKeysEnabled() throws {
        let store = try SQLiteStore.makeInMemory()
        let pragmaOn: Int = try store.queue.read { db in
            try Int.fetchOne(db, sql: "PRAGMA foreign_keys") ?? 0
        }
        XCTAssertEqual(pragmaOn, 1)
    }

    func testMigrationIsIdempotent() throws {
        // Re-running migrations on an already-migrated DB shouldn't error.
        let store = try SQLiteStore.makeInMemory()
        try Migrations.migrator.migrate(store.queue)
        try Migrations.migrator.migrate(store.queue)
    }

    func testTransactionsHaveUniqueFingerprintConstraint() throws {
        let store = try SQLiteStore.makeInMemory()
        let indexes: [String] = try store.queue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'transactions'"
            )
        }
        XCTAssertTrue(
            indexes.contains { $0.contains("transactions") && $0.lowercased().contains("autoindex") }
            || indexes.contains { $0.contains("fingerprint") },
            "expected a unique index on transactions.fingerprint, got: \(indexes)"
        )
    }

    func testV2TablesPresent() throws {
        let store = try SQLiteStore.makeInMemory()
        let tables: [String] = try store.queue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
            )
        }
        let expected: Set<String> = [
            "merchant_aliases", "categorization_rules",
            "user_corrections", "bank_category_mappings",
        ]
        XCTAssertTrue(expected.isSubset(of: Set(tables)),
                      "missing v2 tables: \(expected.subtracting(Set(tables)))")
    }
}
