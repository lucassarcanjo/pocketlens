import Foundation

/// A merchant as seen on a statement.
///
/// `raw` is the first-seen description on a statement line (kept for forensic
/// reference). `normalized` is what dedup, search, and Phase-2 alias matching
/// use — it must be unique per row.
public struct Merchant: Hashable, Codable, Sendable, Identifiable {
    public var id: Int64?
    public var raw: String
    public var normalized: String
    public var defaultCategoryId: Int64?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        raw: String,
        normalized: String,
        defaultCategoryId: Int64? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.raw = raw
        self.normalized = normalized
        self.defaultCategoryId = defaultCategoryId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
