import SwiftUI
import Domain
import Persistence

/// Sheet for adding a `MerchantAlias`. Pre-fills with the transaction's
/// `merchantNormalized` so the user just confirms or trims.
///
/// Aliases are a substring fragment matched against future
/// `merchant_normalized` values; the merchant they alias to receives the
/// alias's category via its `default_category_id`.
struct MerchantAliasEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState

    let prefillFromTransaction: Domain.Transaction
    let onSaved: () -> Void

    @State private var alias: String = ""
    @State private var saveError: String?

    init(prefillFromTransaction: Domain.Transaction, onSaved: @escaping () -> Void) {
        self.prefillFromTransaction = prefillFromTransaction
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add merchant alias")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Form {
                Section("Alias fragment") {
                    TextField("e.g., uber *trip", text: $alias)
                        .help("Casefolded substring matched against merchant_normalized on future imports.")
                }

                Section("Anchor merchant") {
                    Text(prefillFromTransaction.merchantNormalized)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if let cat = prefillFromTransaction.categoryId {
                        Text("Will inherit the merchant's default category (id \(cat)).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label(
                            "This transaction has no category yet — alias will match but have nothing to assign until the merchant gets a default category.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
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
                Button("Add alias") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(alias.trimmingCharacters(in: .whitespaces).isEmpty
                              || prefillFromTransaction.merchantId == nil)
            }
            .padding(20)
        }
        .frame(width: 480)
        .onAppear {
            if alias.isEmpty {
                alias = prefillFromTransaction.merchantNormalized
            }
        }
    }

    private func save() async {
        guard
            let store = app.store,
            let merchantId = prefillFromTransaction.merchantId
        else { return }
        do {
            let repo = MerchantAliasRepository(store: store)
            _ = try await repo.insert(MerchantAlias(
                merchantId: merchantId,
                alias: alias.trimmingCharacters(in: .whitespaces).lowercased(),
                source: .user
            ))
            // Adopt the transaction's category as the merchant's default so the
            // alias has something to assign on future imports. Phase-1's
            // MerchantRepository.upsert preserves first-seen metadata, so we
            // write the FK directly via the dedicated repo method.
            if let categoryId = prefillFromTransaction.categoryId {
                try await MerchantRepository(store: store)
                    .setDefaultCategory(merchantId: merchantId, categoryId: categoryId)
            }
            onSaved()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
