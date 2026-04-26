import Foundation
import Domain
import Persistence
@testable import Categorization

/// Shared helpers for Categorization tests. Builds an in-memory store with
/// the default category set seeded so tests can refer to categories by name.
enum TestEnv {

    static func makeStore() throws -> SQLiteStore {
        let store = try SQLiteStore.makeInMemory()
        try DefaultDataSeeder.seed(into: store)
        return store
    }

    static func categoryId(in store: SQLiteStore, named name: String) async throws -> Int64 {
        let cats = try await CategoryRepository(store: store).all()
        guard let id = cats.first(where: { $0.name == name })?.id else {
            fatalError("Category \(name) not seeded")
        }
        return id
    }

    /// Build a CategorizationInput for a transaction the engine can score.
    /// `transactionId` is nil since most tests categorize at "import time".
    static func input(
        merchantNormalized: String,
        bankCategoryRaw: String? = nil,
        bankName: String? = nil,
        amount: Money = Money(major: 50, currency: .BRL),
        merchantId: Int64? = nil,
        fingerprint: String = UUID().uuidString
    ) -> CategorizationInput {
        CategorizationInput(
            transactionId: nil,
            merchantNormalized: merchantNormalized,
            merchantId: merchantId,
            bankCategoryRaw: bankCategoryRaw,
            bankName: bankName,
            amount: amount,
            fingerprint: fingerprint
        )
    }

    /// Insert a transaction we can refer back to (for similarity / user
    /// correction strategies). Returns the persisted row.
    static func insertTransaction(
        in store: SQLiteStore,
        merchantNormalized: String,
        amount: Money = Money(major: 50, currency: .BRL),
        categoryId: Int64? = nil,
        fingerprint: String = UUID().uuidString,
        last4: String = "0001"
    ) async throws -> Transaction {
        let acctRepo = AccountRepository(store: store)
        let cardRepo = CardRepository(store: store)
        let batchRepo = ImportBatchRepository(store: store)
        let txRepo = TransactionRepository(store: store)

        let acct = try await acctRepo.findOrCreate(bankName: "Itaú", holderName: "L")
        let card = try await cardRepo.upsert(
            Card(last4: last4, holderName: "L"),
            accountId: acct.id!
        )
        let batchSha = "sha-\(UUID().uuidString)"
        let batch = try await batchRepo.insert(ImportBatch(
            sourceFileName: "x.pdf",
            sourceFileSha256: batchSha,
            sourcePages: 1,
            statementTotal: Money(major: 0, currency: .BRL),
            llmProvider: .mock,
            llmModel: "m",
            llmPromptVersion: "v1",
            llmInputTokens: 0, llmOutputTokens: 0, llmCostUSD: 0,
            validationStatus: .ok
        ))
        var tx = Transaction(
            postedDate: Date(timeIntervalSince1970: 0),
            rawDescription: merchantNormalized,
            merchantNormalized: merchantNormalized,
            amount: amount,
            confidence: 1.0
        )
        tx.categoryId = categoryId
        return try await txRepo.insert(
            tx,
            fingerprint: fingerprint,
            importBatchId: batch.id!,
            cardId: card.id!,
            merchantId: nil
        )
    }
}
