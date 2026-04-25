# Statement Extraction

PocketLens does **not** ship per-bank parser classes. Statement extraction is LLM-driven: PDFKit pulls page-by-page text, a `Redactor` scrubs sensitive patterns, and the `LLMStatementExtractor` calls a configured `LLMProvider` (default: `AnthropicProvider`) with a strict tool-use schema. The provider returns a structured `ExtractedStatement` JSON the rest of the pipeline consumes.

This means adding support for a new bank/issuer is, in most cases, **adding a fixture** — not writing code.

## Why no per-bank parsers?

The original v0.1 design called for `ItauInvoiceParser`, `NubankParser`, etc. — one Swift class per bank. We chose against it after the first real fixture: the Itaú Personnalité PDF includes multi-card sections, installment lines, virtual-card and digital-wallet glyphs, international transactions with FX columns, and a forecast section that must be excluded. Encoding all of that as regexes is brittle, and every bank has its own quirks. An LLM with a strict schema does it more reliably, and the same code path covers every issuer.

## The contract

The single contract is the `ExtractedStatement` JSON schema (see [`llm-integration.md`](llm-integration.md)). Every provider must return data conforming to it. Validation is enforced two ways:

1. **Schema-side** — the LLM is constrained to the tool's JSON schema by the provider.
2. **Statement-side** — `ExtractionValidator` sums extracted transactions per card and overall, and asserts they match the totals **printed on the statement** (`Lançamentos no cartão (final XXXX)`, `Total dos lançamentos atuais`) within ±R$0.01.

Mismatches don't reject the import — they mark `ImportBatch.validation_status = warning` and surface diagnostics in the Imports view.

## File-type routing (v0.1)

| Extension | Path |
|---|---|
| `.pdf` | `PDFTextExtractor` → `LLMStatementExtractor` → `ExtractedStatement` |
| `.csv` (Phase 4) | `CSVImporter` with per-account column mapping → direct `Transaction` rows (no LLM) |
| `.ofx` (Phase 4) | `OFXImporter` (structured, single parser handles all banks) |

CSV/OFX deliberately bypass the LLM — they are already structured, sending them to a model would be wasteful and add latency.

## Fixtures

```
fixtures/
├── statements/
│   └── itau-personnalite-2026-03-private.pdf       # gitignored
└── expected-output/
    └── itau-personnalite-2026-03.json              # canonical ExtractedStatement
```

Each fixture pair drives one parser test:
1. Mock provider loads `expected-output/<name>.json` as its canned response.
2. Pipeline runs against `statements/<name>.pdf`.
3. Test asserts: file hash captured, transaction count matches, per-card subtotals validate, fingerprint dedup works.

**Naming:** `<bank>-<product>-<yyyy-mm>[-private].pdf`. The `-private.pdf` suffix is gitignored — use it for any statement you can't publish openly.

## Adding support for a new issuer

In most cases, just add a fixture pair. The LLM handles arbitrary layouts.

If the issuer has unusual quirks the model gets wrong (e.g., a non-Brazilian statement format, a custom installment encoding, or an oddly-named forecast section), add a small **prompt addendum** to `ExtractionPromptV1.swift` describing the quirk. Bump the prompt version constant if you change behavior on existing fixtures.

Workflow:

1. Anonymize a sample statement — replace names and card digits with placeholders, keep the layout intact. Or commit it as `<name>-private.pdf` (gitignored) for personal testing.
2. Drop the file in `fixtures/statements/`.
3. Run the import once against a real provider, eyeball the output, save the verified JSON to `fixtures/expected-output/<name>.json`. (Once verified, that file is canonical — diffs show drift.)
4. Add a test in `packages/Importing/Tests/ImportingTests/` that loads both files via `MockLLMProvider`.
5. If a prompt addendum was needed, document it in `llm-integration.md`.
6. Update the **Tested issuers** table below.

## Diagnostics

Every import populates `ImportBatch.parse_warnings: [String]` with notes such as:
- "Glyph for line 12 ambiguous — purchase_method set to unknown."
- "Per-card subtotal for card 2222 differs by R$ 0,02 from extracted sum."
- "1 transaction had confidence < 0.7 — flagged for review."

These appear in the Imports view alongside extraction metadata (model, tokens, cost, prompt version) so contributors can spot weak coverage at a glance.

## Tested issuers

| Issuer | Product | Fixture | Status |
|---|---|---|---|
| Itaú Personnalité | Mastercard Black | `itau-personnalite-2026-03-private.pdf` | Phase 1 reference |

This list grows as fixtures land.

## No manual fallback

PocketLens is LLM-only by design. There is no manual-entry form and no "no LLM" mode — extraction depends on a configured provider (Anthropic in v0.1; OpenAI or Ollama in v0.5+). If the call fails, the import fails and the batch is marked accordingly; the user can retry, switch providers, or fix the underlying issue. See [`privacy.md`](privacy.md) for the disclosure model.
