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

    /// Apply a user-initiated category change. Writes the override on the
    /// transaction itself AND records a `UserCorrection` row so the engine
    /// can replay the choice on future imports of the same fingerprint.
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

            await reload(store: store)
        } catch {
            self.loadError = "Failed to update category: \(error.localizedDescription)"
        }
    }
}
