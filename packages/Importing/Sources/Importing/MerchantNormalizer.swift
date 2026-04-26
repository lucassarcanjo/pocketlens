import Foundation

/// Normalizes raw merchant strings into the canonical form used for dedup,
/// merchant lookup, and (Phase 2) alias matching.
///
/// Steps, in order:
/// 1. Strip leading provider prefixes (`MP *`, `IFD*`, `PIX*`, `PYP*`, etc).
/// 2. Strip a trailing installment marker (`\b\d{1,2}/\d{1,2}\s*$`) — the LLM
///    may or may not have stripped it; we make the on-disk value authoritative.
/// 3. Casefold to lowercase.
/// 4. Collapse internal whitespace runs to a single space and trim ends.
public enum MerchantNormalizer {

    /// Run all normalization steps in order.
    public static func normalize(_ raw: String) -> String {
        var s = raw
        s = stripLeadingPrefix(s)
        s = stripTrailingInstallment(s)
        s = s.lowercased()
        s = collapseWhitespace(s)
        return s
    }

    // MARK: - Steps (exposed for tests)

    private static let leadingPrefixRegex = try! NSRegularExpression(
        pattern: #"^\s*(?:MP|IFD|PIX|PYP|PAG|PG)\s*\*\s*"#,
        options: [.caseInsensitive]
    )

    public static func stripLeadingPrefix(_ s: String) -> String {
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return leadingPrefixRegex.stringByReplacingMatches(
            in: s, options: [], range: range, withTemplate: ""
        )
    }

    private static let trailingInstallmentRegex = try! NSRegularExpression(
        pattern: #"\s+\d{1,2}/\d{1,2}\s*$"#,
        options: []
    )

    public static func stripTrailingInstallment(_ s: String) -> String {
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return trailingInstallmentRegex.stringByReplacingMatches(
            in: s, options: [], range: range, withTemplate: ""
        )
    }

    private static let whitespaceRegex = try! NSRegularExpression(
        pattern: #"\s+"#,
        options: []
    )

    public static func collapseWhitespace(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        return whitespaceRegex.stringByReplacingMatches(
            in: trimmed, options: [], range: range, withTemplate: " "
        )
    }
}
