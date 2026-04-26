import XCTest
import Domain
import Persistence
@testable import Categorization

final class SimilarityStrategyTests: XCTestCase {

    func testIdenticalDescriptionMatches() async throws {
        let store = try TestEnv.makeStore()
        let cat = try await TestEnv.categoryId(in: store, named: "Transporte")
        _ = try await TestEnv.insertTransaction(
            in: store,
            merchantNormalized: "uber *trip 1234",
            categoryId: cat
        )

        let strategy = SimilarityStrategy(store: store)
        let s = try await strategy.categorize(TestEnv.input(merchantNormalized: "uber *trip 1234"))
        XCTAssertEqual(s?.categoryId, cat)
        XCTAssertEqual(s?.confidence, 0.85)
        XCTAssertEqual(s?.reason, .similarity)
    }

    func testNearMatchAboveThreshold() async throws {
        let store = try TestEnv.makeStore()
        let cat = try await TestEnv.categoryId(in: store, named: "Lazer")
        _ = try await TestEnv.insertTransaction(
            in: store,
            merchantNormalized: "netflix.com brasil",
            categoryId: cat
        )

        // Lower threshold so a small variation matches deterministically.
        let strategy = SimilarityStrategy(store: store, threshold: 0.6)
        let s = try await strategy.categorize(TestEnv.input(merchantNormalized: "netflix.com brasil "))
        XCTAssertEqual(s?.categoryId, cat)
        if let confidence = s?.confidence {
            XCTAssertGreaterThanOrEqual(confidence, 0.50)
            XCTAssertLessThanOrEqual(confidence, 0.85)
        }
    }

    func testBelowThresholdFallsThrough() async throws {
        let store = try TestEnv.makeStore()
        let cat = try await TestEnv.categoryId(in: store, named: "Outros")
        _ = try await TestEnv.insertTransaction(
            in: store,
            merchantNormalized: "totally unrelated text",
            categoryId: cat
        )
        let strategy = SimilarityStrategy(store: store, threshold: 0.85)
        let s = try await strategy.categorize(TestEnv.input(merchantNormalized: "uber"))
        XCTAssertNil(s)
    }

    func testNoCategorizedTransactionsFallsThrough() async throws {
        let store = try TestEnv.makeStore()
        // No prior transactions inserted.
        let strategy = SimilarityStrategy(store: store)
        let s = try await strategy.categorize(TestEnv.input(merchantNormalized: "anything"))
        XCTAssertNil(s)
    }
}
