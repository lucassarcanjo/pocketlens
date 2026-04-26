import Foundation

/// User-facing spending category. Hierarchical via `parentId`.
public struct Category: Hashable, Codable, Sendable, Identifiable {
    public var id: Int64?
    public var parentId: Int64?
    public var name: String
    public var color: String?
    public var icon: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        parentId: Int64? = nil,
        name: String,
        color: String? = nil,
        icon: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.parentId = parentId
        self.name = name
        self.color = color
        self.icon = icon
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Default category set seeded on first run (spec §19).
///
/// Order matters — the seeder writes them sequentially so user-facing IDs
/// stay stable across machines for users who haven't customised their list.
public enum DefaultCategories {
    public struct Seed: Sendable {
        public let name: String
        public let icon: String
        public let color: String
        public init(_ name: String, icon: String, color: String) {
            self.name = name
            self.icon = icon
            self.color = color
        }
    }

    public static let all: [Seed] = [
        .init("Alimentação",       icon: "fork.knife",                color: "#E5484D"),
        .init("Transporte",        icon: "car.fill",                  color: "#3E63DD"),
        .init("Moradia",           icon: "house.fill",                color: "#46A758"),
        .init("Saúde",             icon: "cross.case.fill",           color: "#F76808"),
        .init("Educação",          icon: "book.fill",                 color: "#7C66DC"),
        .init("Compras",           icon: "bag.fill",                  color: "#EAB308"),
        .init("Lazer",             icon: "gamecontroller.fill",       color: "#0EA5E9"),
        .init("Assinaturas",       icon: "rectangle.stack.fill",      color: "#A855F7"),
        .init("Viagens",           icon: "airplane",                  color: "#06B6D4"),
        .init("Serviços",          icon: "wrench.and.screwdriver",    color: "#84CC16"),
        .init("Impostos & Taxas",  icon: "doc.text.fill",             color: "#64748B"),
        .init("Outros",            icon: "questionmark.circle",       color: "#9CA3AF"),
    ]
}
