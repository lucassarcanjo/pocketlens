import SwiftUI
import Domain
import Persistence

@MainActor
final class ImportsViewModel: ObservableObject {
    @Published var batches: [ImportBatch] = []
    @Published var loadError: String?

    func reload(store: SQLiteStore?) async {
        guard let store else { batches = []; return }
        do {
            self.batches = try await ImportBatchRepository(store: store).all()
            self.loadError = nil
        } catch {
            self.loadError = "Failed to load imports: \(error.localizedDescription)"
        }
    }
}

struct ImportsView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var vm = ImportsViewModel()

    var body: some View {
        VStack(alignment: .leading) {
            if let err = vm.loadError {
                Text(err).foregroundStyle(.orange)
            } else if vm.batches.isEmpty {
                Text("No imports yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(vm.batches) { batch in
                    BatchRow(batch: batch)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Imports")
        .task { await vm.reload(store: app.store) }
        .refreshable { await vm.reload(store: app.store) }
    }
}

private struct BatchRow: View {
    let batch: ImportBatch

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(batch.sourceFileName).font(.headline)
                Spacer()
                ValidationBadge(status: batch.validationStatus)
            }
            HStack(spacing: 16) {
                if let start = batch.statementPeriodStart, let end = batch.statementPeriodEnd {
                    Text("\(start.formatted(date: .numeric, time: .omitted)) — \(end.formatted(date: .numeric, time: .omitted))")
                }
                Text("Total: \(batch.statementTotal.formatted(locale: Locale(identifier: "pt_BR")))")
                Text("\(batch.sourcePages) pages")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Text("\(batch.llmProvider.rawValue) · \(batch.llmModel) · prompt \(batch.llmPromptVersion)")
                Text("\(batch.llmInputTokens + batch.llmOutputTokens) tokens · \(String(format: "$%.4f", batch.llmCostUSD))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if !batch.parseWarnings.isEmpty {
                DisclosureGroup("Warnings (\(batch.parseWarnings.count))") {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(batch.parseWarnings, id: \.self) { w in
                            Text("• \(w)").font(.caption)
                        }
                    }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ValidationBadge: View {
    let status: ValidationStatus

    var body: some View {
        Text(status.rawValue.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color, in: Capsule())
    }

    private var color: Color {
        switch status {
        case .ok:      return .green
        case .warning: return .orange
        case .failed:  return .red
        }
    }
}
