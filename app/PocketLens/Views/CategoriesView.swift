import SwiftUI
import Domain
import Persistence

@MainActor
final class CategoriesViewModel: ObservableObject {
    @Published var categories: [Domain.Category] = []
    @Published var loadError: String?

    func reload(store: SQLiteStore?) async {
        guard let store else { categories = []; return }
        do {
            self.categories = try await CategoryRepository(store: store).all()
            self.loadError = nil
        } catch {
            self.loadError = "Failed to load categories: \(error.localizedDescription)"
        }
    }
}

/// Read-only list in Phase 1. Full CRUD ships in Phase 2.
struct CategoriesView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var vm = CategoriesViewModel()

    var body: some View {
        VStack(alignment: .leading) {
            if let err = vm.loadError {
                Text(err).foregroundStyle(.orange)
            } else {
                List(vm.categories) { category in
                    HStack {
                        if let icon = category.icon {
                            Image(systemName: icon)
                                .foregroundStyle(category.color.flatMap(Color.init(hex:)) ?? .secondary)
                                .frame(width: 22)
                        }
                        Text(category.name)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text("Read-only in Phase 1 — editing lands in v0.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task { await vm.reload(store: app.store) }
    }
}

private extension Color {
    init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard trimmed.count == 6, let value = UInt64(trimmed, radix: 16) else { return nil }
        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >> 8)  / 255.0
        let b = Double( value & 0x0000FF)        / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}
