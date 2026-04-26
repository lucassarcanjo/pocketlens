import Foundation
import SwiftUI
import Domain
import Persistence

@MainActor
final class TransactionsViewModel: ObservableObject {

    /// Display row — combines a `Transaction` with the parent `Card`'s last4
    /// for grouping in the table.
    struct Row: Identifiable, Hashable {
        let transaction: Domain.Transaction
        let cardLast4: String

        var id: Int64 { transaction.id ?? 0 }
    }

    @Published var rows: [Row] = []
    @Published var categories: [Domain.Category] = []
    @Published var loadError: String?
    @Published var hasLoaded = false

    func reload(store: SQLiteStore?) async {
        guard let store else { rows = []; hasLoaded = true; return }
        do {
            let txRepo = TransactionRepository(store: store)
            let cardRepo = CardRepository(store: store)
            let catRepo = CategoryRepository(store: store)
            let all = try await txRepo.all()
            let cards = try await cardRepo.all()
            let cardLast4ById: [Int64: String] = Dictionary(
                uniqueKeysWithValues: cards.compactMap { c in
                    c.id.map { ($0, c.last4) }
                }
            )
            self.rows = all.map { tx in
                Row(
                    transaction: tx,
                    cardLast4: tx.cardId.flatMap { cardLast4ById[$0] } ?? "????"
                )
            }
            self.categories = try await catRepo.all()
            self.loadError = nil
        } catch {
            self.loadError = "Failed to load transactions: \(error.localizedDescription)"
        }
        self.hasLoaded = true
    }

    /// Group rows by card for the section headers in `TransactionsView`.
    func grouped() -> [(last4: String, rows: [Row])] {
        let dict = Dictionary(grouping: rows, by: \.cardLast4)
        return dict.keys.sorted().map { key in
            (last4: key, rows: dict[key] ?? [])
        }
    }

    func updateCategory(transactionId: Int64, categoryId: Int64?, store: SQLiteStore?) async {
        guard let store else { return }
        do {
            let repo = TransactionRepository(store: store)
            try await repo.updateCategory(transactionId: transactionId, categoryId: categoryId)
            await reload(store: store)
        } catch {
            self.loadError = "Failed to update category: \(error.localizedDescription)"
        }
    }
}
