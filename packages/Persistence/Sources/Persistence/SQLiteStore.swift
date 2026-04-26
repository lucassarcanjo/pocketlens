import Foundation
import GRDB

/// Owns the SQLite connection. Single writer, single-window app — a
/// `DatabaseQueue` is simpler than a `DatabasePool` and matches Phase 1's
/// concurrency model (the import pipeline runs as one task).
public final class SQLiteStore: @unchecked Sendable {

    public let queue: DatabaseQueue

    /// Open or create the application's database at the standard location:
    /// `~/Library/Application Support/PocketLens/pocketlens.db`. Creates the
    /// containing directory if missing.
    public static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = support.appendingPathComponent("PocketLens", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("pocketlens.db")
    }

    public init(url: URL) throws {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        self.queue = try DatabaseQueue(path: url.path, configuration: config)
        try Migrations.migrator.migrate(queue)
    }

    /// In-memory store for tests + previews.
    public init(inMemory: Bool) throws {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        self.queue = try DatabaseQueue(configuration: config)
        try Migrations.migrator.migrate(queue)
    }

    /// Convenience for tests.
    public static func makeInMemory() throws -> SQLiteStore {
        try SQLiteStore(inMemory: true)
    }

    /// Convenience for app launch — opens the default location, runs
    /// migrations, then runs the seeder.
    public static func openDefault() throws -> SQLiteStore {
        let url = try defaultURL()
        let store = try SQLiteStore(url: url)
        try DefaultDataSeeder.seed(into: store)
        return store
    }
}
