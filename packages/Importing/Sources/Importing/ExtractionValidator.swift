import Foundation
import Domain
import LLM

/// Cross-checks an `ExtractedStatement` against the printed totals on the
/// statement and a few sanity rules. Output drives `validation_status` on
/// `ImportBatch` plus a list of human-readable warnings the UI surfaces.
public struct ExtractionValidator: Sendable {

    /// Money tolerance for "matches printed total". The plan locks this at
    /// ±R$0.01 (one centavo). Floating-rounding from per-installment fractions
    /// shouldn't trigger a warning.
    public static let toleranceMinorUnits = 1

    /// Confidence floor — warn if more than this fraction of transactions
    /// fall below `confidenceLowThreshold`.
    public static let confidenceLowFraction = 0.02
    public static let confidenceLowThreshold = 0.7

    public init() {}

    public func validate(_ statement: ExtractedStatement) -> Report {
        var warnings: [String] = []
        var failed = false

        // Per-card subtotals.
        for card in statement.cards {
            let cardTransactions = statement.transactions.filter { $0.cardLast4 == card.last4 }
            let extractedSum = cardTransactions.map { $0.amount }.reduce(Decimal(0), +)
            let printed = card.subtotal
            if !withinTolerance(extractedSum, printed) {
                warnings.append(
                    "Card \(card.last4): extracted sum \(format(extractedSum)) "
                    + "doesn't match printed subtotal \(format(printed)) "
                    + "(diff \(format(extractedSum - printed)))"
                )
                failed = true
            }
        }

        // Grand total.
        let grandSum = statement.transactions.map { $0.amount }.reduce(Decimal(0), +)
        let printedGrand = statement.statement.totals.currentChargesTotal
        if !withinTolerance(grandSum, printedGrand) {
            warnings.append(
                "Grand total: extracted sum \(format(grandSum)) "
                + "doesn't match printed total \(format(printedGrand)) "
                + "(diff \(format(grandSum - printedGrand)))"
            )
            failed = true
        }

        // Cards listed but no transactions, or transactions referencing an
        // unknown card.
        let knownLast4 = Set(statement.cards.map { $0.last4 })
        let txLast4 = Set(statement.transactions.map { $0.cardLast4 })
        let orphanCards = txLast4.subtracting(knownLast4)
        if !orphanCards.isEmpty {
            warnings.append(
                "Transactions reference unknown card(s): \(orphanCards.sorted().joined(separator: ", "))"
            )
            failed = true
        }
        let emptyCards = knownLast4.subtracting(txLast4)
        if !emptyCards.isEmpty {
            warnings.append(
                "Card(s) listed but no transactions extracted: \(emptyCards.sorted().joined(separator: ", "))"
            )
        }

        // Confidence floor.
        let total = statement.transactions.count
        if total > 0 {
            let lowConf = statement.transactions.filter { $0.confidence < Self.confidenceLowThreshold }.count
            let frac = Double(lowConf) / Double(total)
            if frac > Self.confidenceLowFraction {
                warnings.append(
                    "Low-confidence rows: \(lowConf) of \(total) "
                    + "(\(Int(frac * 100))% > \(Int(Self.confidenceLowFraction * 100))% threshold)"
                )
            }
        }

        // Pass through any warnings the model itself emitted.
        warnings.append(contentsOf: statement.warnings)

        let status: ValidationStatus
        if failed {
            status = .failed
        } else if !warnings.isEmpty {
            status = .warning
        } else {
            status = .ok
        }
        return Report(status: status, warnings: warnings)
    }

    public struct Report: Sendable, Hashable {
        public let status: ValidationStatus
        public let warnings: [String]

        public init(status: ValidationStatus, warnings: [String]) {
            self.status = status
            self.warnings = warnings
        }
    }

    // MARK: - Internals

    private func withinTolerance(_ a: Decimal, _ b: Decimal) -> Bool {
        // Convert to BRL minor units (centavos) for an integer comparison
        // that's immune to Decimal-vs-Double drift.
        let aMinor = (a * 100 as NSDecimalNumber).intValue
        let bMinor = (b * 100 as NSDecimalNumber).intValue
        return abs(aMinor - bMinor) <= Self.toleranceMinorUnits
    }

    private func format(_ d: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: d as NSDecimalNumber) ?? "\(d)"
    }
}
