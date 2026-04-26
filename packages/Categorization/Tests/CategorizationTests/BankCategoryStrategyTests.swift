import XCTest
import Domain
import Persistence
@testable import Categorization

final class BankCategoryStrategyTests: XCTestCase {

    func testItauAlimentacaoMapsToAlimentacao() async throws {
        let store = try TestEnv.makeStore()
        let alimentacao = try await TestEnv.categoryId(in: store, named: "Alimentação")

        let strategy = BankCategoryStrategy(store: store)
        let s = try await strategy.categorize(TestEnv.input(
            merchantNormalized: "anything",
            bankCategoryRaw: "ALIMENTAÇÃO",
            bankName: "Itaú"
        ))
        XCTAssertEqual(s?.categoryId, alimentacao)
        XCTAssertEqual(s?.confidence, 0.85)
        XCTAssertEqual(s?.reason, .bankCategoryMapping)
    }

    func testCaseInsensitiveMatch() async throws {
        let store = try TestEnv.makeStore()
        let strategy = BankCategoryStrategy(store: store)
        let lower = try await strategy.categorize(TestEnv.input(
            merchantNormalized: "x",
            bankCategoryRaw: "alimentação",
            bankName: "Itaú"
        ))
        let upper = try await strategy.categorize(TestEnv.input(
            merchantNormalized: "x",
            bankCategoryRaw: "ALIMENTAÇÃO",
            bankName: "Itaú"
        ))
        XCTAssertEqual(lower?.categoryId, upper?.categoryId)
    }

    func testMissingMappingFallsThrough() async throws {
        let store = try TestEnv.makeStore()
        let strategy = BankCategoryStrategy(store: store)
        let s = try await strategy.categorize(TestEnv.input(
            merchantNormalized: "x",
            bankCategoryRaw: "totally unknown label",
            bankName: "Itaú"
        ))
        XCTAssertNil(s)
    }

    func testNoBankCategoryRawShortCircuits() async throws {
        let store = try TestEnv.makeStore()
        let strategy = BankCategoryStrategy(store: store)
        let s = try await strategy.categorize(TestEnv.input(
            merchantNormalized: "x",
            bankCategoryRaw: nil,
            bankName: "Itaú"
        ))
        XCTAssertNil(s)
    }

    func testIssuerSpecificBeatsWildcardAtRepoLevel() async throws {
        // Don't use the seeded data — assemble a wildcard + issuer-specific
        // pair manually so we directly exercise the repo's tiebreak.
        let store = try SQLiteStore.makeInMemory()
        let categoryRepo = CategoryRepository(store: store)
        let groceries = try await categoryRepo.insert(Domain.Category(name: "Groceries"))
        let other = try await categoryRepo.insert(Domain.Category(name: "Other"))
        let mapRepo = BankCategoryMappingRepository(store: store)
        _ = try await mapRepo.insert(BankCategoryMapping(
            bankName: nil, bankCategoryRaw: "alimentação", categoryId: other.id!
        ))
        _ = try await mapRepo.insert(BankCategoryMapping(
            bankName: "Itaú", bankCategoryRaw: "alimentação", categoryId: groceries.id!
        ))

        let strategy = BankCategoryStrategy(store: store)
        let s = try await strategy.categorize(TestEnv.input(
            merchantNormalized: "x",
            bankCategoryRaw: "alimentação",
            bankName: "Itaú"
        ))
        XCTAssertEqual(s?.categoryId, groceries.id)
    }
}
