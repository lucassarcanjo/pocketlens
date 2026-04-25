# PocketLens

A local-first, open-source personal finance app for macOS. Drop a credit card statement in, see where your money went, keep everything on your Mac.

## Status

Early development. The v0.1 MVP (PDF credit card import → transaction table → manual categorization) is under active construction. See [`.claude-plans/00-OVERVIEW.md`](.claude-plans/00-OVERVIEW.md) for the phased roadmap.

## What It Is

- **Local-first.** Your financial data lives in a SQLite file on your Mac. No remote backend.
- **Private by default.** Nothing leaves your device unless you explicitly enable a cloud LLM provider.
- **Explainable.** Every categorized transaction shows why it got its category — user rule, merchant alias, keyword match, LLM suggestion, etc.
- **Open-source.** MIT licensed. The prompts sent to any LLM provider are in a single file you can read.

## What It Isn't (Yet)

- A full budgeting platform.
- A bank-integration tool (no Plaid, no Open Finance).
- An investment tracker.
- Available on mobile.

It answers: "Where did my money go this month?" — and little more, by design.

## Quickstart

Prerequisites: macOS 14+, Xcode 15+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
make gen
open app/PocketLens.xcodeproj
```

Build and run from Xcode, or `make build && make test` from the command line.

## Architecture

The app is a SwiftUI shell over five Swift Package Manager modules:

| Package | Purpose |
|---|---|
| `Domain` | Value types for Transaction, Merchant, Category, etc. |
| `Persistence` | SQLite store, migrations, repositories. |
| `Importing` | PDF/CSV/OFX importers + per-bank parsers. |
| `Categorization` | Priority-ordered engine: memory → alias → rule → similarity → LLM. |
| `LLM` | Optional provider abstraction (Ollama, OpenAI, Anthropic, mock). |

Full breakdown in [`docs/architecture.md`](docs/architecture.md).

## Documentation

- [Architecture](docs/architecture.md)
- [Data Model (SQLite schema)](docs/data-model.md)
- [Parsers & Fixtures](docs/parsers.md)
- [Categorization Priority & Confidence](docs/categorization.md)
- [Import Flow & Dedup](docs/import-flow.md)
- [Privacy Model](docs/privacy.md)
- [LLM Integration](docs/llm-integration.md)
- [Contributing](docs/contributing.md)

## Roadmap

| Version | Focus |
|---|---|
| v0.1 | PDF credit card import, transaction table, manual categorization |
| v0.2 | Local memory — rules, merchant aliases, confidence scoring |
| v0.3 | Dashboard — Swift Charts, spend by category, top merchants |
| v0.4 | Bank statements — CSV, OFX, cash flow |
| v0.5 | LLM assistance — Ollama, OpenAI, Anthropic (opt-in) |
| v0.6 | Automation — watched folder + Apple Mail rule flow |

Detailed phase plans live in [`.claude-plans/`](.claude-plans/).

## License

MIT. See [LICENSE](LICENSE).
