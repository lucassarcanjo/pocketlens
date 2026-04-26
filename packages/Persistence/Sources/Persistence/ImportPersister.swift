import Foundation
import GRDB
import Domain
import Importing

/// Persists an `ImportPlan` produced by the import pipeline into a single
/// GRDB write transaction. All-or-nothing: either every row lands or
/// none do.
public struct ImportPersister: Sendable {

    public enum Error: Swift.Error, Equatable, Sendable {
        case alreadyImported(batch: ImportBatch)
    }

    public let store: SQLiteStore

    public init(store: SQLiteStore) {
        self.store = store
    }

    public struct PersistResult: Sendable {
        public let batch: ImportBatch
        public let transactionCount: Int
        public let cardCount: Int
        public let merchantCount: Int

        public init(batch: ImportBatch, transactionCount: Int, cardCount: Int, merchantCount: Int) {
            self.batch = batch
            self.transactionCount = transactionCount
            self.cardCount = cardCount
            self.merchantCount = merchantCount
        }
    }

    /// File-level dedup gate. Throws `.alreadyImported` if the SHA-256 has
    /// been seen before; the UI surfaces this as
    /// "already imported as batch #N on YYYY-MM-DD".
    public func persist(
        plan: ImportPlan,
        bankName: String,
        primaryHolderName: String? = nil
    ) async throws -> PersistResult {
        try await store.queue.write { db in
            // Short-circuit on duplicate file.
            if let existing = try ImportBatchRecord
                .filter(Column("source_file_sha256") == plan.batch.sourceFileSha256)
                .fetchOne(db)
            {
                throw Error.alreadyImported(batch: existing.toDomain())
            }

            // Account: find or create by (bankName, holderName).
            let holder = primaryHolderName ?? plan.cards.first?.holderName ?? "Unknown"
            let accountId: Int64 = try {
                if let existing = try AccountRecord
                    .filter(Column("bank_name") == bankName)
                    .filter(Column("holder_name") == holder)
                    .fetchOne(db)
                {
                    return existing.id!
                }
                var rec = AccountRecord(from: Account(
                    bankName: bankName, holderName: holder
                ))
                try rec.insert(db)
                return rec.id!
            }()

            // Cards: upsert by (account_id, last4). Map last4 → card.id.
            var cardIdByLast4: [String: Int64] = [:]
            for card in plan.cards {
                if let existing = try CardRecord
                    .filter(Column("account_id") == accountId)
                    .filter(Column("last4") == card.last4)
                    .fetchOne(db)
                {
                    cardIdByLast4[card.last4] = existing.id!
                } else {
                    var rec = CardRecord(from: card, accountId: accountId)
                    try rec.insert(db)
                    cardIdByLast4[card.last4] = rec.id!
                }
            }

            // Merchants: upsert by normalized. Map normalized → merchant.id.
            var merchantIdByNormalized: [String: Int64] = [:]
            for m in plan.merchants {
                if let existing = try MerchantRecord
                    .filter(Column("normalized") == m.normalized)
                    .fetchOne(db)
                {
                    merchantIdByNormalized[m.normalized] = existing.id!
                } else {
                    var rec = MerchantRecord(from: m)
                    try rec.insert(db)
                    merchantIdByNormalized[m.normalized] = rec.id!
                }
            }

            // ImportBatch.
            var batchRec = ImportBatchRecord(from: plan.batch)
            try batchRec.insert(db)
            let batchId = batchRec.id!

            // Transactions.
            for pending in plan.transactions {
                guard let cardId = cardIdByLast4[pending.cardLast4] else {
                    // Validator should have caught orphan cards, but be safe.
                    continue
                }
                let merchantId = merchantIdByNormalized[pending.merchantNormalized]
                var txRec = TransactionRecord(
                    from: pending.transaction,
                    fingerprint: pending.fingerprint,
                    importBatchId: batchId,
                    cardId: cardId,
                    merchantId: merchantId
                )
                try txRec.insert(db)
            }

            return PersistResult(
                batch: batchRec.toDomain(),
                transactionCount: plan.transactions.count,
                cardCount: plan.cards.count,
                merchantCount: plan.merchants.count
            )
        }
    }
}
