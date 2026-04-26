import Foundation

/// ISO 4217 currencies PocketLens currently understands.
///
/// Extensible — new codes can be added as fixtures arrive. The set is closed
/// at compile time so the import pipeline can fail loudly on unknown codes
/// instead of silently storing junk.
public enum Currency: String, Codable, CaseIterable, Sendable, Hashable {
    case BRL
    case USD
    case EUR
    case GBP

    /// Number of fractional digits (centavos / cents). All four supported
    /// currencies use 2; kept as a property for future-proofing.
    public var fractionDigits: Int { 2 }

    /// 10^fractionDigits — the multiplier between major and minor units.
    public var minorUnitsPerMajor: Int {
        var n = 1
        for _ in 0..<fractionDigits { n *= 10 }
        return n
    }
}
