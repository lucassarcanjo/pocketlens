import Foundation
import Domain
import Persistence

/// Slot 2 — merchant alias collapses the description to a known merchant
/// that has a `default_category_id`.
///
/// Match semantics: the alias is a casefolded fragment; we test substring
/// containment against `merchantNormalized`. Aliases are scanned newest-first
/// so user-added aliases win over system-seeded ones if both match. If the
/// matched merchant has no `defaultCategoryId`, we fall through.
///
/// Confidence is fixed at 0.95.
public struct MerchantAliasStrategy: CategorizationStrategy {
    public let reason: CategorizationReason = .merchantAlias
    let store: SQLiteStore

    public init(store: SQLiteStore) { self.store = store }

    public func categorize(_ input: CategorizationInput) async throws -> CategorizationSuggestion? {
        let aliasRepo = MerchantAliasRepository(store: store)
        let merchantRepo = MerchantRepository(store: store)

        let needle = input.merchantNormalized.lowercased()
        let aliases = try await aliasRepo.all()

        // Longest alias first reduces false positives — "uber eats" should
        // beat the standalone "uber" alias when both are present.
        for alias in aliases.sorted(by: { $0.alias.count > $1.alias.count }) {
            let pattern = alias.alias.lowercased()
            guard !pattern.isEmpty, needle.contains(pattern) else { continue }

            let merchant = try await merchantRepo.all().first { $0.id == alias.merchantId }
            guard let categoryId = merchant?.defaultCategoryId else { continue }

            return CategorizationSuggestion(
                categoryId: categoryId,
                confidence: 0.95,
                reason: .merchantAlias,
                explanation: "Matched merchant alias: \(alias.alias)"
            )
        }
        return nil
    }
}
