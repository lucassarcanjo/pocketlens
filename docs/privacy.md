# Privacy

PocketLens is an open-source, locally stored personal-finance app whose **import path is built on a cloud LLM**. Statement extraction depends on it. There is no non-LLM operating mode and no manual-entry fallback. **If you do not want your statement text sent to a third-party LLM, this app is not for you.**

This document is the honest, plain-language description of what crosses the network and what doesn't.

## TL;DR

- **Storage is local.** SQLite database in `~/Library/Application Support/PocketLens/`. No cloud sync.
- **Statement extraction sends redacted PDF text to your configured LLM provider.** v0.1: Anthropic Claude. v0.5+: also OpenAI or a local Ollama instance, your pick.
- **Pre-LLM redaction strips** full card numbers (last-4 retained), CPF/CNPJ, and street addresses.
- **Telemetry: zero.** No analytics, no crash reporting.
- **API keys: macOS Keychain.** Never on disk in plaintext, never in the database.

## Disclosure model: low friction, two surfaces

We don't ask "send to Anthropic? [yes/no]" on every import. That model creates dialog fatigue, doesn't actually inform anyone, and conflicts with what the app fundamentally does. Instead:

1. **First-launch onboarding** — one-line disclosure shown next to the API-key paste field:
   > PocketLens uses Anthropic Claude to read your statement PDFs. Your data is sent to Anthropic but is **not used for training**. Full card numbers, CPF, and addresses are redacted before upload.

   Plus a "Learn more" link to this document.

2. **Drop-zone inline disclosure** — every time you go to import, the drop zone reads:
   > Drop a PDF here. By uploading, you agree to send the redacted text to **Anthropic Claude** (not used for training).

   The provider name updates if you switch to OpenAI or Ollama.

The act of uploading the file *is* the consent. Setting the app up is the informed-consent moment.

## Privacy model & provider choice

| Provider | Status | Where data goes |
|---|---|---|
| **Anthropic Claude** — default in v0.1 | Phase 1 | HTTPS to `api.anthropic.com` |
| **OpenAI** | Phase 5 | HTTPS to `api.openai.com` |
| **Ollama** (local) | Phase 5 | HTTP to `localhost:11434` (or your configured endpoint) — stays on your machine |

Switching to Ollama is how a privacy-sensitive user keeps everything local. There is no "disable LLM entirely and still use the app" mode — without an LLM there's no extraction.

## What gets sent

The `Redactor` runs before any HTTP call and strips:

- Full card numbers (`1234.5678.9012.3456` → `XXXX.XXXX.XXXX.3456`).
- CPF (`123.456.789-00`) and CNPJ patterns.
- Street address lines (city + state are kept — categorization needs them).

What's still sent: redacted statement text, page-by-page. That includes merchant names, transaction amounts, dates, the issuer's category labels, and the holder names that appear in section headers (e.g., "JOHN A DOE (final 1111)"). The redaction list is pluggable — file an issue if you want stricter rules.

What's never sent: the SQLite database, prior transactions, your API key for any service other than the one being called, OS-level identifiers.

## What gets sent (Categorization & Summary — Phase 2+)

Categorization assist sends a single transaction's normalized description + the user's category list + up to 5 recent (description, category) pairs. **No statement-level data, no unrelated transactions.**

Monthly summary sends aggregates only — per-category totals, top merchants, largest N transaction descriptions. **No raw rows, no card numbers.**

## "Not used for training"

Anthropic's API terms state that data sent to the API is not used to train their models by default. PocketLens makes no other warranty on third-party providers' retention or processing — read each provider's data policy. We surface the "not used for training" line because that's the practical promise users care about; we link to the actual provider terms in Settings.

## Data locations

| Artifact | Location |
|---|---|
| SQLite database | `~/Library/Application Support/PocketLens/pocketlens.db` (GRDB, WAL mode) |
| Imported PDFs | Not stored. The file is read once into memory, hashed, redacted, sent, and dropped. |
| API keys | macOS Keychain (`pocketlens.anthropic_api_key`, etc.). Reveal-on-click in Settings. |
| App preferences | `UserDefaults` (active provider, last-used model, watched folders) |
| Logs | `os.Logger`, visible in Console.app. Redacted statement text is **never** logged. |

## API key handling

- Stored via `Security.framework` with `kSecAttrAccessibleWhenUnlocked`.
- The `LLM` package's `KeychainStore` is the only code path that touches keys.
- Keys are never logged, even in debug builds.
- Settings → LLM → API Key supports rotate/delete; deleting wipes only that provider's entry.

## Open-source transparency

Every prompt sent to an LLM provider is a Swift constant in `packages/LLM/Sources/LLM/`. Prompt-snapshot tests guard against silent edits. To audit exactly what would leave your machine, read those files — there's no other code path.

## User controls

- **Switch to a local provider.** Phase 5 — pick Ollama in Settings; statement text never leaves your machine.
- **Delete data.** Quit the app and `rm -rf ~/Library/Application\ Support/PocketLens/`. The next launch creates a fresh database.
- **Export.** Settings → Backup/Export (Phase 2 or 3) produces a CSV/JSON snapshot.

## Sandboxing

The MVP currently ships with **App Sandbox disabled** (entitlements file is empty). Phase 6 (folder watcher) revisits sandboxing with security-scoped bookmarks for user-selected watched folders. Re-enabling requires explicit, tested entitlements for outbound networking and user-selected file reads.

## Telemetry

There is none. Zero first-party analytics or crash reporting. If you hit a bug, export logs from `Console.app` and file an issue.
