import Foundation

/// Pre-LLM redaction. Strips data we don't want leaving the device while
/// preserving everything the model needs to extract transactions correctly
/// (merchant, city, last-4, amounts, dates).
///
/// Pluggable rules so contributors can add patterns without changing the
/// type itself.
public struct Redactor: Sendable {
    public struct Rule: Sendable {
        public let name: String
        public let regex: NSRegularExpression
        public let replacement: String

        public init(name: String, pattern: String, replacement: String, options: NSRegularExpression.Options = []) {
            self.name = name
            self.regex = try! NSRegularExpression(pattern: pattern, options: options)
            self.replacement = replacement
        }
    }

    public let rules: [Rule]

    public init(rules: [Rule] = Redactor.defaultRules) {
        self.rules = rules
    }

    public func redact(_ input: String) -> String {
        var current = input
        for rule in rules {
            let range = NSRange(current.startIndex..<current.endIndex, in: current)
            current = rule.regex.stringByReplacingMatches(
                in: current,
                options: [],
                range: range,
                withTemplate: rule.replacement
            )
        }
        return current
    }
}

extension Redactor {
    /// Default rule set for Brazilian credit-card statements.
    ///
    /// Order matters: card numbers first (so the last-4 is preserved), then
    /// CPF/CNPJ, then street addresses (which are matched on Brazilian-style
    /// `Rua/Av./Avenida` prefixes — the city + state on the next line is
    /// intentionally preserved).
    public static let defaultRules: [Rule] = [
        // Full Visa/MC card number with separators (XXXX XXXX XXXX 1234 or
        // XXXX.XXXX.XXXX.1234) → mask leading triplets, keep the last 4.
        Rule(
            name: "card-number-spaced",
            pattern: #"\b\d{4}[ .]\d{4}[ .]\d{4}[ .](\d{4})\b"#,
            replacement: "XXXX.XXXX.XXXX.$1"
        ),
        // Bare 16-digit number → mask first 12, keep last 4.
        Rule(
            name: "card-number-contiguous",
            pattern: #"\b\d{12}(\d{4})\b"#,
            replacement: "XXXXXXXXXXXX$1"
        ),
        // CPF: 123.456.789-00
        Rule(
            name: "cpf",
            pattern: #"\b\d{3}\.\d{3}\.\d{3}-\d{2}\b"#,
            replacement: "[CPF]"
        ),
        // CNPJ: 12.345.678/0001-90
        Rule(
            name: "cnpj",
            pattern: #"\b\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}\b"#,
            replacement: "[CNPJ]"
        ),
        // BR street-address line: starts with Rua / Av / Avenida / Alameda /
        // Praça / Travessa / Estrada / Rod. / R. / Av., followed by a name +
        // a number. Greedy up to end-of-line. Case-insensitive.
        Rule(
            name: "br-street-address",
            pattern: #"(?i)\b(?:rua|r\.|avenida|av\.|alameda|al\.|praça|travessa|tv\.|estrada|est\.|rodovia|rod\.)\s+[^\n,]{1,80}?,?\s*\d+[A-Za-z]?\b"#,
            replacement: "[ADDRESS]"
        ),
    ]
}
