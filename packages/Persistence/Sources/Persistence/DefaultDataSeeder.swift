import Foundation
import GRDB
import Domain

/// Seeds first-run defaults: spec §19 categories, plus Phase 2 bank-category
/// mappings (Itaú label → PocketLens category). Idempotent — safe to call
/// on every app launch. Each seeding step short-circuits if its target
/// table is non-empty, so re-running never duplicates rows.
public enum DefaultDataSeeder {

    public static func seed(into store: SQLiteStore) throws {
        try seedCategories(store: store)
        try seedBankCategoryMappings(store: store)
    }

    private static func seedCategories(store: SQLiteStore) throws {
        try store.queue.write { db in
            let count = try CategoryRecord.fetchCount(db)
            guard count == 0 else { return }
            let now = Date()
            for seed in DefaultCategories.all {
                let category = Domain.Category(
                    name: seed.name,
                    color: seed.color,
                    icon: seed.icon,
                    createdAt: now,
                    updatedAt: now
                )
                var rec = CategoryRecord(from: category)
                try rec.insert(db)
            }
        }
    }

    private static func seedBankCategoryMappings(store: SQLiteStore) throws {
        try store.queue.write { db in
            let count = try BankCategoryMappingRecord.fetchCount(db)
            guard count == 0 else { return }

            let categories = try CategoryRecord.fetchAll(db)
            let categoryIdByName: [String: Int64] = Dictionary(
                uniqueKeysWithValues: categories.compactMap { rec in
                    rec.id.map { (rec.name, $0) }
                }
            )

            let now = Date()
            for seed in DefaultBankCategoryMappings.all {
                guard let categoryId = categoryIdByName[seed.pocketLensCategory] else {
                    // Seed references a category we didn't seed — skip rather
                    // than crash. Only happens if the user customised
                    // `DefaultCategories.all` and the names diverged.
                    continue
                }
                let mapping = BankCategoryMapping(
                    bankName: seed.bankName,
                    bankCategoryRaw: seed.bankCategoryRaw,
                    categoryId: categoryId,
                    createdAt: now,
                    updatedAt: now
                )
                var rec = BankCategoryMappingRecord(from: mapping)
                try rec.insert(db)
            }
        }
    }
}
