import Foundation

/// Where a category came from. Mirrors the priority chain documented in
/// `docs/categorization.md` §"Priority Order" and `.claude-plans/03-phase-2-memory.md`.
///
/// The raw value is stable on disk — it lands in
/// `transactions.categorization_reason` (alongside the human-readable phrase
/// the engine emits). UI uses the enum to colour badges; persistence uses it
/// only as documentation. Treat additions as schema-touching.
public enum CategorizationReason: String, Codable, CaseIterable, Sendable, Hashable {
    /// Slot 1 — exact prior user correction on a matching fingerprint.
    case userCorrection = "user_correction"
    /// Slot 2 — merchant alias collapsed the description to a known merchant.
    case merchantAlias = "merchant_alias"
    /// Slot 3 — a user-created rule matched.
    case userRule = "user_rule"
    /// Slot 4 — issuer's own category label mapped to a PocketLens category.
    case bankCategoryMapping = "bank_category_mapping"
    /// Slot 5 — system-seeded keyword rule matched.
    case keywordRule = "keyword_rule"
    /// Slot 6 — similar to a previously-categorized transaction.
    case similarity
    /// Slot 7 — Phase-5 LLM suggestion (stubbed in Phase 2).
    case llmSuggestion = "llm_suggestion"
    /// Slot 8 — nothing matched.
    case uncategorized
}
