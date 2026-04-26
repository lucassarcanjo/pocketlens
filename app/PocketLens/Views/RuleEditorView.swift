import SwiftUI
import Domain
import Persistence

/// Sheet for creating or editing a `CategorizationRule`. Can be opened from
/// the Rules list (blank) or pre-filled from a transaction's right-click
/// menu (the common path).
struct RuleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState

    let categories: [Domain.Category]
    /// Provided when opened from a transaction's "Create rule" action.
    let prefillFromTransaction: Domain.Transaction?
    /// Provided when editing an existing rule from the list.
    let editing: CategorizationRule?
    let onSaved: () -> Void

    // MARK: - Form state
    @State private var name: String = ""
    @State private var pattern: String = ""
    @State private var patternType: PatternType = .contains
    @State private var categoryId: Int64? = nil
    @State private var priority: Int = 0
    @State private var enabled: Bool = true

    @State private var saveError: String?

    init(
        prefillFromTransaction: Domain.Transaction? = nil,
        editing: CategorizationRule? = nil,
        categories: [Domain.Category],
        onSaved: @escaping () -> Void
    ) {
        self.prefillFromTransaction = prefillFromTransaction
        self.editing = editing
        self.categories = categories
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(editing == nil ? "Create rule" : "Edit rule")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Form {
                Section("Pattern") {
                    Picker("Type", selection: $patternType) {
                        Text("Contains").tag(PatternType.contains)
                        Text("Exact").tag(PatternType.exact)
                        Text("Regex").tag(PatternType.regex)
                        Text("Amount range (min..max in centavos)").tag(PatternType.amountRange)
                    }
                    TextField("Pattern", text: $pattern)
                        .help(patternHelp)
                }

                Section("Category") {
                    Picker("Category", selection: $categoryId) {
                        Text("—").tag(Optional<Int64>.none)
                        ForEach(categories) { cat in
                            Text(cat.name).tag(Optional(cat.id ?? 0))
                        }
                    }
                }

                Section("Settings") {
                    TextField("Name", text: $name)
                    Stepper("Priority: \(priority)", value: $priority, in: 0...1000)
                    Toggle("Enabled", isOn: $enabled)
                }

                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Create" : "Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding(20)
        }
        .frame(width: 520)
        .onAppear { applyPrefill() }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !pattern.trimmingCharacters(in: .whitespaces).isEmpty
            && categoryId != nil
    }

    private var patternHelp: String {
        switch patternType {
        case .contains:    return "Substring of merchant_normalized — case-insensitive."
        case .exact:       return "Exact match against merchant_normalized."
        case .regex:       return "Regex against merchant_normalized."
        case .merchant:    return "Equality against merchant id."
        case .amountRange: return "min..max in minor units (R$1.00 = 100). Use * for unbounded."
        }
    }

    private func applyPrefill() {
        if let r = editing {
            name = r.name
            pattern = r.pattern
            patternType = r.patternType
            categoryId = r.categoryId
            priority = r.priority
            enabled = r.enabled
            return
        }
        guard let tx = prefillFromTransaction else { return }
        name = "Auto: \(tx.merchantNormalized)"
        pattern = tx.merchantNormalized
        patternType = .contains
        categoryId = tx.categoryId
    }

    private func save() async {
        guard let store = app.store, let categoryId else { return }
        do {
            let repo = CategorizationRuleRepository(store: store)
            if let editing, let id = editing.id {
                var updated = editing
                updated.id = id
                updated.name = name
                updated.pattern = pattern
                updated.patternType = patternType
                updated.categoryId = categoryId
                updated.priority = priority
                updated.enabled = enabled
                _ = try await repo.update(updated)
            } else {
                _ = try await repo.insert(CategorizationRule(
                    name: name,
                    pattern: pattern,
                    patternType: patternType,
                    categoryId: categoryId,
                    priority: priority,
                    createdBy: .user,
                    enabled: enabled
                ))
            }
            onSaved()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
