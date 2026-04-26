import SwiftUI
import LLM

/// First-launch onboarding. Single screen — disclosure + API key paste.
/// User cannot proceed without a non-empty key (per the plan: app refuses
/// to operate without one).
struct OnboardingView: View {
    @EnvironmentObject private var app: AppState

    @State private var anthropicDraft: String = ""
    @State private var mistralDraft: String = ""
    @State private var saveError: String?

    private var trimmedAnthropic: String {
        anthropicDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var trimmedMistral: String {
        mistralDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to PocketLens")
                    .font(.largeTitle.weight(.semibold))
                Text("Local-first personal finance for macOS.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Label("How it works", systemImage: "info.circle")
                    .font(.headline)
                Text(
                    "PocketLens reads your statement PDFs in two steps. "
                    + "**Mistral OCR** turns the PDF into text. **Anthropic Claude** extracts the structured data. "
                    + "Neither provider trains on your data. Full card numbers, CPF, and street addresses are "
                    + "redacted on-device before the OCR text reaches Claude."
                )
                .font(.body)
                .foregroundStyle(.primary)

                if let url = URL(string: "https://github.com/pocketlens/pocketlens/blob/main/docs/privacy.md") {
                    Link("Privacy details →", destination: url)
                        .font(.callout)
                }
            }
            .padding(16)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 8) {
                Text("Anthropic API key")
                    .font(.headline)
                Text("Paste your key from console.anthropic.com. Stored locally in macOS Keychain.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                SecureField("sk-ant-…", text: $anthropicDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 480)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Mistral API key")
                    .font(.headline)
                Text("Paste your key from console.mistral.ai. Used for OCR only. Stored locally in macOS Keychain.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                SecureField("…", text: $mistralDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 480)
                if let saveError {
                    Text(saveError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Spacer()
                Button("Continue") {
                    do {
                        try app.saveAPIKey(trimmedAnthropic)
                        try app.saveMistralAPIKey(trimmedMistral)
                    } catch {
                        saveError = "Couldn't store key in Keychain: \(error.localizedDescription)"
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedAnthropic.isEmpty || trimmedMistral.isEmpty)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}
