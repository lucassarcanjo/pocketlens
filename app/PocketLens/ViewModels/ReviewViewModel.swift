import Foundation
import SwiftUI
import Domain
import Persistence

/// Backs `ReviewView`. Loads **all** transactions (across every month) so the
/// review queue can surface uncategorized / low-confidence items wherever they
/// live in history. Distinct from `TransactionsViewModel`, which only ever
/// holds the current month's page.
@MainActor
final class ReviewViewModel: ObservableObject {

    @Published var rows: [TransactionsViewModel.Row] = []
    @Published var categories: [Domain.Category] = []
    @Published var loadError: String?
    @Published var hasLoaded = false

    private var cardLast4ById: [Int64: String] = [:]

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

            let all = try await txRepo.all()
            rows = all.map(makeRow)
            loadError = nil
        } catch {
            loadError = "Failed to load review queue: \(error.localizedDescription)"
        }
        hasLoaded = true
    }

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
            loadError = "Failed to update category: \(error.localizedDescription)"
        }
    }

    private func makeRow(_ tx: Domain.Transaction) -> TransactionsViewModel.Row {
        TransactionsViewModel.Row(
            transaction: tx,
            cardLast4: tx.cardId.flatMap { cardLast4ById[$0] } ?? "????"
        )
    }
}
