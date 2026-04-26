import XCTest
import Domain
import Importing
import Persistence
@testable import Categorization

final class ImportPlanCategorizationTests: XCTestCase {

    func testApplyPopulatesEachTransaction() async throws {
        let store = try TestEnv.makeStore()
        let alimentacao = try await TestEnv.categoryId(in: store, named: "Alimentação")

        // Pre-existing user rule that will hit one transaction in the plan.
        _ = try await CategorizationRuleRepository(store: store).insert(
            CategorizationRule(
                name: "Padaria",
                pattern: "padaria",
                patternType: .contains,
                categoryId: alimentacao,
                createdBy: .user
            )
        )

        // Build a tiny plan with two transactions.
        let plan = makePlan(transactions: [
            ("padaria real", "ALIMENTAÇÃO"),
            ("totally novel merchant", nil),
        ])

        let engine = CategorizationEngine.standard(store: store)
        let updated = try await engine.apply(to: plan, bankName: "Itaú")

        XCTAssertEqual(updated.transactions.count, 2)

        // First transaction → user rule hit.
        let first = updated.transactions[0].transaction
        XCTAssertEqual(first.categoryId, alimentacao)
        XCTAssertEqual(first.confidence, 0.90)
        XCTAssertEqual(first.categorizationReason, "User rule: \"Padaria\"")

        // Second → no rule, falls all the way through to uncategorized.
        let second = updated.transactions[1].transaction
        XCTAssertNil(second.categoryId)
        XCTAssertEqual(second.confidence, 0.0)
        XCTAssertEqual(second.categorizationReason, "No strong rule found")
    }

    // MARK: - Helpers

    private func makePlan(transactions: [(merchant: String, bankCategoryRaw: String?)]) -> ImportPlan {
        let card = Card(last4: "0001", holderName: "L")
        let merchants = transactions.map {
            Merchant(raw: $0.merchant, normalized: $0.merchant)
        }
        let pending = transactions.map { row -> PendingTransaction in
            let tx = Transaction(
                postedDate: Date(timeIntervalSince1970: 0),
                rawDescription: row.merchant,
                merchantNormalized: row.merchant,
                bankCategoryRaw: row.bankCategoryRaw,
                amount: Money(major: 50, currency: .BRL),
                purchaseMethod: .physical,
                transactionType: .purchase,
                confidence: 1.0
            )
            return PendingTransaction(
                cardLast4: "0001",
                merchantNormalized: row.merchant,
                transaction: tx,
                fingerprint: "fp-\(row.merchant)"
            )
        }
        let batch = ImportBatch(
            sourceFileName: "x.pdf",
            sourceFileSha256: "sha-x",
            sourcePages: 1,
            statementTotal: Money(major: 100, currency: .BRL),
            llmProvider: .mock, llmModel: "m", llmPromptVersion: "v1",
            llmInputTokens: 0, llmOutputTokens: 0, llmCostUSD: 0,
            validationStatus: .ok
        )
        return ImportPlan(batch: batch, cards: [card], merchants: merchants, transactions: pending)
    }
}
