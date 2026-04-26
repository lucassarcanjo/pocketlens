import Foundation
import SwiftUI
import Domain
import Persistence

/// Selectable date-range presets for the dashboard. `custom` reads
/// `customStart`/`customEnd` from the view model.
enum DashboardDateRangePreset: String, CaseIterable, Identifiable {
    case thisMonth, lastMonth, last3Months, custom
    var id: String { rawValue }

    var label: String {
        switch self {
        case .thisMonth:   return "This month"
        case .lastMonth:   return "Last month"
        case .last3Months: return "Last 3 months"
        case .custom:      return "Custom…"
        }
    }
}

@MainActor
final class DashboardViewModel: ObservableObject {

    // MARK: - Persisted preferences

    @AppStorage("pocketlens.dashboard.preset")
    private var presetRaw: String = DashboardDateRangePreset.thisMonth.rawValue

    @AppStorage("pocketlens.dashboard.customStartISO")
    private var customStartISO: String = ""

    @AppStorage("pocketlens.dashboard.customEndISO")
    private var customEndISO: String = ""

    @AppStorage("pocketlens.dashboard.currency")
    private var currencyRaw: String = Currency.BRL.rawValue

    // MARK: - UI state

    @Published var preset: DashboardDateRangePreset = .thisMonth {
        didSet { presetRaw = preset.rawValue }
    }
    @Published var customStart: Date = Date() {
        didSet { customStartISO = Self.iso.string(from: customStart) }
    }
    @Published var customEnd: Date = Date() {
        didSet { customEndISO = Self.iso.string(from: customEnd) }
    }
    @Published var selectedCurrency: Currency = .BRL {
        didSet { currencyRaw = selectedCurrency.rawValue }
    }

    // MARK: - Loaded snapshots

    @Published var totalsByCurrency: [AggregateQueries.CurrencyTotal] = []
    @Published var spendingByCategory: [AggregateQueries.CategoryTotal] = []
    @Published var topMerchants: [AggregateQueries.MerchantTotal] = []
    @Published var largestTransactions: [AggregateQueries.LargestTransaction] = []
    @Published var totalsByCard: [AggregateQueries.CardTotal] = []
    @Published var uncategorizedCount: Int = 0
    @Published var needsReviewCount: Int = 0

    @Published var loadError: String?
    @Published var hasLoaded = false

    // MARK: - Init

    init() {
        // Restore from AppStorage on launch.
        if let restored = DashboardDateRangePreset(rawValue: presetRaw) {
            preset = restored
        }
        if let s = Self.iso.date(from: customStartISO) { customStart = s }
        if let e = Self.iso.date(from: customEndISO)   { customEnd = e }
        if let c = Currency(rawValue: currencyRaw)     { selectedCurrency = c }
    }

    // MARK: - Period

    /// Half-open interval for the current preset, evaluated against `now` in
    /// UTC so it lines up with the UTC `posted_date` strings on disk.
    func interval(now: Date = Date()) -> (start: Date, end: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!

        switch preset {
        case .thisMonth:
            let monthStart = cal.dateInterval(of: .month, for: now)?.start ?? now
            let nextMonth = cal.date(byAdding: .month, value: 1, to: monthStart) ?? now
            return (monthStart, nextMonth)
        case .lastMonth:
            let monthStart = cal.dateInterval(of: .month, for: now)?.start ?? now
            let lastStart = cal.date(byAdding: .month, value: -1, to: monthStart) ?? now
            return (lastStart, monthStart)
        case .last3Months:
            let monthStart = cal.dateInterval(of: .month, for: now)?.start ?? now
            let nextMonth = cal.date(byAdding: .month, value: 1, to: monthStart) ?? now
            let threeBack = cal.date(byAdding: .month, value: -2, to: monthStart) ?? now
            return (threeBack, nextMonth)
        case .custom:
            // End is exclusive — bump custom end forward by one day so the
            // user-picked end date is *included* in the period.
            let endExclusive = cal.date(byAdding: .day, value: 1, to: customEnd) ?? customEnd
            return (customStart, endExclusive)
        }
    }

    // MARK: - Reload

    func reload(store: SQLiteStore?) async {
        guard let store else {
            resetSnapshots()
            hasLoaded = true
            return
        }
        let q = AggregateQueries(store: store)
        let (start, end) = interval()
        do {
            async let totalsTask     = q.totalsByCurrency(start: start, endExclusive: end)
            async let uncatTask      = q.uncategorizedCount(start: start, endExclusive: end)
            async let needsTask      = q.needsReviewCount(start: start, endExclusive: end)

            let totals = try await totalsTask
            self.totalsByCurrency = totals

            // Default the selected currency to the largest-total currency in
            // the period if the persisted choice has no data here.
            if !totals.contains(where: { $0.currency == selectedCurrency }),
               let top = totals.max(by: { $0.total.minorUnits < $1.total.minorUnits }) {
                self.selectedCurrency = top.currency
            }

            async let categoriesTask = q.spendingByCategory(start: start, endExclusive: end, currency: selectedCurrency)
            async let merchantsTask  = q.topMerchants(start: start, endExclusive: end, currency: selectedCurrency, limit: 8)
            async let largestTask    = q.largestTransactions(start: start, endExclusive: end, currency: selectedCurrency, limit: 5)
            async let cardsTask      = q.totalsByCard(start: start, endExclusive: end, currency: selectedCurrency)

            self.spendingByCategory  = try await categoriesTask
            self.topMerchants        = try await merchantsTask
            self.largestTransactions = try await largestTask
            self.totalsByCard        = try await cardsTask
            self.uncategorizedCount  = try await uncatTask
            self.needsReviewCount    = try await needsTask
            self.loadError = nil
        } catch {
            self.loadError = "Failed to load dashboard: \(error.localizedDescription)"
        }
        self.hasLoaded = true
    }

    private func resetSnapshots() {
        totalsByCurrency = []
        spendingByCategory = []
        topMerchants = []
        largestTransactions = []
        totalsByCard = []
        uncategorizedCount = 0
        needsReviewCount = 0
    }

    // MARK: - Helpers

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
