import Foundation
import Domain
import Persistence

/// Slots 3 and 5 — rule-based categorization.
///
/// Same matcher logic, different rule populations:
/// - Slot 3 (`source: .user`): rules the user created — confidence 0.90
/// - Slot 5 (`source: .system`): keyword rules seeded by us — confidence 0.80
///
/// Rules are walked in priority-desc order; the first that matches wins.
/// Pattern semantics by `PatternType`:
/// - `.contains` — case-insensitive substring against `merchantNormalized`
/// - `.regex`    — case-insensitive regex against `merchantNormalized`
/// - `.exact`    — case-insensitive equality against `merchantNormalized`
/// - `.merchant` — equality against `merchantId`
/// - `.amountRange` — `pattern` is `"min..max"` in minor currency units;
///   either side may be `*` for unbounded
public struct RuleStrategy: CategorizationStrategy {
    public let reason: CategorizationReason
    let store: SQLiteStore
    let source: RuleSource
    let baseConfidence: Double

    public init(
        store: SQLiteStore,
        source: RuleSource,
        reason: CategorizationReason,
        baseConfidence: Double
    ) {
        self.store = store
        self.source = source
        self.reason = reason
        self.baseConfidence = baseConfidence
    }

    public func categorize(_ input: CategorizationInput) async throws -> CategorizationSuggestion? {
        let repo = CategorizationRuleRepository(store: store)
        let rules = try await repo.enabled(by: source)

        for rule in rules {
            guard Self.matches(rule: rule, input: input) else { continue }
            return CategorizationSuggestion(
                categoryId: rule.categoryId,
                confidence: baseConfidence,
                reason: reason,
                explanation: explanation(for: rule)
            )
        }
        return nil
    }

    private func explanation(for rule: CategorizationRule) -> String {
        switch reason {
        case .userRule:
            return "User rule: \"\(rule.name)\""
        case .keywordRule:
            return "Keyword rule: \"\(rule.name)\""
        default:
            return "Rule matched: \"\(rule.name)\""
        }
    }

    // MARK: - Matchers

    static func matches(rule: CategorizationRule, input: CategorizationInput) -> Bool {
        switch rule.patternType {
        case .contains:
            return input.merchantNormalized.lowercased().contains(rule.pattern.lowercased())
        case .exact:
            return input.merchantNormalized.lowercased() == rule.pattern.lowercased()
        case .regex:
            return regexMatches(pattern: rule.pattern, input: input.merchantNormalized)
        case .merchant:
            guard let mid = rule.merchantId, let inputMid = input.merchantId else { return false }
            return mid == inputMid
        case .amountRange:
            return amountInRange(pattern: rule.pattern, amount: input.amount.minorUnits)
        }
    }

    private static func regexMatches(pattern: String, input: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            // A malformed pattern doesn't crash the engine — it just can't match.
            return false
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.firstMatch(in: input, options: [], range: range) != nil
    }

    private static func amountInRange(pattern: String, amount: Int) -> Bool {
        let parts = pattern.split(separator: "..", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let lo = parts[0].trimmingCharacters(in: .whitespaces)
        let hi = parts[1].trimmingCharacters(in: .whitespaces)

        let lower: Int = (lo == "*" || lo.isEmpty) ? Int.min : (Int(lo) ?? Int.min)
        let upper: Int = (hi == "*" || hi.isEmpty) ? Int.max : (Int(hi) ?? Int.max)
        return amount >= lower && amount <= upper
    }
}
