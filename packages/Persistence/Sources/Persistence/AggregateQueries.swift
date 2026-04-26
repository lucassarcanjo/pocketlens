import Foundation
import GRDB
import Domain

/// Raw-SQL aggregations for the dashboard.
///
/// All grouping happens in SQLite — the view model never folds rows in Swift.
/// Each row is bucketed by the close date of the statement it appeared on
/// (`import_batches.statement_period_end`), falling back to `posted_date` when
/// statement metadata is missing. This makes installments land in the month
/// they're being charged, not the original purchase month.
/// Date arguments are half-open: `bucket >= start AND bucket < endExclusive`.
///
/// "Spending" excludes `payment` (the user paying off the card) and includes
/// `purchase`, `refund` (negative, offsets), `fee`, `iof`, and `adjustment`.
public struct AggregateQueries: Sendable {

    let dbQueue: DatabaseQueue

    public init(store: SQLiteStore) { self.dbQueue = store.queue }

    /// SQL fragment listing the transaction types that count as spending.
    private static let spendingTypesSQL =
        "('purchase','refund','fee','iof','adjustment')"

    /// Bucketing date expression: statement close date when available, else
    /// the row's own `posted_date`. Requires aliases `t` (transactions) and
    /// `b` (import_batches).
    private static let bucketDateSQL =
        "COALESCE(b.statement_period_end, t.posted_date)"

    // MARK: - DTOs

    public struct CurrencyTotal: Sendable, Hashable {
        public let currency: Currency
        public let total: Money
    }

    public struct CategoryTotal: Sendable, Hashable {
        /// `nil` for the uncategorized bucket.
        public let categoryId: Int64?
        /// `nil` for the uncategorized bucket.
        public let categoryName: String?
        public let categoryColor: String?
        public let total: Money
        public let transactionCount: Int
    }

    public struct MerchantTotal: Sendable, Hashable {
        public let merchantNormalized: String
        public let total: Money
        public let transactionCount: Int
    }

    public struct LargestTransaction: Sendable, Hashable {
        public let transactionId: Int64
        public let postedDate: Date
        public let merchantNormalized: String
        public let amount: Money
        public let cardLast4: String
    }

    public struct CardTotal: Sendable, Hashable {
        public let cardId: Int64
        public let cardLast4: String
        public let cardHolderName: String
        public let cardNickname: String?
        public let total: Money
    }

    // MARK: - Queries

    /// One row per currency seen in the period.
    public func totalsByCurrency(start: Date, endExclusive: Date) async throws -> [CurrencyTotal] {
        let s = DateFmt.date.string(from: start)
        let e = DateFmt.date.string(from: endExclusive)
        return try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.currency AS currency, SUM(t.amount) AS total_minor
                FROM transactions t
                JOIN import_batches b ON b.id = t.import_batch_id
                WHERE \(Self.bucketDateSQL) >= ? AND \(Self.bucketDateSQL) < ?
                  AND t.transaction_type IN \(Self.spendingTypesSQL)
                GROUP BY t.currency
                ORDER BY t.currency
                """, arguments: [s, e])
            return rows.compactMap { row -> CurrencyTotal? in
                let code: String = row["currency"]
                guard let cur = Currency(rawValue: code) else { return nil }
                let minor: Int = row["total_minor"]
                return CurrencyTotal(currency: cur, total: Money(minorUnits: minor, currency: cur))
            }
        }
    }

    /// Spending grouped by category in a single currency. Uncategorized rows
    /// collapse to a single bucket with `categoryId == nil`.
    public func spendingByCategory(
        start: Date,
        endExclusive: Date,
        currency: Currency
    ) async throws -> [CategoryTotal] {
        let s = DateFmt.date.string(from: start)
        let e = DateFmt.date.string(from: endExclusive)
        return try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.category_id        AS category_id,
                       c.name               AS category_name,
                       c.color              AS category_color,
                       SUM(t.amount)        AS total_minor,
                       COUNT(*)             AS tx_count
                FROM transactions t
                JOIN import_batches b ON b.id = t.import_batch_id
                LEFT JOIN categories c ON c.id = t.category_id
                WHERE \(Self.bucketDateSQL) >= ? AND \(Self.bucketDateSQL) < ?
                  AND t.currency = ?
                  AND t.transaction_type IN \(Self.spendingTypesSQL)
                GROUP BY t.category_id
                ORDER BY total_minor DESC
                """, arguments: [s, e, currency.rawValue])
            return rows.map { row in
                let minor: Int = row["total_minor"]
                return CategoryTotal(
                    categoryId: row["category_id"],
                    categoryName: row["category_name"],
                    categoryColor: row["category_color"],
                    total: Money(minorUnits: minor, currency: currency),
                    transactionCount: row["tx_count"]
                )
            }
        }
    }

    /// Top merchants by total spend in a single currency. Grouped by
    /// `merchant_normalized` so the result is stable even if the merchant
    /// row was deleted.
    public func topMerchants(
        start: Date,
        endExclusive: Date,
        currency: Currency,
        limit: Int
    ) async throws -> [MerchantTotal] {
        let s = DateFmt.date.string(from: start)
        let e = DateFmt.date.string(from: endExclusive)
        return try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.merchant_normalized AS merchant_normalized,
                       SUM(t.amount)         AS total_minor,
                       COUNT(*)              AS tx_count
                FROM transactions t
                JOIN import_batches b ON b.id = t.import_batch_id
                WHERE \(Self.bucketDateSQL) >= ? AND \(Self.bucketDateSQL) < ?
                  AND t.currency = ?
                  AND t.transaction_type IN \(Self.spendingTypesSQL)
                GROUP BY t.merchant_normalized
                ORDER BY total_minor DESC
                LIMIT ?
                """, arguments: [s, e, currency.rawValue, limit])
            return rows.map { row in
                let minor: Int = row["total_minor"]
                return MerchantTotal(
                    merchantNormalized: row["merchant_normalized"],
                    total: Money(minorUnits: minor, currency: currency),
                    transactionCount: row["tx_count"]
                )
            }
        }
    }

    /// Top-N largest single transactions. Refunds (negative amounts) are
    /// excluded — "largest" here means biggest spend, not biggest absolute.
    public func largestTransactions(
        start: Date,
        endExclusive: Date,
        currency: Currency,
        limit: Int
    ) async throws -> [LargestTransaction] {
        let s = DateFmt.date.string(from: start)
        let e = DateFmt.date.string(from: endExclusive)
        return try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.id                  AS id,
                       t.posted_date         AS posted_date,
                       t.merchant_normalized AS merchant_normalized,
                       t.amount              AS amount_minor,
                       cd.last4              AS card_last4
                FROM transactions t
                JOIN import_batches b ON b.id = t.import_batch_id
                JOIN cards cd ON cd.id = t.card_id
                WHERE \(Self.bucketDateSQL) >= ? AND \(Self.bucketDateSQL) < ?
                  AND t.currency = ?
                  AND t.amount > 0
                  AND t.transaction_type IN ('purchase','fee','iof','adjustment')
                ORDER BY t.amount DESC
                LIMIT ?
                """, arguments: [s, e, currency.rawValue, limit])
            return rows.compactMap { row -> LargestTransaction? in
                let dateStr: String = row["posted_date"]
                guard let date = DateFmt.date.date(from: dateStr) else { return nil }
                let minor: Int = row["amount_minor"]
                return LargestTransaction(
                    transactionId: row["id"],
                    postedDate: date,
                    merchantNormalized: row["merchant_normalized"],
                    amount: Money(minorUnits: minor, currency: currency),
                    cardLast4: row["card_last4"]
                )
            }
        }
    }

    /// Count of spending-type transactions in the period without a category.
    public func uncategorizedCount(start: Date, endExclusive: Date) async throws -> Int {
        let s = DateFmt.date.string(from: start)
        let e = DateFmt.date.string(from: endExclusive)
        return try await dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM transactions t
                JOIN import_batches b ON b.id = t.import_batch_id
                WHERE \(Self.bucketDateSQL) >= ? AND \(Self.bucketDateSQL) < ?
                  AND t.category_id IS NULL
                  AND t.transaction_type IN \(Self.spendingTypesSQL)
                """, arguments: [s, e]) ?? 0
        }
    }

    /// Count of categorized transactions whose categorization confidence sits
    /// in the "needs review" band (`lowerBound ≤ confidence < upperBound`).
    /// Defaults match Phase 2's ReviewView (0.50..<0.80).
    public func needsReviewCount(
        start: Date,
        endExclusive: Date,
        lowerBound: Double = 0.50,
        upperBound: Double = 0.80
    ) async throws -> Int {
        let s = DateFmt.date.string(from: start)
        let e = DateFmt.date.string(from: endExclusive)
        return try await dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM transactions t
                JOIN import_batches b ON b.id = t.import_batch_id
                WHERE \(Self.bucketDateSQL) >= ? AND \(Self.bucketDateSQL) < ?
                  AND t.category_id IS NOT NULL
                  AND t.confidence >= ? AND t.confidence < ?
                  AND t.transaction_type IN \(Self.spendingTypesSQL)
                """, arguments: [s, e, lowerBound, upperBound]) ?? 0
        }
    }

    /// Per-card spending totals in a single currency, highest-spending first.
    /// "Person" is deferred — Phase 3 ships card-only totals (see plan).
    public func totalsByCard(
        start: Date,
        endExclusive: Date,
        currency: Currency
    ) async throws -> [CardTotal] {
        let s = DateFmt.date.string(from: start)
        let e = DateFmt.date.string(from: endExclusive)
        return try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT cd.id           AS card_id,
                       cd.last4        AS card_last4,
                       cd.holder_name  AS card_holder,
                       cd.nickname     AS card_nickname,
                       SUM(t.amount)   AS total_minor
                FROM transactions t
                JOIN import_batches b ON b.id = t.import_batch_id
                JOIN cards cd ON cd.id = t.card_id
                WHERE \(Self.bucketDateSQL) >= ? AND \(Self.bucketDateSQL) < ?
                  AND t.currency = ?
                  AND t.transaction_type IN \(Self.spendingTypesSQL)
                GROUP BY cd.id
                ORDER BY total_minor DESC
                """, arguments: [s, e, currency.rawValue])
            return rows.map { row in
                let minor: Int = row["total_minor"]
                return CardTotal(
                    cardId: row["card_id"],
                    cardLast4: row["card_last4"],
                    cardHolderName: row["card_holder"],
                    cardNickname: row["card_nickname"],
                    total: Money(minorUnits: minor, currency: currency)
                )
            }
        }
    }
}
