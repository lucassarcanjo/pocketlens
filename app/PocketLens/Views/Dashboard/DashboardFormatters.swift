import Foundation
import SwiftUI
import Domain

/// Shared formatting helpers for the dashboard's cards. Currency formatting
/// uses pt-BR for BRL and en-US for USD/EUR — matches the rest of the app.
enum DashboardFormatters {

    static func format(_ money: Money) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = money.currency.rawValue
        switch money.currency {
        case .BRL: f.locale = Locale(identifier: "pt_BR")
        case .USD: f.locale = Locale(identifier: "en_US")
        case .EUR: f.locale = Locale(identifier: "de_DE")
        case .GBP: f.locale = Locale(identifier: "en_GB")
        }
        return f.string(from: NSDecimalNumber(decimal: money.majorAmount)) ?? "—"
    }

    static func formatShort(_ money: Money) -> String {
        // Compact form for axis labels — drops cents on large values.
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = money.currency.rawValue
        f.maximumFractionDigits = 0
        switch money.currency {
        case .BRL: f.locale = Locale(identifier: "pt_BR")
        case .USD: f.locale = Locale(identifier: "en_US")
        case .EUR: f.locale = Locale(identifier: "de_DE")
        case .GBP: f.locale = Locale(identifier: "en_GB")
        }
                
        return f.string(from: NSDecimalNumber(decimal: money.majorAmount)) ?? "—"
    }

    static let date: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// "#RRGGBB" → SwiftUI Color. Mirrors the helper in `CategoriesView`.
    static func color(hex: String?) -> Color {
        guard let hex else { return .secondary }
        let trimmed = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard trimmed.count == 6, let value = UInt64(trimmed, radix: 16) else { return .secondary }
        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >> 8)  / 255.0
        let b = Double( value & 0x0000FF)        / 255.0
        return Color(red: r, green: g, blue: b)
    }
}
