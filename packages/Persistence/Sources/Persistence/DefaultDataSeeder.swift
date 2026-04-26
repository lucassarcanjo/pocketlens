import Foundation
import GRDB
import Domain

/// Seeds first-run defaults: spec §19 categories. Idempotent — safe to call
/// on every app launch.
public enum DefaultDataSeeder {

    public static func seed(into store: SQLiteStore) throws {
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
}
