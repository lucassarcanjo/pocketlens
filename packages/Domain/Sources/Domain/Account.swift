import Foundation

/// A bank-relationship-level entity (one bank, one primary holder). Owns 1..N
/// `Card`s.
public struct Account: Hashable, Codable, Sendable, Identifiable {
    public var id: Int64?
    public var bankName: String
    public var holderName: String
    public var accountAlias: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        bankName: String,
        holderName: String,
        accountAlias: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.bankName = bankName
        self.holderName = holderName
        self.accountAlias = accountAlias
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
