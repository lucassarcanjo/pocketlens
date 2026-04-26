import Foundation
import SwiftUI
import Domain
import Persistence
import Importing
import Categorization
import LLM

/// Drives the import-a-PDF flow: file picker → progress sheet → save.
/// Surfaces a phase string so the progress sheet can render
/// "extracting text → calling Claude → validating → saving".
@MainActor
final class ImportFlowController: ObservableObject {

    enum Phase: Equatable {
        case idle
        case extractingText
        case callingLLM
        case validating
        case categorizing
        case saving
        case done(transactionCount: Int)
        case error(String)

        var label: String {
            switch self {
            case .idle:                       return "Ready"
            case .extractingText:             return "Extracting text…"
            case .callingLLM:                 return "Calling Claude…"
            case .validating:                 return "Validating totals…"
            case .categorizing:               return "Categorizing transactions…"
            case .saving:                     return "Saving to database…"
            case .done(let n):                return "Imported \(n) transactions"
            case .error(let msg):             return "Failed: \(msg)"
            }
        }

        var isTerminal: Bool {
            switch self {
            case .done, .error: return true
            default:            return false
            }
        }
    }

    @Published var phase: Phase = .idle
    @Published var isRunning: Bool = false
    @Published var lastWarnings: [String] = []

    /// Entry point. Reads the URL, runs the pipeline, persists the plan.
    /// Caller (the view) reloads transactions on completion.
    func run(url: URL, app: AppState) async {
        guard let store = app.store else {
            phase = .error("Database isn't open.")
            return
        }
        guard let provider = app.makeProvider() else {
            phase = .error("Anthropic API key isn't set.")
            return
        }
        guard let ocr = app.makeOCR() else {
            phase = .error("Mistral API key isn't set.")
            return
        }

        isRunning = true
        defer { isRunning = false }

        do {
            phase = .extractingText
            let pipeline = ImportPipeline(provider: provider, ocr: ocr)
            let bankName = pipeline.defaultBankName

            phase = .callingLLM
            let rawPlan = try await pipeline.dryRun(url: url)

            phase = .validating
            // Pipeline already validated; if it failed catastrophically we'd
            // want to surface that. For Phase 1 we accept warnings and persist.

            phase = .categorizing
            let engine = CategorizationEngine.standard(store: store)
            let plan = try await engine.apply(to: rawPlan, bankName: bankName)

            phase = .saving
            let persister = ImportPersister(store: store)
            let result = try await persister.persist(
                plan: plan,
                bankName: bankName  // Phase 6 widens this when multi-bank lands.
            )
            self.lastWarnings = result.batch.parseWarnings
            self.phase = .done(transactionCount: result.transactionCount)
        } catch ImportPersister.Error.alreadyImported(let batch) {
            let date = batch.importedAt.formatted(date: .numeric, time: .omitted)
            self.phase = .error(
                "Already imported as batch #\(batch.id ?? 0) on \(date)."
            )
        } catch {
            self.phase = .error(error.localizedDescription)
        }
    }

    func dismiss() {
        if phase.isTerminal {
            phase = .idle
            lastWarnings = []
        }
    }
}
