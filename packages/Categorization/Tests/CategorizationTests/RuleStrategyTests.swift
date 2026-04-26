import XCTest
import Domain
import Persistence
@testable import Categorization

final class RuleStrategyTests: XCTestCase {

    func testContainsPattern() async throws {
        let store = try TestEnv.makeStore()
        let cat = try await TestEnv.categoryId(in: store, named: "Transporte")
        _ = try await CategorizationRuleRepository(store: store).insert(
            CategorizationRule(
                name: "Uber → Transporte",
                pattern: "uber",
                patternType: .contains,
                categoryId: cat,
                priority: 0,
                createdBy: .user
            )
        )
        let strategy = RuleStrategy(store: store, source: .user, reason: .userRule, baseConfidence: 0.90)
        let s = try await strategy.categorize(TestEnv.input(merchantNormalized: "uber *trip 4451"))
        XCTAssertEqual(s?.categoryId, cat)
        XCTAssertEqual(s?.reason, .userRule)
        XCTAssertEqual(s?.confidence, 0.90)
    }

    func testExactPattern() async throws {
        let store = try TestEnv.makeStore()
        let cat = try await TestEnv.categoryId(in: store, named: "Alimentação")
        _ = try await CategorizationRuleRepository(store: store).insert(
            CategorizationRule(
                name: "exact",
                pattern: "padaria real",
                patternType: .exact,
                categoryId: cat,
                createdBy: .user
            )
        )
        let strategy = RuleStrategy(store: store, source: .user, reason: .userRule, baseConfidence: 0.90)
        let hit = try await strategy.categorize(TestEnv.input(merchantNormalized: "padaria real"))
        XCTAssertNotNil(hit)
        let miss = try await strategy.categorize(TestEnv.input(merchantNormalized: "padaria real branca"))
        XCTAssertNil(miss, "exact must not match substring")
    }

    func testRegexPattern() async throws {
        let store = try TestEnv.makeStore()
        let cat = try await TestEnv.categoryId(in: store, named: "Lazer")
        _ = try await CategorizationRuleRepository(store: store).insert(
            CategorizationRule(
                name: "regex",
                pattern: #"^netflix.*"#,
                patternType: .regex,
                categoryId: cat,
                createdBy: .user
            )
        )
        let strategy = RuleStrategy(store: store, source: .user, reason: .userRule, baseConfidence: 0.90)
        let hit = try await strategy.categorize(TestEnv.input(merchantNormalized: "netflix.com brasil"))
        XCTAssertNotNil(hit)
        let miss = try await strategy.categorize(TestEnv.input(merchantNormalized: "spotify"))
        XCTAssertNil(miss)
    }

    func testMalformedRegexFallsThrough() async throws {
        let store = try TestEnv.makeStore()
        let cat = try await TestEnv.categoryId(in: store, named: "Outros")
        _ = try await CategorizationRuleRepository(store: store).insert(
            CategorizationRule(
                name: "broken",
                pattern: #"["#,  // unbalanced bracket
                patternType: .regex,
                categoryId: cat,
                createdBy: .user
            )
        )
        let strategy = RuleStrategy(store: store, source: .user, reason: .userRule, baseConfidence: 0.90)
        let s = try await strategy.categorize(TestEnv.input(merchantNormalized: "[abc"))
        XCTAssertNil(s, "malformed regex must fall through, not throw")
    }

    func testMerchantPattern() async throws {
        let store = try TestEnv.makeStore()
        let merchantRepo = MerchantRepository(store: store)
        let m = try await merchantRepo.upsert(Merchant(raw: "AMAZON", normalized: "amazon"))
        let cat = try await TestEnv.categoryId(in: store, named: "Compras")
        _ = try await CategorizationRuleRepository(store: store).insert(
            CategorizationRule(
                name: "merchant",
                pattern: "",
                patternType: .merchant,
                merchantId: m.id,
                categoryId: cat,
                createdBy: .user
            )
        )
        let strategy = RuleStrategy(store: store, source: .user, reason: .userRule, baseConfidence: 0.90)
        let s = try await strategy.categorize(
            TestEnv.input(merchantNormalized: "amazon", merchantId: m.id)
        )
        XCTAssertEqual(s?.categoryId, cat)

        let none = try await strategy.categorize(
            TestEnv.input(merchantNormalized: "other", merchantId: 99999)
        )
        XCTAssertNil(none)
    }

    func testAmountRangePattern() async throws {
        let store = try TestEnv.makeStore()
        let cat = try await TestEnv.categoryId(in: store, named: "Outros")
        // Range 5000..15000 minor units = R$50.00..R$150.00
        _ = try await CategorizationRuleRepository(store: store).insert(
            CategorizationRule(
                name: "midrange",
                pattern: "5000..15000",
                patternType: .amountRange,
                categoryId: cat,
                createdBy: .user
            )
        )
        let strategy = RuleStrategy(store: store, source: .user, reason: .userRule, baseConfidence: 0.90)

        let inside = try await strategy.categorize(TestEnv.input(
            merchantNormalized: "x", amount: Money(major: 75, currency: .BRL)
        ))
        XCTAssertNotNil(inside)

        let below = try await strategy.categorize(TestEnv.input(
            merchantNormalized: "x", amount: Money(major: 10, currency: .BRL)
        ))
        XCTAssertNil(below)

        let above = try await strategy.categorize(TestEnv.input(
            merchantNormalized: "x", amount: Money(major: 200, currency: .BRL)
        ))
        XCTAssertNil(above)
    }

    func testAmountRangeWildcard() async throws {
        let store = try TestEnv.makeStore()
        let cat = try await TestEnv.categoryId(in: store, named: "Outros")
        _ = try await CategorizationRuleRepository(store: store).insert(
            CategorizationRule(
                name: "big",
                pattern: "100000..*",
                patternType: .amountRange,
                categoryId: cat,
                createdBy: .user
            )
        )
        let strategy = RuleStrategy(store: store, source: .user, reason: .userRule, baseConfidence: 0.90)
        let big = try await strategy.categorize(TestEnv.input(
            merchantNormalized: "x", amount: Money(major: 5000, currency: .BRL)
        ))
        XCTAssertNotNil(big, "* upper bound must allow any large amount")
    }

    func testHigherPriorityWins() async throws {
        let store = try TestEnv.makeStore()
        let lazer = try await TestEnv.categoryId(in: store, named: "Lazer")
        let viagens = try await TestEnv.categoryId(in: store, named: "Viagens")

        let repo = CategorizationRuleRepository(store: store)
        _ = try await repo.insert(CategorizationRule(
            name: "low", pattern: "trip", patternType: .contains,
            categoryId: lazer, priority: 1, createdBy: .user
        ))
        _ = try await repo.insert(CategorizationRule(
            name: "high", pattern: "trip", patternType: .contains,
            categoryId: viagens, priority: 100, createdBy: .user
        ))

        let strategy = RuleStrategy(store: store, source: .user, reason: .userRule, baseConfidence: 0.90)
        let s = try await strategy.categorize(TestEnv.input(merchantNormalized: "uber *trip"))
        XCTAssertEqual(s?.categoryId, viagens)
    }
}
