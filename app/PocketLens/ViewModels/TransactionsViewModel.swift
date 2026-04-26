import Foundation
import SwiftUI
import Domain
import Persistence

@MainActor
final class TransactionsViewModel: ObservableObject {

    static let pageSize = 50

    /// Display row — combines a `Transaction` with the parent `Card`'s last4
    /// for the per-row card chip.
    struct Row: Identifiable, Hashable {
        let transaction: Domain.Transaction
        let cardLast4: String

        var id: Int64 { transaction.id ?? 0 }
    }

    @Published var rows: [Row] = []
    @Published var categories: [Domain.Category] = []
    @Published var loadError: String?
    @Published var hasLoaded = false
    @Published var isLoadingMore = false

    @Published var currentMonth: DateInterval = TransactionsViewModel.month(containing: Date())
    @Published private(set) var totalInMonth: Int = 0
    @Published private(set) var bounds: (min: Date, max: Date)?

    private var cardLast4ById: [Int64: String] = [:]

    var hasMore: Bool { rows.count < totalInMonth }

    var canGoPrev: Bool {
        guard let b = bounds else { return false }
        return currentMonth.start > Self.month(containing: b.min).start
    }

    var canGoNext: Bool {
        guard let b = bounds else { return false }
        return currentMonth.start < Self.month(containing: b.max).start
    }

    /// First load: fetch supporting data, jump to the most recent month with
    /// transactions, and load page 1.
    func reload(store: SQLiteStore?) async {
        guard let store else { rows = []; hasLoaded = true; return }
        do {
            let txRepo = TransactionRepository(store: store)
            let cardRepo = CardRepository(store: store)
            let catRepo = CategoryRepository(store: store)

            let cards = try await cardRepo.all()
            cardLast4ById = Dictionary(uniqueKeysWithValues: cards.compactMap { c in
                c.id.map { ($0, c.last4) }
            })
            categories = try await catRepo.all()

            bounds = try await txRepo.postedDateBounds()
            if let b = bounds {
                currentMonth = Self.month(containing: b.max)
            }
            try await loadPage(reset: true, store: store)
            loadError = nil
        } catch {
            loadError = "Failed to load transactions: \(error.localizedDescription)"
        }
        hasLoaded = true
    }

    /// Reload page 1 of the current month and refresh bounds. Used after import
    /// completes or after a rule/alias edit that may have re-categorized rows.
    /// Jumps to the most recent month if an import extended the upper bound.
    func refresh(store: SQLiteStore?) async {
        guard let store else { return }
        do {
            let txRepo = TransactionRepository(store: store)
            bounds = try await txRepo.postedDateBounds()
            if let b = bounds {
                let latest = Self.month(containing: b.max)
                if latest.start > currentMonth.start {
                    currentMonth = latest
                }
            }
            try await loadPage(reset: true, store: store)
        } catch {
            loadError = "Failed to refresh transactions: \(error.localizedDescription)"
        }
    }

    func goToPreviousMonth(store: SQLiteStore?) async {
        guard canGoPrev, let store else { return }
        currentMonth = Self.shift(currentMonth, by: -1)
        do { try await loadPage(reset: true, store: store) }
        catch { loadError = "Failed to load month: \(error.localizedDescription)" }
    }

    func goToNextMonth(store: SQLiteStore?) async {
        guard canGoNext, let store else { return }
        currentMonth = Self.shift(currentMonth, by: 1)
        do { try await loadPage(reset: true, store: store) }
        catch { loadError = "Failed to load month: \(error.localizedDescription)" }
    }

    func loadMore(store: SQLiteStore?) async {
        guard hasMore, !isLoadingMore, let store else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do { try await loadPage(reset: false, store: store) }
        catch { loadError = "Failed to load more: \(error.localizedDescription)" }
    }

    private func loadPage(reset: Bool, store: SQLiteStore) async throws {
        let txRepo = TransactionRepository(store: store)
        if reset {
            totalInMonth = try await txRepo.countInMonth(
                start: currentMonth.start,
                endExclusive: currentMonth.end
            )
        }
        let offset = reset ? 0 : rows.count
        let page = try await txRepo.inMonth(
            start: currentMonth.start,
            endExclusive: currentMonth.end,
            limit: Self.pageSize,
            offset: offset
        )
        let mapped = page.map(makeRow)
        if reset { rows = mapped } else { rows.append(contentsOf: mapped) }
    }

    private func makeRow(_ tx: Domain.Transaction) -> Row {
        Row(
            transaction: tx,
            cardLast4: tx.cardId.flatMap { cardLast4ById[$0] } ?? "????"
        )
    }

    /// Apply a user-initiated category change. Mutates the affected row in
    /// place rather than reloading, so the user keeps their scroll position
    /// and any "view more" pages they've already loaded.
    func updateCategory(transactionId: Int64, categoryId: Int64?, store: SQLiteStore?) async {
        guard let store else { return }
        do {
            let txRepo = TransactionRepository(store: store)

            let prior = try await txRepo.find(id: transactionId)
            let oldCategoryId = prior?.categoryId

            try await txRepo.updateCategorization(
                transactionId: transactionId,
                categoryId: categoryId,
                confidence: categoryId == nil ? 0.0 : 1.0,
                reason: categoryId == nil
                    ? "User cleared category"
                    : "Prior user correction on this transaction"
            )

            // Only log a correction when we have a destination category and the
            // assignment actually changed. Clearing the category isn't a "learn
            // this" signal.
            if let newCategoryId = categoryId, newCategoryId != oldCategoryId {
                _ = try await UserCorrectionRepository(store: store).insert(UserCorrection(
                    transactionId: transactionId,
                    oldCategoryId: oldCategoryId,
                    newCategoryId: newCategoryId,
                    correctionType: .category
                ))
            }

            if let updated = try await txRepo.find(id: transactionId),
               let idx = rows.firstIndex(where: { $0.id == transactionId }) {
                rows[idx] = makeRow(updated)
            }
        } catch {
            self.loadError = "Failed to update category: \(error.localizedDescription)"
        }
    }

    // MARK: - Month helpers

    /// UTC month interval containing `date`, half-open (end is the start of the
    /// next month). Mirrors `DashboardViewModel.interval` to stay aligned with
    /// the on-disk `posted_date` strings, which are UTC.
    static func month(containing date: Date) -> DateInterval {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let start = cal.dateInterval(of: .month, for: date)?.start ?? date
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? date
        return DateInterval(start: start, end: end)
    }

    static func shift(_ month: DateInterval, by months: Int) -> DateInterval {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let newStart = cal.date(byAdding: .month, value: months, to: month.start) ?? month.start
        let newEnd = cal.date(byAdding: .month, value: 1, to: newStart) ?? month.end
        return DateInterval(start: newStart, end: newEnd)
    }
}
