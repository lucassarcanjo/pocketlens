import XCTest
@testable import Persistence
import Domain

final class Phase2RepositoriesTests: XCTestCase {

    private func makeStore() throws -> SQLiteStore {
        try SQLiteStore.makeInMemory()
    }

    // MARK: - MerchantAliasRepository

    func testMerchantAlias_InsertAndFetchByMerchant() async throws {
        let store = try makeStore()
        let merchantRepo = MerchantRepository(store: store)
        let aliasRepo = MerchantAliasRepository(store: store)

        let m = try await merchantRepo.upsert(
            Merchant(raw: "UBER *TRIP", normalized: "uber *trip")
        )

        _ = try await aliasRepo.insert(
            MerchantAlias(merchantId: m.id!, alias: "uber trip sp", source: .user)
        )
        _ = try await aliasRepo.insert(
            MerchantAlias(merchantId: m.id!, alias: "uber br", source: .system)
        )

        let aliases = try await aliasRepo.forMerchant(m.id!)
        XCTAssertEqual(aliases.count, 2)
        XCTAssertEqual(Set(aliases.map { $0.alias }), ["uber trip sp", "uber br"])
    }

    func testMerchantAlias_UniquePerMerchant() async throws {
        let store = try makeStore()
        let merchantRepo = MerchantRepository(store: store)
        let aliasRepo = MerchantAliasRepository(store: store)
        let m = try await merchantRepo.upsert(
            Merchant(raw: "X", normalized: "x")
        )
        _ = try await aliasRepo.insert(
            MerchantAlias(merchantId: m.id!, alias: "abc", source: .user)
        )
        do {
            _ = try await aliasRepo.insert(
                MerchantAlias(merchantId: m.id!, alias: "abc", source: .user)
            )
            XCTFail("expected UNIQUE(merchant_id, alias) violation")
        } catch {
            // expected
        }
    }

    // MARK: - CategorizationRuleRepository

    func testCategorizationRule_FilterByCreatedBy() async throws {
        let store = try makeStore()
        try DefaultDataSeeder.seed(into: store)
        let ruleRepo = CategorizationRuleRepository(store: store)
        let categories = try await CategoryRepository(store: store).all()
        let alimentacao = categories.first { $0.name == "Alimentação" }!.id!

        _ = try await ruleRepo.insert(CategorizationRule(
            name: "User: padaria",
            pattern: "padaria",
            patternType: .contains,
            categoryId: alimentacao,
            priority: 5,
            createdBy: .user
        ))
        _ = try await ruleRepo.insert(CategorizationRule(
            name: "System: UBER",
            pattern: "uber",
            patternType: .contains,
            categoryId: alimentacao,
            priority: 10,
            createdBy: .system
        ))

        let userRules = try await ruleRepo.enabled(by: .user)
        let systemRules = try await ruleRepo.enabled(by: .system)
        XCTAssertEqual(userRules.count, 1)
        XCTAssertEqual(systemRules.count, 1)
        XCTAssertEqual(userRules.first?.pattern, "padaria")
        XCTAssertEqual(systemRules.first?.pattern, "uber")
    }

    func testCategorizationRule_OrderedByPriorityDesc() async throws {
        let store = try makeStore()
        try DefaultDataSeeder.seed(into: store)
        let ruleRepo = CategorizationRuleRepository(store: store)
        let alimentacao = try await CategoryRepository(store: store).all()
            .first { $0.name == "Alimentação" }!.id!

        _ = try await ruleRepo.insert(CategorizationRule(
            name: "low", pattern: "a", patternType: .contains,
            categoryId: alimentacao, priority: 1, createdBy: .user
        ))
        _ = try await ruleRepo.insert(CategorizationRule(
            name: "high", pattern: "b", patternType: .contains,
            categoryId: alimentacao, priority: 100, createdBy: .user
        ))

        let rules = try await ruleRepo.enabled(by: .user)
        XCTAssertEqual(rules.first?.priority, 100, "highest priority must come first")
    }

    func testCategorizationRule_DisabledExcluded() async throws {
        let store = try makeStore()
        try DefaultDataSeeder.seed(into: store)
        let ruleRepo = CategorizationRuleRepository(store: store)
        let alimentacao = try await CategoryRepository(store: store).all()
            .first { $0.name == "Alimentação" }!.id!

        _ = try await ruleRepo.insert(CategorizationRule(
            name: "off", pattern: "x", patternType: .contains,
            categoryId: alimentacao, createdBy: .user, enabled: false
        ))
        let rules = try await ruleRepo.enabled(by: .user)
        XCTAssertTrue(rules.isEmpty)
    }

    // MARK: - UserCorrectionRepository

    func testUserCorrection_InsertAndFetch() async throws {
        let store = try makeStore()
        try DefaultDataSeeder.seed(into: store)
        let categories = try await CategoryRepository(store: store).all()
        let from = categories[0].id!
        let to = categories[1].id!

        // Need a transaction to FK against.
        let acctRepo = AccountRepository(store: store)
        let cardRepo = CardRepository(store: store)
        let batchRepo = ImportBatchRepository(store: store)
        let txRepo = TransactionRepository(store: store)
        let acct = try await acctRepo.findOrCreate(bankName: "Itaú", holderName: "L")
        let card = try await cardRepo.upsert(Card(last4: "0001", holderName: "L"), accountId: acct.id!)
        let batch = try await batchRepo.insert(ImportBatch(
            sourceFileName: "x.pdf", sourceFileSha256: "shaA", sourcePages: 1,
            statementTotal: Money(major: 0, currency: .BRL),
            llmProvider: .mock, llmModel: "m", llmPromptVersion: "v1",
            llmInputTokens: 0, llmOutputTokens: 0, llmCostUSD: 0,
            validationStatus: .ok
        ))
        let tx = try await txRepo.insert(
            Transaction(
                postedDate: Date(timeIntervalSince1970: 0),
                rawDescription: "x", merchantNormalized: "x",
                amount: Money(major: 1, currency: .BRL)
            ),
            fingerprint: "fpA",
            importBatchId: batch.id!, cardId: card.id!, merchantId: nil
        )

        let correctionRepo = UserCorrectionRepository(store: store)
        _ = try await correctionRepo.insert(UserCorrection(
            transactionId: tx.id!,
            oldCategoryId: from,
            newCategoryId: to,
            correctionType: .category
        ))
        let corrections = try await correctionRepo.forTransaction(tx.id!)
        XCTAssertEqual(corrections.count, 1)
        XCTAssertEqual(corrections.first?.newCategoryId, to)
    }

    // MARK: - BankCategoryMappingRepository

    func testBankCategoryMapping_IssuerSpecificBeatsWildcard() async throws {
        // Don't seed — we want a clean mapping table to control rows directly.
        let store = try makeStore()

        // Need categories to FK against; seed only those.
        let categoryRepo = CategoryRepository(store: store)
        let now = Date()
        for seed in DefaultCategories.all {
            _ = try await categoryRepo.insert(Domain.Category(
                name: seed.name, color: seed.color, icon: seed.icon,
                createdAt: now, updatedAt: now
            ))
        }
        let cats = try await CategoryRepository(store: store).all()
        let groceries = cats.first { $0.name == "Alimentação" }!.id!
        let other = cats.first { $0.name == "Outros" }!.id!

        let repo = BankCategoryMappingRepository(store: store)
        // Wildcard row.
        _ = try await repo.insert(BankCategoryMapping(
            bankName: nil,
            bankCategoryRaw: "alimentação",
            categoryId: other
        ))
        // Issuer-specific row should win.
        _ = try await repo.insert(BankCategoryMapping(
            bankName: "Itaú",
            bankCategoryRaw: "alimentação",
            categoryId: groceries
        ))

        let hit = try await repo.find(bankName: "Itaú", bankCategoryRaw: "ALIMENTAÇÃO")
        XCTAssertEqual(hit?.categoryId, groceries, "issuer-specific row must beat wildcard")

        let wildcardOnly = try await repo.find(bankName: "BancoOutro", bankCategoryRaw: "alimentação")
        XCTAssertEqual(wildcardOnly?.categoryId, other, "wildcard row applies when issuer doesn't match")

        let missing = try await repo.find(bankName: "Itaú", bankCategoryRaw: "doesnotexist")
        XCTAssertNil(missing)
    }

    func testBankCategoryMapping_SeederPopulatesDefaults() async throws {
        let store = try makeStore()
        try DefaultDataSeeder.seed(into: store)
        let repo = BankCategoryMappingRepository(store: store)
        let all = try await repo.all()
        XCTAssertFalse(all.isEmpty, "seeder must populate default mappings")
        XCTAssertEqual(all.count, DefaultBankCategoryMappings.all.count)

        // ALIMENTAÇÃO must resolve to Alimentação.
        let cats = try await CategoryRepository(store: store).all()
        let alimentacaoId = cats.first { $0.name == "Alimentação" }!.id!
        let hit = try await repo.find(bankName: "Itaú", bankCategoryRaw: "alimentação")
        XCTAssertEqual(hit?.categoryId, alimentacaoId)
    }

    func testBankCategoryMapping_SeederIdempotent() async throws {
        let store = try makeStore()
        try DefaultDataSeeder.seed(into: store)
        try DefaultDataSeeder.seed(into: store)
        try DefaultDataSeeder.seed(into: store)
        let repo = BankCategoryMappingRepository(store: store)
        let all = try await repo.all()
        XCTAssertEqual(all.count, DefaultBankCategoryMappings.all.count,
                       "running the seeder repeatedly must not duplicate rows")
    }
}
