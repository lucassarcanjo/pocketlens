import Foundation

/// A physical or virtual card that belongs to an `Account`. A multi-card
/// statement contains several `Card`s sharing one `accountId`.
public struct Card: Hashable, Codable, Sendable, Identifiable {
    public var id: Int64?
    public var accountId: Int64?
    public var last4: String
    public var holderName: String
    public var network: String?
    public var tier: String?
    public var nickname: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        accountId: Int64? = nil,
        last4: String,
        holderName: String,
        network: String? = nil,
        tier: String? = nil,
        nickname: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        precondition(last4.count == 4, "Card.last4 must be exactly 4 chars, got \"\(last4)\"")
        self.id = id
        self.accountId = accountId
        self.last4 = last4
        self.holderName = holderName
        self.network = network
        self.tier = tier
        self.nickname = nickname
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
