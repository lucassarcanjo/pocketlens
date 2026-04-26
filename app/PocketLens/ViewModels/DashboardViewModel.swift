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

    /// Cross-filter: when non-nil, every "filterable" card (totals / merchants
    /// / largest / cards / trend) re-queries scoped to this category. Stays
    /// in-memory only — not persisted, so a reload starts unfiltered.
    @Published private(set) var selectedCategoryId: Int64?

    /// Display name for the active filter. Set alongside `selectedCategoryId`
    /// in `setCategoryFilter` so the pill doesn't have to look it up.
    @Published private(set) var selectedCategoryName: String?

    // MARK: - Loaded snapshots

    @Published var totalsByCurrency: [AggregateQueries.CurrencyTotal] = []
    @Published var spendingByCategory: [AggregateQueries.CategoryTotal] = []
    @Published var topMerchants: [AggregateQueries.MerchantTotal] = []
    @Published var largestTransactions: [AggregateQueries.LargestTransaction] = []
    @Published var totalsByCard: [AggregateQueries.CardTotal] = []
    @Published var monthlyTrend: [AggregateQueries.MonthTotal] = []
    @Published var uncategorizedCount: Int = 0
    @Published var needsReviewCount: Int = 0

    @Published var loadError: String?
    @Published var hasLoaded = false

    /// Trailing window for the trend chart. Decoupled from the period picker
    /// on purpose — the trend's job is to give a baseline against which the
    /// selected period can be judged.
    static let trendMonthCount = 6

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
        let cat = selectedCategoryId
        do {
            // Currency totals MUST stay unfiltered — the segmented currency
            // picker needs to show every currency the period contains, even
            // if the active category has no data in some of them.
            async let unfilteredTotalsTask = q.totalsByCurrency(start: start, endExclusive: end)
            async let uncatTask            = q.uncategorizedCount(start: start, endExclusive: end)
            async let needsTask            = q.needsReviewCount(start: start, endExclusive: end)

            let unfilteredTotals = try await unfilteredTotalsTask
            self.totalsByCurrency = try await q.totalsByCurrency(
                start: start, endExclusive: end, categoryId: cat
            )

            // Default the selected currency to the largest-total currency in
            // the period if the persisted choice has no data here. Use the
            // unfiltered totals so the fallback isn't biased by the active
            // category filter.
            if !unfilteredTotals.contains(where: { $0.currency == selectedCurrency }),
               let top = unfilteredTotals.max(by: { $0.total.minorUnits < $1.total.minorUnits }) {
                self.selectedCurrency = top.currency
            }

            // Category breakdown stays unfiltered — it acts as the legend /
            // selector for the cross-filter itself.
            async let categoriesTask = q.spendingByCategory(start: start, endExclusive: end, currency: selectedCurrency)
            async let merchantsTask  = q.topMerchants(start: start, endExclusive: end, currency: selectedCurrency, limit: 8, categoryId: cat)
            async let largestTask    = q.largestTransactions(start: start, endExclusive: end, currency: selectedCurrency, limit: 5, categoryId: cat)
            async let cardsTask      = q.totalsByCard(start: start, endExclusive: end, currency: selectedCurrency, categoryId: cat)
            async let trendTask      = q.spendingByMonth(months: Self.trendMonthCount, currency: selectedCurrency, categoryId: cat)

            self.spendingByCategory  = try await categoriesTask
            self.topMerchants        = try await merchantsTask
            self.largestTransactions = try await largestTask
            self.totalsByCard        = try await cardsTask
            self.monthlyTrend        = try await trendTask
            self.uncategorizedCount  = try await uncatTask
            self.needsReviewCount    = try await needsTask
            self.loadError = nil
        } catch {
            self.loadError = "Failed to load dashboard: \(error.localizedDescription)"
        }
        self.hasLoaded = true
    }

    /// Toggle the category cross-filter. Passing the already-selected category
    /// clears it; passing `nil` always clears.
    func setCategoryFilter(
        _ categoryId: Int64?,
        name: String?,
        store: SQLiteStore?
    ) async {
        if categoryId == selectedCategoryId {
            selectedCategoryId = nil
            selectedCategoryName = nil
        } else {
            selectedCategoryId = categoryId
            selectedCategoryName = name
        }
        await reload(store: store)
    }

    private func resetSnapshots() {
        totalsByCurrency = []
        spendingByCategory = []
        topMerchants = []
        largestTransactions = []
        totalsByCard = []
        monthlyTrend = []
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
