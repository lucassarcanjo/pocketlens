# Privacy

PocketLens is **local-first**. Financial data never leaves your Mac unless you explicitly enable a cloud LLM provider.

## Data Locations

| Artifact | Location |
|---|---|
| SQLite database | `~/Library/Application Support/PocketLens/pocketlens.db` |
| Imported statement files | Not stored by the app. Files are read once and kept only in their original location. |
| API keys (if configured) | macOS Keychain — never on disk in plaintext, never in the DB. |
| App preferences | `UserDefaults` (watched folders, privacy mode, etc.) |
| Logs | `os.Logger` — visible via `Console.app`. No financial data in logs. |

## Privacy Modes

Spec §13.3. Set in Settings → Privacy.

| Mode | Network | Data sent to providers |
|---|---|---|
| **No LLM** (default) | None | Nothing. Ever. |
| **Local LLM** | HTTP to user-configured Ollama endpoint (typically `localhost:11434`) | Transaction summaries — only to the local endpoint. |
| **Cloud LLM** | HTTPS to OpenAI or Anthropic | Transaction summaries via the user's API key, after explicit consent. |

Mode is selectable per feature (categorization, monthly explanation) — the user can enable Cloud for monthly summaries while keeping categorization on "No LLM", for instance. Default for everything is off.

## What Gets Sent (Cloud Mode)

When Cloud LLM is enabled, a consent dialog shows the **exact payload** before first use. The `DataRedactor` strips:

- Account numbers.
- Full card numbers (last-4 is preserved if useful for context).
- Person names.
- Statement-level totals and balances (these reveal more than the per-transaction data needed for categorization).

Full PDF files are **never** sent. Raw `description_raw` is sent only if a user opts in; default is `description_normalized`.

## API Key Handling

- Keys are written to macOS Keychain via `Security.framework`.
- The `LLM` package's Keychain wrapper is the only code path that touches keys.
- Keys are **never** logged, even in debug builds.
- Users can rotate and delete keys from Settings.

## Telemetry

There is none. PocketLens has zero first-party analytics or crash reporting. If you hit a bug, export logs from `Console.app` and file an issue.

## Open-Source Transparency

All prompts sent to LLM providers are defined in `packages/LLM/Sources/LLM/PromptBuilder.swift` — a single file you can read to know exactly what leaves your machine. Snapshot tests lock down the exact prompt text.

## User Controls

- **Revoke consent** — toggle Privacy Mode back to "No LLM" anytime. No residual state on cloud providers beyond what they already retain under their own data policies.
- **Delete data** — the SQLite file can be deleted; `~/Library/Application Support/PocketLens/` can be removed entirely. The app will create a fresh database on next launch.
- **Export** — Settings → Backup/Export (planned for Phase 1 or 2) produces a CSV/JSON snapshot you can take elsewhere.

## Sandboxing

PocketLens ships with App Sandbox enabled:

- `com.apple.security.app-sandbox` = true
- `com.apple.security.files.user-selected.read-only` = true (drag-and-drop / file picker)
- No outbound-network entitlement in "No LLM" mode — added dynamically or at build-time for LLM providers.

Phase 6's folder-watching feature will require security-scoped bookmarks for any user-chosen watched folder outside the sandbox container.
