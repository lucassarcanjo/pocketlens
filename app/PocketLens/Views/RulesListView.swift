import SwiftUI
import Domain
import Persistence

/// CRUD list of `CategorizationRule`s, sectioned by source (user-created vs
/// system-seeded). The user can create from scratch, edit, toggle enabled,
/// or delete. System rules are read-only.
struct RulesListView: View {
    @EnvironmentObject private var app: AppState

    @State private var rules: [CategorizationRule] = []
    @State private var categories: [Domain.Category] = []
    @State private var loadError: String?

    @State private var creating = false
    @State private var editing: CategorizationRule?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Rules")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    creating = true
                } label: {
                    Label("New rule", systemImage: "plus")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            if let err = loadError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .padding()
                    .foregroundStyle(.orange)
            }

            List {
                Section("Your rules") {
                    let userRules = rules.filter { $0.createdBy == .user }
                    if userRules.isEmpty {
                        Text("No user rules yet. Right-click a transaction to create one.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(userRules, id: \.id) { rule in
                            row(rule, editable: true)
                        }
                    }
                }
                Section("System keyword rules") {
                    let systemRules = rules.filter { $0.createdBy == .system }
                    if systemRules.isEmpty {
                        Text("No system rules seeded.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(systemRules, id: \.id) { rule in
                            row(rule, editable: false)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .navigationTitle("Rules")
        .task { await reload() }
        .sheet(isPresented: $creating) {
            RuleEditorView(categories: categories) {
                Task { await reload() }
            }
        }
        .sheet(item: $editing) { rule in
            RuleEditorView(editing: rule, categories: categories) {
                Task { await reload() }
            }
        }
    }

    @ViewBuilder
    private func row(_ rule: CategorizationRule, editable: Bool) -> some View {
        let categoryName = categories.first { $0.id == rule.categoryId }?.name ?? "?"
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rule.name).font(.body.weight(.medium))
                    if !rule.enabled {
                        Text("disabled")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.background.tertiary, in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                Text("\(rule.patternType.rawValue): \(rule.pattern)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text("→ \(categoryName)  ·  priority \(rule.priority)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if editable {
                Button {
                    editing = rule
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                Button(role: .destructive) {
                    Task { await delete(rule) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private func reload() async {
        guard let store = app.store else { return }
        do {
            rules = try await CategorizationRuleRepository(store: store).all()
            categories = try await CategoryRepository(store: store).all()
            loadError = nil
        } catch {
            loadError = "Failed to load rules: \(error.localizedDescription)"
        }
    }

    private func delete(_ rule: CategorizationRule) async {
        guard let store = app.store, let id = rule.id else { return }
        do {
            try await CategorizationRuleRepository(store: store).delete(id: id)
            await reload()
        } catch {
            loadError = "Failed to delete rule: \(error.localizedDescription)"
        }
    }
}

