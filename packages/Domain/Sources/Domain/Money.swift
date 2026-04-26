import Foundation

/// A currency-typed monetary amount.
///
/// Stored internally as a minor-unit `Int` (centavos / cents) so equality and
/// hashing are cheap and exact. Construction from `Decimal` rounds half-to-even
/// at the currency's fraction-digit boundary.
public struct Money: Hashable, Sendable, Codable {
    /// Amount in the minor unit (e.g. centavos for BRL). Signed: negative
    /// values represent refunds / credits.
    public let minorUnits: Int
    public let currency: Currency

    public init(minorUnits: Int, currency: Currency) {
        self.minorUnits = minorUnits
        self.currency = currency
    }

    public init(major: Decimal, currency: Currency) {
        let multiplier = Decimal(currency.minorUnitsPerMajor)
        var scaled = major * multiplier
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .bankers)
        // NSDecimalNumber bridges to NSNumber → Int. Decimal values that
        // overflow Int will trap; that's correct behaviour for an unbounded
        // Decimal hitting our bounded storage.
        self.minorUnits = (rounded as NSDecimalNumber).intValue
        self.currency = currency
    }

    public var majorAmount: Decimal {
        Decimal(minorUnits) / Decimal(currency.minorUnitsPerMajor)
    }

    public static func zero(_ currency: Currency) -> Money {
        Money(minorUnits: 0, currency: currency)
    }

    public var isZero: Bool { minorUnits == 0 }
    public var isNegative: Bool { minorUnits < 0 }

    public func negated() -> Money {
        Money(minorUnits: -minorUnits, currency: currency)
    }
}

// MARK: - Arithmetic (currency-safe)

extension Money {
    public enum ArithmeticError: Error, Equatable {
        case currencyMismatch(lhs: Currency, rhs: Currency)
    }

    public static func + (lhs: Money, rhs: Money) throws -> Money {
        guard lhs.currency == rhs.currency else {
            throw ArithmeticError.currencyMismatch(lhs: lhs.currency, rhs: rhs.currency)
        }
        return Money(minorUnits: lhs.minorUnits + rhs.minorUnits, currency: lhs.currency)
    }

    public static func - (lhs: Money, rhs: Money) throws -> Money {
        guard lhs.currency == rhs.currency else {
            throw ArithmeticError.currencyMismatch(lhs: lhs.currency, rhs: rhs.currency)
        }
        return Money(minorUnits: lhs.minorUnits - rhs.minorUnits, currency: lhs.currency)
    }

    /// Sum a sequence of `Money` values that share a currency. Returns
    /// `Money.zero(fallback)` if the sequence is empty.
    public static func sum<S: Sequence>(_ values: S, fallback: Currency) throws -> Money where S.Element == Money {
        var iter = values.makeIterator()
        guard let first = iter.next() else {
            return Money.zero(fallback)
        }
        var total = first
        while let next = iter.next() {
            total = try total + next
        }
        return total
    }
}

// MARK: - Comparable (within a single currency)

extension Money: Comparable {
    /// Strict less-than comparison. **Asserts on currency mismatch** because
    /// comparing money in different currencies has no defined meaning.
    public static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(
            lhs.currency == rhs.currency,
            "Money comparison across currencies is undefined: \(lhs.currency) vs \(rhs.currency)"
        )
        return lhs.minorUnits < rhs.minorUnits
    }
}

// MARK: - Locale-safe formatting

extension Money {
    /// Format using the user's locale by default. Pass `Locale(identifier: "pt_BR")`
    /// for statement-style display regardless of system locale.
    public func formatted(locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.rawValue
        formatter.locale = locale
        formatter.maximumFractionDigits = currency.fractionDigits
        formatter.minimumFractionDigits = currency.fractionDigits
        return formatter.string(from: majorAmount as NSDecimalNumber) ?? "\(majorAmount) \(currency.rawValue)"
    }
}
