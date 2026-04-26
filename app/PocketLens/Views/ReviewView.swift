import SwiftUI
import Domain
import Persistence

/// Review queue. Surfaces transactions that need user attention:
/// - **Uncategorized** (`categoryId == nil`)
/// - **Low confidence** (< 0.50)
/// - **Needs review** (0.50 ≤ confidence < 0.80)
///
/// Filter pill at the top toggles between these. Each row supports the same
/// inline category picker + context-menu actions as the main Transactions
/// view.
struct ReviewView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case uncategorized
        case lowConfidence
        case needsReview
        case all

        var id: String { rawValue }
        var label: String {
            switch self {
            case .uncategorized: return "Uncategorized"
            case .lowConfidence: return "Low confidence"
            case .needsReview:   return "Needs review"
            case .all:           return "All flagged"
            }
        }
    }

    @EnvironmentObject private var app: AppState
    @StateObject private var vm = ReviewViewModel()

    @State private var filter: Filter
    @State private var ruleEditorTransaction: Domain.Transaction?
    @State private var aliasEditorTransaction: Domain.Transaction?

    /// `initialFilter` lets callers (e.g. the dashboard's attention cards)
    /// open this view pre-filtered. The parent must vary `.id(...)` to force
    /// re-init when the filter argument changes.
    init(initialFilter: Filter = .all) {
        _filter = State(initialValue: initialFilter)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { f in
                        Text(f.label).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 480)
                Spacer()
                Text("\(filteredRows.count) of \(vm.rows.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            if filteredRows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filteredRows) { row in
                            TransactionRowView(
                                row: row,
                                categories: vm.categories,
                                onCategoryPicked: { catId in
                                    Task { await vm.updateCategory(
                                        transactionId: row.transaction.id ?? 0,
                                        categoryId: catId,
                                        store: app.store
                                    ) }
                                },
                                onCreateRule: { ruleEditorTransaction = row.transaction },
                                onAddAlias: { aliasEditorTransaction = row.transaction }
                            )
                            Divider()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Review")
        .task { await vm.reload(store: app.store) }
        .sheet(item: $ruleEditorTransaction) { tx in
            RuleEditorView(prefillFromTransaction: tx, categories: vm.categories) {
                Task { await vm.reload(store: app.store) }
            }
        }
        .sheet(item: $aliasEditorTransaction) { tx in
            MerchantAliasEditorView(prefillFromTransaction: tx) {
                Task { await vm.reload(store: app.store) }
            }
        }
    }

    private var filteredRows: [TransactionsViewModel.Row] {
        vm.rows.filter { row in
            let tx = row.transaction
            switch filter {
            case .uncategorized:
                return tx.categoryId == nil
            case .lowConfidence:
                return tx.categoryId != nil && tx.confidence < 0.50
            case .needsReview:
                return tx.categoryId != nil
                    && tx.confidence >= 0.50 && tx.confidence < 0.80
            case .all:
                return tx.categoryId == nil || tx.confidence < 0.80
            }
        }
        .sorted { ($0.transaction.confidence) < ($1.transaction.confidence) }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("Nothing needs review.")
                .font(.title3.weight(.semibold))
            Text("Categories above 0.80 confidence are considered settled.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
