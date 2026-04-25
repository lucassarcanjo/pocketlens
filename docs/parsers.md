# Parsers

PocketLens imports financial data by running a file through a **parser** that produces a `ParsedStatement` DTO — a neutral representation the rest of the pipeline can consume.

## Parser Contract

Every parser conforms to a small protocol (full signature lives in `packages/Importing/Sources/Importing/`):

```swift
protocol StatementParser {
    static var parserName: String { get }
    static var parserVersion: String { get }

    /// Given raw file bytes (or extracted PDF text), return a structured result.
    func parse(_ input: ParserInput) throws -> ParsedStatement
}
```

A `ParsedStatement` contains:

- A list of `ParsedTransaction` (date, raw description, amount, card last digits, installment info when present)
- Statement-level fields: period start/end, total, due date, card holder (when available)
- `ParserDiagnostics`: counts (transactions found, warnings) and any unrecognized sections

The parser does **NOT** normalize descriptions, dedupe, or assign categories. Those are separate concerns handled downstream. This keeps parsers testable with a single fixture-based assertion per bank.

## File Type Detection

`PDFImporter`, `CSVImporter`, and `OFXImporter` route by extension (and sniff the first bytes for safety). They then select the correct parser:

- **PDF credit card statements** → per-issuer parsers (e.g., `ItauInvoiceParser`) — the parser is chosen by inspecting the extracted text for an issuer signature (header string, logo OCR, etc.).
- **CSV** → `CSVImporter` with per-account column-mapping config.
- **OFX** → `OFXImporter` — structured format, single parser covers most banks.

## Fixtures

Each parser has a matching fixture pair:

```
fixtures/
├── statements/
│   └── itau-2025-11.pdf
└── expected-output/
    └── itau-2025-11.json
```

The JSON is the canonical expected output — a list of `ParsedTransaction` objects plus statement-level fields. Tests load the PDF, run the parser, and assert deep equality against the JSON.

**Rules for fixtures:**

- Real statements should be **anonymized** — replace names, card digits with obvious placeholders, keep the layout intact. An anonymization script belongs in `scripts/` (future).
- Add a new fixture for every parser bug fix. The fixture is the regression test.
- Commit only PDFs you're comfortable publishing under the repo's open-source license.

## Adding a New Parser

1. Create `packages/Importing/Sources/Importing/<Bank>InvoiceParser.swift`.
2. Implement `StatementParser`.
3. Add a fixture pair to `fixtures/`.
4. Add `<Bank>InvoiceParserTests.swift` that loads the fixture and asserts equality.
5. Register the parser in the importer's lookup table.
6. Update this doc's "Supported Parsers" list.

## Parser Diagnostics

Every import attempts to fill a `ParserDiagnostics` record that gets stored alongside the `ImportBatch`:

- Transactions found (before dedup)
- Transactions imported (after dedup)
- Duplicates skipped
- Rows failed to parse
- Warnings (e.g., "IOF line present but amount not captured")
- Unrecognized statement sections

This surfaces in the Imports screen, so users and contributors know immediately when a parser is weak on a given layout.

## Supported Parsers

| Bank / Source | Format | Package | Status |
|---|---|---|---|
| Itaú credit card | PDF | Importing | Planned (Phase 1) |
| CSV (generic, per-account mapping) | CSV | Importing | Planned (Phase 4) |
| OFX (generic) | OFX | Importing | Planned (Phase 4) |

This table gets updated as parsers land.
