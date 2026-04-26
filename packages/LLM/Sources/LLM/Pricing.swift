import Foundation

/// Static price table for Anthropic models. Prices in USD per 1M tokens.
/// Source: https://www.anthropic.com/pricing  (as of plan write-up; bump
/// these when Anthropic changes pricing).
///
/// Cache reads are billed at 10% of the input rate by Anthropic.
public enum Pricing {

    public struct Rates: Sendable {
        public let inputPerMillion: Double
        public let outputPerMillion: Double
        public let cacheReadPerMillion: Double

        public init(inputPerMillion: Double, outputPerMillion: Double, cacheReadPerMillion: Double? = nil) {
            self.inputPerMillion = inputPerMillion
            self.outputPerMillion = outputPerMillion
            self.cacheReadPerMillion = cacheReadPerMillion ?? (inputPerMillion * 0.1)
        }
    }

    /// USD per 1M tokens. Add new models here when bumping the picker.
    public static let table: [String: Rates] = [
        "claude-sonnet-4-6":          Rates(inputPerMillion: 3.0,  outputPerMillion: 15.0),
        "claude-opus-4-7":            Rates(inputPerMillion: 15.0, outputPerMillion: 75.0),
        "claude-haiku-4-5-20251001":  Rates(inputPerMillion: 1.0,  outputPerMillion: 5.0),
    ]

    public static func costUSD(
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int = 0
    ) -> Double {
        guard let r = table[model] else { return 0 }
        let mil = 1_000_000.0
        let inputCost      = Double(inputTokens)      / mil * r.inputPerMillion
        let outputCost     = Double(outputTokens)     / mil * r.outputPerMillion
        let cacheReadCost  = Double(cacheReadTokens)  / mil * r.cacheReadPerMillion
        return inputCost + outputCost + cacheReadCost
    }
}
