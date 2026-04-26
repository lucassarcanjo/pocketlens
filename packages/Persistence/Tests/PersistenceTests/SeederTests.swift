import XCTest
@testable import Persistence
import Domain

final class SeederTests: XCTestCase {

    func testSeedsCategoriesOnFirstRun() async throws {
        let store = try SQLiteStore.makeInMemory()
        try DefaultDataSeeder.seed(into: store)
        let repo = CategoryRepository(store: store)
        let cats = try await repo.all()
        XCTAssertEqual(cats.count, DefaultCategories.all.count)
        XCTAssertTrue(cats.contains { $0.name == "Alimentação" })
        XCTAssertTrue(cats.contains { $0.name == "Outros" })
    }

    func testSeederIsIdempotent() async throws {
        let store = try SQLiteStore.makeInMemory()
        try DefaultDataSeeder.seed(into: store)
        try DefaultDataSeeder.seed(into: store)
        try DefaultDataSeeder.seed(into: store)
        let repo = CategoryRepository(store: store)
        let count = try await repo.count()
        XCTAssertEqual(count, DefaultCategories.all.count)
    }
}
