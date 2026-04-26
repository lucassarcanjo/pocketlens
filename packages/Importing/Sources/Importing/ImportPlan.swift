import Foundation
import Domain
import LLM

/// Result of running the import pipeline up to but excluding the persistence
/// step. Pure value types — testable without a database.
///
/// `ImportPipeline.dryRun(...)` returns this. Persisting it (Task #6/8) takes
/// these structures, upserts into accounts/cards/merchants, and writes the
/// `ImportBatch` + `Transaction` rows in one GRDB transaction.
public struct ImportPlan: Sendable {
    public var batch: ImportBatch
    public var cards: [Card]
    public var merchants: [Merchant]
    public var transactions: [PendingTransaction]

    public init(
        batch: ImportBatch,
        cards: [Card],
        merchants: [Merchant],
        transactions: [PendingTransaction]
    ) {
        self.batch = batch
        self.cards = cards
        self.merchants = merchants
        self.transactions = transactions
    }
}

/// A transaction shape that's been resolved as far as the in-memory pipeline
/// can — but still carries lookup keys (cardLast4, merchantNormalized) rather
/// than DB ids, since persistence assigns those.
public struct PendingTransaction: Sendable, Hashable {
    public var cardLast4: String
    public var merchantNormalized: String
    public var transaction: Transaction
    public var fingerprint: String

    public init(
        cardLast4: String,
        merchantNormalized: String,
        transaction: Transaction,
        fingerprint: String
    ) {
        self.cardLast4 = cardLast4
        self.merchantNormalized = merchantNormalized
        self.transaction = transaction
        self.fingerprint = fingerprint
    }
}
