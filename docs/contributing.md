# Contributing to PocketLens

Thanks for looking! PocketLens is an open-source, local-first macOS app. We welcome fixes, parsers for new banks, and dashboard ideas.

## Prerequisites

- macOS 14 Sonoma or later.
- Xcode 15 or later.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — install via Homebrew:
  ```sh
  brew install xcodegen
  ```

## First-Time Setup

```sh
git clone <repo-url>
cd pocketlens
make gen           # generates app/PocketLens.xcodeproj from project.yml
open app/PocketLens.xcodeproj
```

## Make Targets

| Command | What it does |
|---|---|
| `make gen` | Run `xcodegen generate` to produce `app/PocketLens.xcodeproj`. |
| `make build` | Build the app via `xcodebuild`. |
| `make test` | Run the app test target AND each SPM package's tests. |
| `make fmt` | Format Swift source (placeholder — swift-format config pending). |
| `make clean` | Remove build artifacts. |

## Repo Structure

```
pocketlens/
├── .claude-plans/         # Phased plan + session log (cross-session continuity)
├── docs/                  # Concept documentation (this file + friends)
├── app/
│   ├── project.yml        # XcodeGen spec — source of truth for the Xcode project
│   ├── PocketLens/        # SwiftUI app target (XcodeGen generates PocketLens.xcodeproj here)
│   └── PocketLensTests/   # XCTest target
├── packages/
│   ├── Domain/            # Pure value types: Transaction, Merchant, Category, …
│   ├── Persistence/       # SQLite store + migrations + repositories
│   ├── Importing/         # PDF/CSV/OFX importers + per-bank parsers
│   ├── Categorization/    # Rule engine, alias matcher, similarity, memory
│   └── LLM/               # Provider protocol + Mock/Ollama/OpenAI/Anthropic impls
├── fixtures/
│   ├── statements/        # Anonymized sample statements (PDF/CSV/OFX)
│   └── expected-output/   # Paired JSON for parser assertions
├── Makefile
├── README.md
├── LICENSE                # MIT
└── CONTRIBUTING.md
```

## Adding a Parser for a New Bank

1. Anonymize a statement — replace names, card digits with `XXXX`, keep the layout intact.
2. Drop it in `fixtures/statements/<bank>-<yyyy-mm>.pdf`.
3. Create the expected JSON in `fixtures/expected-output/<bank>-<yyyy-mm>.json`.
4. Implement `packages/Importing/Sources/Importing/<Bank>InvoiceParser.swift` conforming to `StatementParser`.
5. Add `<Bank>InvoiceParserTests.swift` in `packages/Importing/Tests/ImportingTests/`.
6. Register the parser in the importer lookup.
7. Update [`docs/parsers.md`](parsers.md) → "Supported Parsers" table.

## Test Fixture Guidelines

- Anonymize thoroughly. If you can't share a statement publicly, don't commit it — write a synthetic one instead.
- One fixture = one bank + one statement period. Small and focused.
- Bug fixes: add the reproducing fixture **before** fixing the parser. The test is the regression protection.

## Code Style

- Follow Apple's Swift API Design Guidelines.
- Prefer `struct` over `class`. Immutability by default. Protocol-oriented design.
- No force-unwraps (`!`) outside test code.
- Dependency injection at module boundaries — easier to test.
- Keep SwiftUI views small; move logic into view models or the feature packages.

## Commit Messages

Short imperative subject (≤ 72 chars), optional body. Examples:

- `Add ItauInvoiceParser for credit card PDFs`
- `Fix dedup edge case when installment info is missing`
- `Categorize: emit reason strings for all strategies`

## Pull Requests

- One feature or fix per PR.
- Update the relevant `.claude-plans/` phase file if you complete a task (check the box).
- Update the concept docs in `docs/` if you change behavior they describe.
- All tests green locally: `make test`.

## Privacy-Sensitive Changes

If your change touches any outbound data path (LLM providers, telemetry, export), please note it clearly in the PR. We err aggressively on the side of keeping data local. See [`docs/privacy.md`](privacy.md).

## Questions

Open a GitHub issue with the `question` label. For design discussions, reference the relevant phase file under `.claude-plans/`.
