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

    /// Set or clear the merchant's `default_category_id`. Used by the alias
    /// editor when adopting a transaction's category as the merchant's
    /// default — required because `upsert(_:)` preserves first-seen metadata
    /// and won't overwrite existing rows.
    public func setDefaultCategory(merchantId: Int64, categoryId: Int64?) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE merchants SET default_category_id = ?, updated_at = ? WHERE id = ?",
                arguments: [categoryId, DateFmt.iso8601.string(from: Date()), merchantId]
            )
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

    /// Update the categorization fields for a single transaction. Caller is
    /// responsible for separately writing a `UserCorrection` row when the
    /// edit is user-initiated.
    public func updateCategorization(
        transactionId: Int64,
        categoryId: Int64?,
        confidence: Double,
        reason: String
    ) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE transactions
                SET category_id = ?, confidence = ?, categorization_reason = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [categoryId, confidence, reason, DateFmt.iso8601.string(from: Date()), transactionId]
            )
        }
    }

    public func find(id: Int64) async throws -> Transaction? {
        try await dbQueue.read { db in
            try TransactionRecord
                .filter(Column("id") == id)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findByFingerprint(_ fingerprint: String) async throws -> Transaction? {
        try await dbQueue.read { db in
            try TransactionRecord
                .filter(Column("fingerprint") == fingerprint)
                .fetchOne(db)?
                .toDomain()
        }
    }

    /// All transactions that already have a category assigned. Used by the
    /// similarity strategy as the corpus to compare against.
    public func categorized() async throws -> [Transaction] {
        try await dbQueue.read { db in
            try TransactionRecord
                .filter(Column("category_id") != nil)
                .order(Column("posted_date").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }
}

// MARK: - MerchantAliasRepository

public struct MerchantAliasRepository: Sendable {
    let dbQueue: DatabaseQueue

    public init(store: SQLiteStore) { self.dbQueue = store.queue }

    public func insert(_ alias: MerchantAlias) async throws -> MerchantAlias {
        try await dbQueue.write { db in
            var rec = MerchantAliasRecord(from: alias)
            try rec.insert(db)
            return rec.toDomain()
        }
    }

    public func all() async throws -> [MerchantAlias] {
        try await dbQueue.read { db in
            try MerchantAliasRecord.fetchAll(db).map { $0.toDomain() }
        }
    }

    public func forMerchant(_ merchantId: Int64) async throws -> [MerchantAlias] {
        try await dbQueue.read { db in
            try MerchantAliasRecord
                .filter(Column("merchant_id") == merchantId)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func delete(id: Int64) async throws {
        try await dbQueue.write { db in
            _ = try MerchantAliasRecord.deleteOne(db, key: id)
        }
    }
}

// MARK: - CategorizationRuleRepository

public struct CategorizationRuleRepository: Sendable {
    let dbQueue: DatabaseQueue

    public init(store: SQLiteStore) { self.dbQueue = store.queue }

    public func insert(_ rule: CategorizationRule) async throws -> CategorizationRule {
        try await dbQueue.write { db in
            var rec = CategorizationRuleRecord(from: rule)
            try rec.insert(db)
            return rec.toDomain()
        }
    }

    public func update(_ rule: CategorizationRule) async throws -> CategorizationRule {
        try await dbQueue.write { db in
            var rec = CategorizationRuleRecord(from: rule)
            rec.updatedAt = DateFmt.iso8601.string(from: Date())
            try rec.update(db)
            return rec.toDomain()
        }
    }

    public func delete(id: Int64) async throws {
        try await dbQueue.write { db in
            _ = try CategorizationRuleRecord.deleteOne(db, key: id)
        }
    }

    public func all() async throws -> [CategorizationRule] {
        try await dbQueue.read { db in
            try CategorizationRuleRecord
                .order(Column("priority").desc, Column("id"))
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    /// Enabled rules of a given source, highest priority first. The engine
    /// queries `.user` for slot 3 and `.system` for slot 5.
    public func enabled(by source: RuleSource) async throws -> [CategorizationRule] {
        try await dbQueue.read { db in
            try CategorizationRuleRecord
                .filter(Column("enabled") == 1)
                .filter(Column("created_by") == source.rawValue)
                .order(Column("priority").desc, Column("id"))
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }
}

// MARK: - UserCorrectionRepository

public struct UserCorrectionRepository: Sendable {
    let dbQueue: DatabaseQueue

    public init(store: SQLiteStore) { self.dbQueue = store.queue }

    public func insert(_ correction: UserCorrection) async throws -> UserCorrection {
        try await dbQueue.write { db in
            var rec = UserCorrectionRecord(from: correction)
            try rec.insert(db)
            return rec.toDomain()
        }
    }

    public func all() async throws -> [UserCorrection] {
        try await dbQueue.read { db in
            try UserCorrectionRecord
                .order(Column("created_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func forTransaction(_ transactionId: Int64) async throws -> [UserCorrection] {
        try await dbQueue.read { db in
            try UserCorrectionRecord
                .filter(Column("transaction_id") == transactionId)
                .order(Column("created_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }
}

// MARK: - BankCategoryMappingRepository

public struct BankCategoryMappingRepository: Sendable {
    let dbQueue: DatabaseQueue

    public init(store: SQLiteStore) { self.dbQueue = store.queue }

    public func insert(_ mapping: BankCategoryMapping) async throws -> BankCategoryMapping {
        try await dbQueue.write { db in
            var rec = BankCategoryMappingRecord(from: mapping)
            try rec.insert(db)
            return rec.toDomain()
        }
    }

    public func all() async throws -> [BankCategoryMapping] {
        try await dbQueue.read { db in
            try BankCategoryMappingRecord.fetchAll(db).map { $0.toDomain() }
        }
    }

    /// Issuer-specific match wins over the wildcard `bank_name = NULL` row.
    /// Both lookups use casefolded `bankCategoryRaw` because rows are stored
    /// casefolded by `BankCategoryMapping.init`.
    public func find(bankName: String?, bankCategoryRaw: String) async throws -> BankCategoryMapping? {
        let needle = bankCategoryRaw.lowercased()
        return try await dbQueue.read { db in
            if let bankName,
               let issuerRow = try BankCategoryMappingRecord
                .filter(Column("bank_name") == bankName)
                .filter(Column("bank_category_raw") == needle)
                .fetchOne(db)
            {
                return issuerRow.toDomain()
            }
            return try BankCategoryMappingRecord
                .filter(Column("bank_name") == nil)
                .filter(Column("bank_category_raw") == needle)
                .fetchOne(db)?
                .toDomain()
        }
    }
}
