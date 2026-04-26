import XCTest
import Domain
import Persistence
@testable import Categorization

final class MerchantAliasStrategyTests: XCTestCase {

    func testAliasCollapsesVariantsToSingleMerchant() async throws {
        let store = try TestEnv.makeStore()
        let cat = try await TestEnv.categoryId(in: store, named: "Transporte")

        let merchantRepo = MerchantRepository(store: store)
        let aliasRepo = MerchantAliasRepository(store: store)

        let uber = try await merchantRepo.upsert(
            Merchant(raw: "UBER", normalized: "uber", defaultCategoryId: cat)
        )
        XCTAssertEqual(uber.defaultCategoryId, cat, "first-insert path must persist defaultCategoryId")

        _ = try await aliasRepo.insert(
            MerchantAlias(merchantId: uber.id!, alias: "uber *trip", source: .user)
        )
        _ = try await aliasRepo.insert(
            MerchantAlias(merchantId: uber.id!, alias: "uber trip sp", source: .user)
        )

        let strategy = MerchantAliasStrategy(store: store)

        // Variant 1.
        let s1 = try await strategy.categorize(TestEnv.input(
            merchantNormalized: "uber *trip 1234"
        ))
        XCTAssertEqual(s1?.categoryId, cat)
        XCTAssertEqual(s1?.confidence, 0.95)
        XCTAssertEqual(s1?.reason, .merchantAlias)

        // Variant 2.
        let s2 = try await strategy.categorize(TestEnv.input(
            merchantNormalized: "uber trip sp"
        ))
        XCTAssertEqual(s2?.categoryId, cat)
    }

    func testAliasFallsThroughWhenMerchantHasNoCategory() async throws {
        let store = try TestEnv.makeStore()
        let merchantRepo = MerchantRepository(store: store)
        let aliasRepo = MerchantAliasRepository(store: store)

        let m = try await merchantRepo.upsert(Merchant(raw: "X", normalized: "x"))
        _ = try await aliasRepo.insert(
            MerchantAlias(merchantId: m.id!, alias: "x", source: .user)
        )

        let strategy = MerchantAliasStrategy(store: store)
        let s = try await strategy.categorize(TestEnv.input(merchantNormalized: "x ltd"))
        XCTAssertNil(s, "no defaultCategoryId on the merchant → fall through")
    }
}
