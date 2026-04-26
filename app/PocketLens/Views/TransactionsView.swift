import SwiftUI
import UniformTypeIdentifiers
import Domain
import Persistence

struct TransactionsView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var vm = TransactionsViewModel()
    @StateObject private var importer = ImportFlowController()

    @State private var showFileImporter = false
    @State private var isHovering = false

    var body: some View {
        ZStack {
            content
            if isHovering {
                ImportDropOverlay()
            }
        }
        .navigationTitle("Transactions")
        .toolbar {
            ToolbarItem {
                Button { showFileImporter = true } label: {
                    Label("Import", systemImage: "tray.and.arrow.down")
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { runImport(url) }
            case .failure(let err):
                importer.phase = .error(err.localizedDescription)
            }
        }
        .onDrop(of: [.fileURL, .pdf], isTargeted: $isHovering) { providers in
            handleDrop(providers: providers)
        }
        .onReceive(NotificationCenter.default.publisher(for: .importStatementRequested)) { _ in
            showFileImporter = true
        }
        .sheet(isPresented: importBinding) {
            ImportProgressSheet(controller: importer) { Task { await vm.reload(store: app.store) } }
        }
        .task { await vm.reload(store: app.store) }
    }

    private var importBinding: Binding<Bool> {
        Binding(
            get: { importer.isRunning || importer.phase.isTerminal && importer.phase != .idle },
            set: { _ in }
        )
    }

    @ViewBuilder
    private var content: some View {
        if !vm.hasLoaded {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.loadError {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28)).foregroundStyle(.orange)
                Text(err).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.rows.isEmpty {
            EmptyImportPrompt(showFileImporter: $showFileImporter)
        } else {
            transactionsList
        }
    }

    @State private var ruleEditorTransaction: Domain.Transaction?
    @State private var aliasEditorTransaction: Domain.Transaction?

    private var transactionsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                disclosureBanner
                ForEach(vm.grouped(), id: \.last4) { group in
                    CardSection(
                        last4: group.last4,
                        rows: group.rows,
                        categories: vm.categories,
                        onCategoryPicked: { tx, catId in
                            Task { await vm.updateCategory(
                                transactionId: tx.id ?? 0,
                                categoryId: catId,
                                store: app.store
                            ) }
                        },
                        onCreateRule: { tx in ruleEditorTransaction = tx },
                        onAddAlias: { tx in aliasEditorTransaction = tx }
                    )
                }
            }
            .padding(20)
        }
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

    private var disclosureBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
            Text("Drag a credit-card statement PDF anywhere here. By uploading, you agree to send the PDF to Mistral OCR and the redacted OCR text to Anthropic Claude — neither provider trains on your data.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func runImport(_ url: URL) {
        Task { await importer.run(url: url, app: app) }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, url.pathExtension.lowercased() == "pdf" else { return }
            Task { @MainActor in runImport(url) }
        }
        return true
    }
}

// MARK: - Sub-views

private struct EmptyImportPrompt: View {
    @Binding var showFileImporter: Bool
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text("Drop a credit-card statement PDF here")
                .font(.title2.weight(.semibold))
            Text("By uploading, you agree to send the PDF to Mistral OCR and the redacted OCR text to Anthropic Claude — neither provider trains on your data.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
            Button("Choose File…") { showFileImporter = true }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("o", modifiers: .command)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private struct ImportDropOverlay: View {
    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.08)
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 40))
                Text("Drop to import")
                    .font(.title2.weight(.semibold))
            }
            .padding(40)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .allowsHitTesting(false)
    }
}

private struct CardSection: View {
    let last4: String
    let rows: [TransactionsViewModel.Row]
    let categories: [Domain.Category]
    let onCategoryPicked: (Domain.Transaction, Int64?) -> Void
    let onCreateRule: (Domain.Transaction) -> Void
    let onAddAlias: (Domain.Transaction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "creditcard.fill")
                Text("Card •••• \(last4)")
                    .font(.headline)
                Spacer()
                Text("\(rows.count) transactions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    TransactionRowView(
                        row: row,
                        categories: categories,
                        onCategoryPicked: { catId in
                            onCategoryPicked(row.transaction, catId)
                        },
                        onCreateRule: { onCreateRule(row.transaction) },
                        onAddAlias: { onAddAlias(row.transaction) }
                    )
                    Divider()
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct TransactionRowView: View {
    let row: TransactionsViewModel.Row
    let categories: [Domain.Category]
    let onCategoryPicked: (Int64?) -> Void
    var onCreateRule: (() -> Void)? = nil
    var onAddAlias: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: methodIcon(row.transaction.purchaseMethod))
                        .foregroundStyle(.secondary)
                    Text(row.transaction.rawDescription)
                        .lineLimit(1)
                    if let inst = row.transaction.installment {
                        Text("\(inst.current)/\(inst.total)")
                            .font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.background.tertiary, in: Capsule())
                    }
                }
                HStack(spacing: 6) {
                    Text(row.transaction.postedDate.formatted(date: .numeric, time: .omitted))
                    if let city = row.transaction.merchantCity {
                        Text("· \(city)")
                    }
                    if let bank = row.transaction.bankCategoryRaw {
                        Text("· \(bank)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !row.transaction.categorizationReason.isEmpty {
                    CategorizationReasonBadge(
                        reasonKey: CategorizationReasonBadge.reason(
                            forExplanation: row.transaction.categorizationReason,
                            confidence: row.transaction.confidence
                        ),
                        explanation: row.transaction.categorizationReason,
                        confidence: row.transaction.confidence
                    )
                }
            }
            Spacer()
            Picker("", selection: pickerSelection) {
                Text("—").tag(Optional<Int64>.none)
                ForEach(categories) { cat in
                    Text(cat.name).tag(Optional(cat.id ?? 0))
                }
            }
            .labelsHidden()
            .frame(width: 160)

            Text(row.transaction.amount.formatted(locale: Locale(identifier: "pt_BR")))
                .font(.system(.body, design: .monospaced))
                .frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contextMenu {
            if let onCreateRule {
                Button("Create rule from this transaction…", systemImage: "plus.rectangle.on.folder") {
                    onCreateRule()
                }
            }
            if let onAddAlias {
                Button("Add merchant alias…", systemImage: "link.badge.plus") {
                    onAddAlias()
                }
            }
        }
    }

    private var pickerSelection: Binding<Int64?> {
        Binding(
            get: { row.transaction.categoryId },
            set: { onCategoryPicked($0) }
        )
    }

    private func methodIcon(_ m: PurchaseMethod) -> String {
        switch m {
        case .physical:      return "creditcard"
        case .virtualCard:   return "lock.shield"
        case .digitalWallet: return "wallet.pass"
        case .recurring:     return "repeat"
        case .unknown:       return "questionmark.circle"
        }
    }
}
