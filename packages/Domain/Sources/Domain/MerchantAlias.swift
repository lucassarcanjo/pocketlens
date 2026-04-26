import Foundation

/// Maps a variant of a merchant description to a canonical merchant.
///
/// Example: `UBER *TRIP`, `UBER TRIP SP`, `Uber BR` all alias to the single
/// `Uber` merchant. The alias pattern is a casefolded fragment matched
/// against `transactions.merchant_normalized` — the engine's
/// `MerchantAliasMatcher` does substring containment.
public struct MerchantAlias: Hashable, Codable, Sendable, Identifiable {
    public enum Source: String, Codable, CaseIterable, Sendable, Hashable {
        case user
        case system
        case llm
    }

    public var id: Int64?
    public var merchantId: Int64
    public var alias: String
    public var source: Source
    public var createdAt: Date

    public init(
        id: Int64? = nil,
        merchantId: Int64,
        alias: String,
        source: Source = .user,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.merchantId = merchantId
        self.alias = alias
        self.source = source
        self.createdAt = createdAt
    }
}
