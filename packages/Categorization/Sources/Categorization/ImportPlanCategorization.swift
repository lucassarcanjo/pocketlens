import Foundation
import Domain
import Importing

extension CategorizationEngine {

    /// Categorize every `PendingTransaction` in a plan against the current
    /// DB state. Returns a new plan with each transaction's `categoryId`,
    /// `confidence`, and `categorizationReason` populated by the engine.
    ///
    /// `bankName` is the issuing bank for the parent account — drives the
    /// `BankCategoryStrategy` lookup. Passed in (rather than reading it off
    /// the plan) because the plan's batch carries no bank affiliation; the
    /// caller's `ImportPipeline.defaultBankName` is the source of truth.
    ///
    /// The engine only reads existing rows, so this is safe to call before
    /// `ImportPersister.persist(...)`. We don't run inside the persist
    /// transaction because the engine's strategies use repos that open their
    /// own DB transactions.
    public func apply(to plan: ImportPlan, bankName: String) async throws -> ImportPlan {
        var newTransactions: [PendingTransaction] = []
        newTransactions.reserveCapacity(plan.transactions.count)

        for pending in plan.transactions {
            let input = CategorizationInput(
                merchantNormalized: pending.merchantNormalized,
                bankCategoryRaw: pending.transaction.bankCategoryRaw,
                bankName: bankName,
                amount: pending.transaction.amount,
                fingerprint: pending.fingerprint
            )
            let suggestion = try await categorize(input)

            var tx = pending.transaction
            tx.categoryId = suggestion.categoryId
            tx.confidence = suggestion.confidence
            tx.categorizationReason = suggestion.explanation
            tx.updatedAt = Date()

            newTransactions.append(PendingTransaction(
                cardLast4: pending.cardLast4,
                merchantNormalized: pending.merchantNormalized,
                transaction: tx,
                fingerprint: pending.fingerprint
            ))
        }

        return ImportPlan(
            batch: plan.batch,
            cards: plan.cards,
            merchants: plan.merchants,
            transactions: newTransactions
        )
    }
}
