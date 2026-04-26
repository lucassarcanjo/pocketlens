import Foundation

/// Maps an issuer's own category label (`transactions.bank_category_raw`)
/// to a PocketLens category. Drives priority slot 4 in the categorization
/// chain.
///
/// `bankName` is `nil` for the wildcard row that applies to any issuer; an
/// issuer-specific row beats the wildcard at lookup time. `bankCategoryRaw`
/// is stored casefolded so matching is a plain equality lookup.
public struct BankCategoryMapping: Hashable, Codable, Sendable, Identifiable {
    public var id: Int64?
    public var bankName: String?
    public var bankCategoryRaw: String
    public var categoryId: Int64
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        bankName: String?,
        bankCategoryRaw: String,
        categoryId: Int64,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.bankName = bankName
        self.bankCategoryRaw = bankCategoryRaw.lowercased()
        self.categoryId = categoryId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Default Itaú label → PocketLens category mapping seeded on first run.
///
/// Targets the default category set in `DefaultCategories.all` by name —
/// resolution to `categoryId` happens in `DefaultDataSeeder`. Source:
/// observed Itaú Personnalité statement labels (March 2026 fixture).
public enum DefaultBankCategoryMappings {
    public struct Seed: Sendable {
        public let bankName: String?
        public let bankCategoryRaw: String
        public let pocketLensCategory: String
        public init(
            bankName: String? = "Itaú",
            bankCategoryRaw: String,
            pocketLensCategory: String
        ) {
            self.bankName = bankName
            self.bankCategoryRaw = bankCategoryRaw
            self.pocketLensCategory = pocketLensCategory
        }
    }

    public static let all: [Seed] = [
        // Itaú Personnalité observed labels (statement March 2026).
        .init(bankCategoryRaw: "alimentação",            pocketLensCategory: "Alimentação"),
        .init(bankCategoryRaw: "alimentacao",            pocketLensCategory: "Alimentação"),
        .init(bankCategoryRaw: "supermercados",          pocketLensCategory: "Alimentação"),
        .init(bankCategoryRaw: "veículos",               pocketLensCategory: "Transporte"),
        .init(bankCategoryRaw: "veiculos",               pocketLensCategory: "Transporte"),
        .init(bankCategoryRaw: "transportes",            pocketLensCategory: "Transporte"),
        .init(bankCategoryRaw: "turismo e entretenim.",  pocketLensCategory: "Lazer"),
        .init(bankCategoryRaw: "turismo",                pocketLensCategory: "Viagens"),
        .init(bankCategoryRaw: "entretenimento",         pocketLensCategory: "Lazer"),
        .init(bankCategoryRaw: "vestuário",              pocketLensCategory: "Compras"),
        .init(bankCategoryRaw: "vestuario",              pocketLensCategory: "Compras"),
        .init(bankCategoryRaw: "saúde",                  pocketLensCategory: "Saúde"),
        .init(bankCategoryRaw: "saude",                  pocketLensCategory: "Saúde"),
        .init(bankCategoryRaw: "educação",               pocketLensCategory: "Educação"),
        .init(bankCategoryRaw: "educacao",               pocketLensCategory: "Educação"),
        .init(bankCategoryRaw: "serviços",               pocketLensCategory: "Serviços"),
        .init(bankCategoryRaw: "servicos",               pocketLensCategory: "Serviços"),
        .init(bankCategoryRaw: "casa",                   pocketLensCategory: "Moradia"),
        .init(bankCategoryRaw: "diversos",               pocketLensCategory: "Outros"),
    ]
}
