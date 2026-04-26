import Foundation
import Domain
import Persistence

/// Slot 4 — issuer's own category label maps to a PocketLens category.
///
/// Bails immediately when the input has no `bankCategoryRaw`. Otherwise the
/// repo lookup prefers an issuer-specific row over the wildcard
/// `bank_name = NULL` row. Confidence is fixed at 0.85 — the issuer already
/// classified this merchant, but their taxonomy doesn't always align with
/// ours.
public struct BankCategoryStrategy: CategorizationStrategy {
    public let reason: CategorizationReason = .bankCategoryMapping
    let store: SQLiteStore

    public init(store: SQLiteStore) { self.store = store }

    public func categorize(_ input: CategorizationInput) async throws -> CategorizationSuggestion? {
        guard let raw = input.bankCategoryRaw, !raw.isEmpty else { return nil }
        let repo = BankCategoryMappingRepository(store: store)
        guard let mapping = try await repo.find(bankName: input.bankName, bankCategoryRaw: raw) else {
            return nil
        }
        return CategorizationSuggestion(
            categoryId: mapping.categoryId,
            confidence: 0.85,
            reason: .bankCategoryMapping,
            explanation: "Bank category: \(raw)"
        )
    }
}
