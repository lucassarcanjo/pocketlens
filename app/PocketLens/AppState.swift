import Foundation
import SwiftUI
import Domain
import Persistence
import Importing
import LLM

/// Top-level state object the SwiftUI scene observes. Owns the SQLite store,
/// the active LLM provider, and the user's onboarding/api-key state.
///
/// Single instance per app launch — wired up in `PocketLensApp` and injected
/// into the environment so the view hierarchy can mutate it without prop
/// drilling.
@MainActor
final class AppState: ObservableObject {

    /// Settings UI exposes this as a picker. Default per plan: Sonnet 4.6.
    @AppStorage("pocketlens.llmModel") var llmModel: String = "claude-sonnet-4-6"

    @Published var store: SQLiteStore?
    @Published var startupError: String?

    @Published var apiKey: String?         // Anthropic
    @Published var mistralAPIKey: String?  // Mistral OCR
    @Published var hasCompletedOnboarding: Bool = false

    let anthropicKeychain = KeychainStore.anthropic
    let mistralKeychain   = KeychainStore.mistral

    init() {
        bootstrap()
    }

    func bootstrap() {
        do {
            let store = try SQLiteStore.openDefault()
            self.store = store
        } catch {
            self.startupError = "Failed to open database: \(error.localizedDescription)"
            return
        }
        self.apiKey        = (try? anthropicKeychain.read()) ?? nil
        self.mistralAPIKey = (try? mistralKeychain.read()) ?? nil
        recomputeOnboarding()
    }

    func saveAPIKey(_ value: String) throws {
        try anthropicKeychain.write(value)
        apiKey = value
        recomputeOnboarding()
    }

    func clearAPIKey() throws {
        try anthropicKeychain.delete()
        apiKey = nil
        recomputeOnboarding()
    }

    func saveMistralAPIKey(_ value: String) throws {
        try mistralKeychain.write(value)
        mistralAPIKey = value
        recomputeOnboarding()
    }

    func clearMistralAPIKey() throws {
        try mistralKeychain.delete()
        mistralAPIKey = nil
        recomputeOnboarding()
    }

    private func recomputeOnboarding() {
        let hasAnthropic = (apiKey?.isEmpty == false)
        let hasMistral   = (mistralAPIKey?.isEmpty == false)
        hasCompletedOnboarding = hasAnthropic && hasMistral
    }

    func makeProvider() -> (any LLMProvider)? {
        guard let key = apiKey, !key.isEmpty else { return nil }
        return AnthropicProvider(apiKey: key, model: llmModel)
    }

    func makeOCR() -> MistralOCRClient? {
        guard let key = mistralAPIKey, !key.isEmpty else { return nil }
        return MistralOCRClient(apiKey: key)
    }

    /// Hard reset — wipes the on-disk database. Settings UI confirms.
    func resetDatabase() throws {
        let url = try SQLiteStore.defaultURL()
        // Close current handle by dropping the reference, then remove.
        self.store = nil
        try? FileManager.default.removeItem(at: url)
        // Also remove WAL/SHM siblings.
        let wal = url.appendingPathExtension("wal-journal")
        let shm = url.appendingPathExtension("shm")
        try? FileManager.default.removeItem(at: wal)
        try? FileManager.default.removeItem(at: shm)
        bootstrap()
    }
}
