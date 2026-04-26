import Foundation

/// What kind of pattern a `CategorizationRule` carries. Drives matcher
/// dispatch in `RuleBasedCategorizer` (Phase 2).
public enum PatternType: String, Codable, CaseIterable, Sendable, Hashable {
    /// Substring match against `merchant_normalized`.
    case contains
    /// Full regex match against `merchant_normalized`.
    case regex
    /// Exact equality match against `merchant_normalized`.
    case exact
    /// Equality against `merchant_id`. `pattern` is unused; `merchantId` carries the value.
    case merchant
    /// Numeric range against `amount`. `pattern` encodes the range as
    /// `"min..max"` in minor units (BRL centavos).
    case amountRange = "amount_range"
}

/// Who created a rule. Drives priority slot:
/// - `.user` → slot 3 (user rule)
/// - `.system` → slot 5 (keyword/system rule)
/// - `.llm` → reserved for Phase 5 suggestions, treated as user-created when applied
public enum RuleSource: String, Codable, CaseIterable, Sendable, Hashable {
    case user
    case system
    case llm
}

/// A single pattern → category mapping. Persisted in `categorization_rules`.
public struct CategorizationRule: Hashable, Codable, Sendable, Identifiable {
    public var id: Int64?
    public var name: String
    public var pattern: String
    public var patternType: PatternType
    public var merchantId: Int64?
    public var categoryId: Int64
    /// Higher wins among rules of the same priority slot. Ties broken by id.
    public var priority: Int
    public var createdBy: RuleSource
    public var enabled: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        name: String,
        pattern: String,
        patternType: PatternType,
        merchantId: Int64? = nil,
        categoryId: Int64,
        priority: Int = 0,
        createdBy: RuleSource = .user,
        enabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.patternType = patternType
        self.merchantId = merchantId
        self.categoryId = categoryId
        self.priority = priority
        self.createdBy = createdBy
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
