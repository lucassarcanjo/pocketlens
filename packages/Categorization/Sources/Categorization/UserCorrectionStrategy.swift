import Foundation
import Domain
import Persistence

/// Slot 1 — exact prior user correction.
///
/// Looks up an existing transaction row that shares the input's fingerprint,
/// then checks for a `user_corrections` entry. The most recent correction
/// wins. Confidence is fixed at 1.00 — the user told us this category.
///
/// In a re-import scenario the same fingerprint also gates dedup, so this
/// strategy primarily fires when re-categorizing an existing row. Phase 4's
/// bank-statement linkage will introduce a softer match (merchant_normalized
/// alone) for cross-statement learning.
public struct UserCorrectionStrategy: CategorizationStrategy {
    public let reason: CategorizationReason = .userCorrection
    let store: SQLiteStore

    public init(store: SQLiteStore) { self.store = store }

    public func categorize(_ input: CategorizationInput) async throws -> CategorizationSuggestion? {
        let txRepo = TransactionRepository(store: store)
        let correctionRepo = UserCorrectionRepository(store: store)

        guard let priorTx = try await txRepo.findByFingerprint(input.fingerprint),
              let priorTxId = priorTx.id
        else { return nil }

        let corrections = try await correctionRepo.forTransaction(priorTxId)
        guard let latest = corrections.first else { return nil }

        return CategorizationSuggestion(
            categoryId: latest.newCategoryId,
            confidence: 1.00,
            reason: .userCorrection,
            explanation: "Prior user correction on this transaction"
        )
    }
}
