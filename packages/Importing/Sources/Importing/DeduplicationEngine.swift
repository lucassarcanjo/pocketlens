import Foundation
import Domain

/// In-memory dedup helper. The persisting layer enforces uniqueness via DB
/// constraints; this type lets the pipeline collapse same-batch duplicates
/// (rare, but possible if the LLM emits two rows for one line) before they
/// hit SQLite — and surface that as a warning.
public struct DeduplicationEngine: Sendable {

    public init() {}

    public struct Result: Sendable {
        public var unique: [PendingTransaction]
        public var collapsed: Int

        public init(unique: [PendingTransaction], collapsed: Int) {
            self.unique = unique
            self.collapsed = collapsed
        }
    }

    /// Collapse rows that share a fingerprint. Order-stable — first occurrence
    /// wins. Returns the surviving rows + a count of how many were dropped.
    public func collapse(_ pending: [PendingTransaction]) -> Result {
        var seen = Set<String>()
        var unique: [PendingTransaction] = []
        unique.reserveCapacity(pending.count)
        var collapsed = 0
        for row in pending {
            if seen.insert(row.fingerprint).inserted {
                unique.append(row)
            } else {
                collapsed += 1
            }
        }
        return Result(unique: unique, collapsed: collapsed)
    }
}
