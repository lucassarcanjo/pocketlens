import XCTest
import Domain
import Persistence
@testable import Categorization

final class UserCorrectionStrategyTests: XCTestCase {

    func testReturnsLatestCorrectionByFingerprint() async throws {
        let store = try TestEnv.makeStore()
        let alimentacao = try await TestEnv.categoryId(in: store, named: "Alimentação")
        let lazer = try await TestEnv.categoryId(in: store, named: "Lazer")

        let fingerprint = "deterministic-fp-1"
        let tx = try await TestEnv.insertTransaction(
            in: store,
            merchantNormalized: "padaria real",
            categoryId: alimentacao,
            fingerprint: fingerprint
        )

        // User corrects from Alimentação → Lazer (synthetic).
        _ = try await UserCorrectionRepository(store: store).insert(UserCorrection(
            transactionId: tx.id!,
            oldCategoryId: alimentacao,
            newCategoryId: lazer
        ))

        // Re-categorize a NEW input that has the same fingerprint (e.g.
        // overlapping statement re-import). Strategy should find the prior
        // correction and replay it.
        let strategy = UserCorrectionStrategy(store: store)
        let s = try await strategy.categorize(TestEnv.input(
            merchantNormalized: "padaria real",
            fingerprint: fingerprint
        ))
        XCTAssertEqual(s?.categoryId, lazer)
        XCTAssertEqual(s?.confidence, 1.00)
        XCTAssertEqual(s?.reason, .userCorrection)
    }

    func testNoPriorTransactionFallsThrough() async throws {
        let store = try TestEnv.makeStore()
        let strategy = UserCorrectionStrategy(store: store)
        let s = try await strategy.categorize(TestEnv.input(
            merchantNormalized: "x", fingerprint: "never-seen"
        ))
        XCTAssertNil(s)
    }

    func testPriorTransactionWithoutCorrectionFallsThrough() async throws {
        let store = try TestEnv.makeStore()
        let alimentacao = try await TestEnv.categoryId(in: store, named: "Alimentação")
        let fingerprint = "fp-no-correction"
        _ = try await TestEnv.insertTransaction(
            in: store,
            merchantNormalized: "x",
            categoryId: alimentacao,
            fingerprint: fingerprint
        )
        let strategy = UserCorrectionStrategy(store: store)
        let s = try await strategy.categorize(TestEnv.input(
            merchantNormalized: "x", fingerprint: fingerprint
        ))
        XCTAssertNil(s, "no user_corrections row → fall through")
    }
}
