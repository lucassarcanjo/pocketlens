import SwiftUI
import LLM

struct SettingsView: View {
    @EnvironmentObject private var app: AppState

    @State private var anthropicDraft: String = ""
    @State private var revealAnthropic: Bool = false
    @State private var anthropicStatus: String?

    @State private var mistralDraft: String = ""
    @State private var revealMistral: Bool = false
    @State private var mistralStatus: String?

    @State private var showResetConfirm = false

    private let availableModels = [
        "claude-haiku-4-5-20251001",
        "claude-sonnet-4-6",
        "claude-opus-4-7",
    ]

    var body: some View {
        Form {
            Section("Anthropic API key") {
                HStack {
                    if revealAnthropic {
                        TextField("sk-ant-…", text: $anthropicDraft).textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("sk-ant-…", text: $anthropicDraft).textFieldStyle(.roundedBorder)
                    }
                    Button(revealAnthropic ? "Hide" : "Reveal") { revealAnthropic.toggle() }
                }
                HStack {
                    Button("Save") {
                        do {
                            try app.saveAPIKey(anthropicDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                            anthropicStatus = "Saved."
                        } catch {
                            anthropicStatus = "Failed: \(error.localizedDescription)"
                        }
                    }
                    .disabled(anthropicDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Forget key", role: .destructive) {
                        try? app.clearAPIKey()
                        anthropicDraft = ""
                        anthropicStatus = "Removed."
                    }

                    if let anthropicStatus { Text(anthropicStatus).foregroundStyle(.secondary) }
                }
                Text("Stored in macOS Keychain (`pocketlens.anthropic`).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Mistral API key (OCR)") {
                HStack {
                    if revealMistral {
                        TextField("…", text: $mistralDraft).textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("…", text: $mistralDraft).textFieldStyle(.roundedBorder)
                    }
                    Button(revealMistral ? "Hide" : "Reveal") { revealMistral.toggle() }
                }
                HStack {
                    Button("Save") {
                        do {
                            try app.saveMistralAPIKey(mistralDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                            mistralStatus = "Saved."
                        } catch {
                            mistralStatus = "Failed: \(error.localizedDescription)"
                        }
                    }
                    .disabled(mistralDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Forget key", role: .destructive) {
                        try? app.clearMistralAPIKey()
                        mistralDraft = ""
                        mistralStatus = "Removed."
                    }

                    if let mistralStatus { Text(mistralStatus).foregroundStyle(.secondary) }
                }
                Text("Used to OCR statement PDFs into markdown before Claude extraction. Stored in `pocketlens.mistral`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Model") {
                Picker("Default model", selection: $app.llmModel) {
                    ForEach(availableModels, id: \.self) { Text($0).tag($0) }
                }
                Text("Haiku 4.5 is cheapest and fastest. Sonnet 4.6 is the default — balanced. Opus 4.7 is the most capable fallback when validation fails on hard statements.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                if let url = URL(string: "https://github.com/pocketlens/pocketlens/blob/main/docs/privacy.md") {
                    Link("docs/privacy.md →", destination: url)
                }
                Text("PocketLens is LLM-only by design. There is no non-LLM mode in v0.1; Phase 5 will add a local Ollama option.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Database") {
                Button("Reset Database…", role: .destructive) {
                    showResetConfirm = true
                }
                Text("Wipes all transactions, batches, and merchants. The seeded category list is restored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .alert("Reset PocketLens database?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                do { try app.resetDatabase() } catch { }
            }
        } message: {
            Text("This permanently deletes all imported statements and transactions. Your API key in Keychain is unaffected.")
        }
        .task {
            anthropicDraft = app.apiKey ?? ""
            mistralDraft   = app.mistralAPIKey ?? ""
        }
    }
}
