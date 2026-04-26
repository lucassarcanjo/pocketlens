import Foundation

/// One row recorded every time a user overrides a category (or, in later
/// phases, edits the merchant / amount / date) on a transaction. Drives the
/// top-priority slot in the categorization chain: a correction on transaction
/// X teaches future imports of fingerprint-equal transactions to land on the
/// same category automatically.
public struct UserCorrection: Hashable, Codable, Sendable, Identifiable {
    public enum CorrectionType: String, Codable, CaseIterable, Sendable, Hashable {
        case category
        case merchant
        case amount
        case date
    }

    public var id: Int64?
    public var transactionId: Int64
    public var oldCategoryId: Int64?
    public var newCategoryId: Int64
    public var correctionType: CorrectionType
    public var note: String?
    public var createdAt: Date

    public init(
        id: Int64? = nil,
        transactionId: Int64,
        oldCategoryId: Int64?,
        newCategoryId: Int64,
        correctionType: CorrectionType = .category,
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.transactionId = transactionId
        self.oldCategoryId = oldCategoryId
        self.newCategoryId = newCategoryId
        self.correctionType = correctionType
        self.note = note
        self.createdAt = createdAt
    }
}
