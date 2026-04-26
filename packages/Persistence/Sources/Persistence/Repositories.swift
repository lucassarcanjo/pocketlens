import Foundation
import GRDB
import Domain

/// Async repositories over the v1 schema. Each method runs on the GRDB
/// scheduling queue via `dbQueue.write`/`read`.

public struct AccountRepository: Sendable {
    let dbQueue: DatabaseQueue

    public init(store: SQLiteStore) { self.dbQueue = store.queue }

    /// Find by (bankName, holderName) — current uniqueness key for
    /// upserts. We don't have a UNIQUE constraint on this pair on disk
    /// (Phase 1 only ever sees one Itaú account), so this is a soft lookup.
    public func findOrCreate(bankName: String, holderName: String) async throws -> Account {
        try await dbQueue.write { db in
            if let existing = try AccountRecord
                .filter(Column("bank_name") == bankName)
                .filter(Column("holder_name") == holderName)
                .fetchOne(db)
            {
                return existing.toDomain()
            }
            var rec = AccountRecord(from: Account(
                bankName: bankName, holderName: holderName
            ))
            try rec.insert(db)
            return rec.toDomain()
        }
    }

    public func all() async throws -> [Account] {
        try await dbQueue.read { db in
            try AccountRecord.fetchAll(db).map { $0.toDomain() }
        }
    }
}

public struct CardRepository: Sendable {
    let dbQueue: DatabaseQueue

    public init(store: SQLiteStore) { self.dbQueue = store.queue }

    /// Upsert by (account_id, last4) — the table's unique key. Holder /
    /// network / tier are taken from the incoming `Card` if the row is new
    /// or refreshed if it already exists with different metadata.
    public func upsert(_ card: Card, accountId: Int64) async throws -> Card {
        try await dbQueue.write { db in
            if let existing = try CardRecord
                .filter(Column("account_id") == accountId)
                .filter(Column("last4") == card.last4)
                .fetchOne(db)
            {
                return existing.toDomain()
            }
            var rec = CardRecord(from: card, accountId: accountId)
            try rec.insert(db)
            return rec.toDomain()
        }
    }

    public func all() async throws -> [Card] {
        try await dbQueue.read { db in
            try CardRecord.fetchAll(db).map { $0.toDomain() }
        }
    }
}

public struct MerchantRepository: Sendable {
    let dbQueue: DatabaseQueue

    public init(store: SQLiteStore) { self.dbQueue = store.queue }

    /// Upsert by `normalized` (UNIQUE on disk). First-seen `raw` and
    /// `default_category_id` win — Phase 2 will rework this when aliases land.
    public func upsert(_ merchant: Merchant) async throws -> Merchant {
        try await dbQueue.write { db in
            if let existing = try MerchantRecord
                .filter(Column("normalized") == merchant.normalized)
                .fetchOne(db)
            {
                return existing.toDomain()
            }
            var rec = MerchantRecord(from: merchant)
            try rec.insert(db)
            return rec.toDomain()
        }
    }

    public func all() async throws -> [Merchant] {
        try await dbQueue.read { db in
            try MerchantRecord.fetchAll(db).map { $0.toDomain() }
        }
    }
}

public struct CategoryRepository: Sendable {
    let dbQueue: DatabaseQueue

    public init(store: SQLiteStore) { self.dbQueue = store.queue }

    public func all() async throws -> [Domain.Category] {
        try await dbQueue.read { db in
            try CategoryRecord
                .order(Column("id"))
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func count() async throws -> Int {
        try await dbQueue.read { db in
            try CategoryRecord.fetchCount(db)
        }
    }

    public func insert(_ category: Domain.Category) async throws -> Domain.Category {
        try await dbQueue.write { db in
            var rec = CategoryRecord(from: category)
            try rec.insert(db)
            return rec.toDomain()
        }
    }
}

public struct ImportBatchRepository: Sendable {
    let dbQueue: DatabaseQueue

    public init(store: SQLiteStore) { self.dbQueue = store.queue }

    /// Returns existing batch when SHA-256 already imported. Caller surfaces
    /// the friendly "already imported as batch #N on …" message.
    public func findBySha256(_ sha: String) async throws -> ImportBatch? {
        try await dbQueue.read { db in
            try ImportBatchRecord
                .filter(Column("source_file_sha256") == sha)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func insert(_ batch: ImportBatch) async throws -> ImportBatch {
        try await dbQueue.write { db in
            var rec = ImportBatchRecord(from: batch)
            try rec.insert(db)
            return rec.toDomain()
        }
    }

    public func all() async throws -> [ImportBatch] {
        try await dbQueue.read { db in
            try ImportBatchRecord
                .order(Column("imported_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }
}

public struct TransactionRepository: Sendable {
    let dbQueue: DatabaseQueue

    public init(store: SQLiteStore) { self.dbQueue = store.queue }

    /// Insert a single transaction. Caller is responsible for pre-resolving
    /// merchantId / cardId / importBatchId.
    public func insert(
        _ transaction: Transaction,
        fingerprint: String,
        importBatchId: Int64,
        cardId: Int64,
        merchantId: Int64?
    ) async throws -> Transaction {
        try await dbQueue.write { db in
            var rec = TransactionRecord(
                from: transaction,
                fingerprint: fingerprint,
                importBatchId: importBatchId,
                cardId: cardId,
                merchantId: merchantId
            )
            try rec.insert(db)
            return rec.toDomain()
        }
    }

    public func updateCategory(transactionId: Int64, categoryId: Int64?) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE transactions SET category_id = ?, updated_at = ? WHERE id = ?",
                arguments: [categoryId, DateFmt.iso8601.string(from: Date()), transactionId]
            )
        }
    }

    public func all() async throws -> [Transaction] {
        try await dbQueue.read { db in
            try TransactionRecord
                .order(Column("posted_date").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func forBatch(_ importBatchId: Int64) async throws -> [Transaction] {
        try await dbQueue.read { db in
            try TransactionRecord
                .filter(Column("import_batch_id") == importBatchId)
                .order(Column("posted_date"))
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func forCard(_ cardId: Int64) async throws -> [Transaction] {
        try await dbQueue.read { db in
            try TransactionRecord
                .filter(Column("card_id") == cardId)
                .order(Column("posted_date").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }
}
