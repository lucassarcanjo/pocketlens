import XCTest
import Domain
import Persistence
@testable import Categorization

final class EnginePriorityTests: XCTestCase {

    /// User correction (slot 1) wins over a bank-category mapping (slot 4)
    /// even when both match.
    func testUserCorrectionBeatsBankCategoryMapping() async throws {
        let store = try TestEnv.makeStore()
        let alimentacao = try await TestEnv.categoryId(in: store, named: "Alimentação")
        let lazer = try await TestEnv.categoryId(in: store, named: "Lazer")

        let fingerprint = "fp-priority-1"
        let tx = try await TestEnv.insertTransaction(
            in: store,
            merchantNormalized: "padaria real",
            categoryId: alimentacao,
            fingerprint: fingerprint
        )
        _ = try await UserCorrectionRepository(store: store).insert(UserCorrection(
            transactionId: tx.id!,
            oldCategoryId: alimentacao,
            newCategoryId: lazer
        ))

        let engine = CategorizationEngine.standard(store: store)
        let s = try await engine.categorize(TestEnv.input(
            merchantNormalized: "padaria real",
            bankCategoryRaw: "ALIMENTAÇÃO",
            bankName: "Itaú",
            fingerprint: fingerprint
        ))
        XCTAssertEqual(s.reason, .userCorrection)
        XCTAssertEqual(s.categoryId, lazer)
    }

    /// User rule (slot 3) wins over a bank-category mapping (slot 4) and a
    /// system rule (slot 5).
    func testUserRuleBeatsBankAndSystemRule() async throws {
        let store = try TestEnv.makeStore()
        let viagens = try await TestEnv.categoryId(in: store, named: "Viagens")
        let alimentacao = try await TestEnv.categoryId(in: store, named: "Alimentação")
        let outros = try await TestEnv.categoryId(in: store, named: "Outros")

        let ruleRepo = CategorizationRuleRepository(store: store)
        _ = try await ruleRepo.insert(CategorizationRule(
            name: "user", pattern: "uber", patternType: .contains,
            categoryId: viagens, createdBy: .user
        ))
        _ = try await ruleRepo.insert(CategorizationRule(
            name: "system", pattern: "uber", patternType: .contains,
            categoryId: outros, createdBy: .system
        ))

        let engine = CategorizationEngine.standard(store: store)
        let s = try await engine.categorize(TestEnv.input(
            merchantNormalized: "uber *trip",
            bankCategoryRaw: "ALIMENTAÇÃO",
            bankName: "Itaú"
        ))
        XCTAssertEqual(s.reason, .userRule)
        XCTAssertEqual(s.categoryId, viagens)
        // Sanity: the bank mapping would have routed to alimentacao, but slot 3 won.
        XCTAssertNotEqual(s.categoryId, alimentacao)
    }

    /// Bank-category mapping (slot 4) wins over a system keyword rule (slot 5).
    func testBankMappingBeatsSystemRule() async throws {
        let store = try TestEnv.makeStore()
        let alimentacao = try await TestEnv.categoryId(in: store, named: "Alimentação")
        let outros = try await TestEnv.categoryId(in: store, named: "Outros")

        _ = try await CategorizationRuleRepository(store: store).insert(CategorizationRule(
            name: "system",
            pattern: "anything",
            patternType: .contains,
            categoryId: outros,
            createdBy: .system
        ))

        let engine = CategorizationEngine.standard(store: store)
        let s = try await engine.categorize(TestEnv.input(
            merchantNormalized: "anything pizzaria",
            bankCategoryRaw: "ALIMENTAÇÃO",
            bankName: "Itaú"
        ))
        XCTAssertEqual(s.reason, .bankCategoryMapping)
        XCTAssertEqual(s.categoryId, alimentacao)
    }

    /// All strategies miss → the engine returns `.uncategorized`.
    func testUncategorizedWhenNothingMatches() async throws {
        let store = try TestEnv.makeStore()
        let engine = CategorizationEngine.standard(store: store)
        let s = try await engine.categorize(TestEnv.input(
            merchantNormalized: "totally novel merchant"
        ))
        XCTAssertEqual(s.reason, .uncategorized)
        XCTAssertNil(s.categoryId)
        XCTAssertEqual(s.confidence, 0.0)
    }

    /// Confidence bands per `docs/categorization.md`.
    func testEachStrategyEmitsItsConfidenceBand() async throws {
        let store = try TestEnv.makeStore()
        let cat = try await TestEnv.categoryId(in: store, named: "Outros")

        // user correction → 1.00
        let fp = "fp-bands"
        let tx = try await TestEnv.insertTransaction(
            in: store, merchantNormalized: "x", categoryId: cat, fingerprint: fp
        )
        _ = try await UserCorrectionRepository(store: store).insert(UserCorrection(
            transactionId: tx.id!, oldCategoryId: nil, newCategoryId: cat
        ))
        let userCorr = try await UserCorrectionStrategy(store: store)
            .categorize(TestEnv.input(merchantNormalized: "x", fingerprint: fp))
        XCTAssertEqual(userCorr?.confidence, 1.00)

        // user rule → 0.90
        _ = try await CategorizationRuleRepository(store: store).insert(CategorizationRule(
            name: "u", pattern: "u", patternType: .contains,
            categoryId: cat, createdBy: .user
        ))
        let userRule = try await RuleStrategy(
            store: store, source: .user, reason: .userRule, baseConfidence: 0.90
        ).categorize(TestEnv.input(merchantNormalized: "uber"))
        XCTAssertEqual(userRule?.confidence, 0.90)

        // bank category → 0.85
        let bank = try await BankCategoryStrategy(store: store)
            .categorize(TestEnv.input(
                merchantNormalized: "x", bankCategoryRaw: "ALIMENTAÇÃO", bankName: "Itaú"
            ))
        XCTAssertEqual(bank?.confidence, 0.85)

        // keyword (system) rule → 0.80
        _ = try await CategorizationRuleRepository(store: store).insert(CategorizationRule(
            name: "s", pattern: "kw", patternType: .contains,
            categoryId: cat, createdBy: .system
        ))
        let kw = try await RuleStrategy(
            store: store, source: .system, reason: .keywordRule, baseConfidence: 0.80
        ).categorize(TestEnv.input(merchantNormalized: "kw merchant"))
        XCTAssertEqual(kw?.confidence, 0.80)
    }
}
