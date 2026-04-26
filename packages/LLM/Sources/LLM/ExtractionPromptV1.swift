import Foundation

/// The v1 extraction prompt + tool schema sent to the LLM provider.
///
/// **Versioning is load-bearing.** `version` is stamped onto every
/// `ImportBatch.llmPromptVersion`. Bumping the version is the signal that
/// historical batches may not reproduce byte-for-byte. Edit the prompt
/// contents, bump the version, and refresh the snapshot test in one PR.
public enum ExtractionPromptV1 {
    public static let version = "v1"

    /// Single-tool name forced by `tool_choice`. The schema below mirrors
    /// `ExtractedStatement`.
    public static let toolName = "record_extracted_statement"

    public static let toolDescription = """
    Records the structured contents of a credit-card statement PDF that the \
    user has just provided. You MUST call this tool exactly once with the \
    full extracted statement. Do NOT include marketing text, simulation \
    tables, or the forecast section ("Compras parceladas - próximas faturas").
    """

    public static let systemPrompt: String = """
    You are a careful financial-statement parser for PocketLens, a personal
    finance app. Your single job is to read the redacted text of a Brazilian
    credit-card statement and emit a structured record by calling the tool
    `record_extracted_statement` exactly once.

    Output discipline:
    - Never narrate. Never write prose. Call the tool with structured JSON.
    - Never include lines from the forecast section ("Compras parceladas -
      próximas faturas"), simulation tables ("Simulação de Compras parc. c/
      juros…", "Simulação Saque Cash"), or marketing/legal boilerplate.
    - Include EVERY transaction from the current period: national, international,
      IOF lines, fees, payments, refunds.

    Multi-card grouping:
    - One statement may contain multiple cards. List each card in `cards` with
      its `last4`, `holder_name`, and printed `subtotal` ("Lançamentos no
      cartão (final XXXX) <amount>").
    - Each transaction MUST reference its card via `card_last4`.

    Year inference:
    - Statements print only DD/MM. Compute the year from the statement
      `period_end` (closing date).
    - For installment lines marked "current/total", the original purchase
      occurred `(total - current)` months before the closing month. Use that
      to set the correct year for the `posted_date`.
    - Set `posted_year_inferred = true` whenever the source line did not
      print an explicit year.

    Installments:
    - If the merchant string ends with `N/M` (e.g. `06/10`), set
      `installment_current = N`, `installment_total = M`. The line `amount`
      is the per-installment amount, NOT the total purchase price. Strip the
      `N/M` suffix from the `merchant` field but keep it in `raw_description`.

    International transactions:
    - Lines under "Lançamentos internacionais" carry an original-currency
      amount, an FX rate, and a BRL-converted amount. Populate
      `original_amount` + `original_currency` + `fx_rate`. The BRL-converted
      amount goes in `amount` with `currency = "BRL"`.
    - "Repasse de IOF" is its own row with `transaction_type = "iof"`. Do not
      fold IOF into purchase amounts.

    Purchase method (best-effort):
    - `@` glyph prefix on a line ⇒ `virtual_card`.
    - "Compra com carteira digital" / wallet glyph ⇒ `digital_wallet`.
    - Recurring/subscription markers ⇒ `recurring`.
    - Otherwise ⇒ `physical`. If you cannot tell, emit `unknown` rather than
      guessing.

    Confidence:
    - For each transaction, emit a `confidence` in [0, 1] reflecting how
      certain you are about the row. <0.7 means the importer should flag
      this row for human review.

    Numeric format:
    - Source amounts use Brazilian convention: `7.473,18` is seven thousand
      four hundred seventy-three reais and eighteen centavos. Emit numbers
      as JSON numbers (`7473.18`), never as locale-formatted strings.
    """

    /// JSON-Schema for the `record_extracted_statement` tool. Sent to the
    /// provider as part of the request. Keep this in sync with
    /// `ExtractedStatement` — the snapshot test will catch drift.
    public static let toolSchemaJSON: String = #"""
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["statement", "cards", "transactions", "warnings"],
      "properties": {
        "statement": {
          "type": "object",
          "additionalProperties": false,
          "required": ["issuer", "currency", "totals"],
          "properties": {
            "issuer":        { "type": "string" },
            "product":       { "type": "string" },
            "period_start":  { "type": "string", "description": "ISO date YYYY-MM-DD" },
            "period_end":    { "type": "string", "description": "ISO date YYYY-MM-DD; closing date" },
            "due_date":      { "type": "string", "description": "ISO date YYYY-MM-DD" },
            "currency":      { "type": "string", "enum": ["BRL","USD","EUR","GBP"] },
            "totals": {
              "type": "object",
              "additionalProperties": false,
              "required": ["current_charges_total"],
              "properties": {
                "previous_balance":      { "type": "number" },
                "payment_received":      { "type": "number" },
                "revolving_balance":     { "type": "number" },
                "current_charges_total": { "type": "number" }
              }
            }
          }
        },
        "cards": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["last4", "holder_name", "subtotal"],
            "properties": {
              "last4":       { "type": "string", "minLength": 4, "maxLength": 4 },
              "holder_name": { "type": "string" },
              "network":     { "type": "string" },
              "tier":        { "type": "string" },
              "subtotal":    { "type": "number" }
            }
          }
        },
        "transactions": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": [
              "card_last4", "posted_date", "posted_year_inferred",
              "raw_description", "merchant", "amount", "currency",
              "purchase_method", "transaction_type", "confidence"
            ],
            "properties": {
              "card_last4":           { "type": "string", "minLength": 4, "maxLength": 4 },
              "posted_date":          { "type": "string", "description": "ISO date YYYY-MM-DD" },
              "posted_year_inferred": { "type": "boolean" },
              "raw_description":      { "type": "string" },
              "merchant":             { "type": "string" },
              "merchant_city":        { "type": "string" },
              "bank_category_raw":    { "type": "string" },
              "amount":               { "type": "number" },
              "currency":             { "type": "string", "enum": ["BRL","USD","EUR","GBP"] },
              "original_amount":      { "type": "number" },
              "original_currency":    { "type": "string", "enum": ["BRL","USD","EUR","GBP"] },
              "fx_rate":              { "type": "number" },
              "installment_current":  { "type": "integer", "minimum": 1 },
              "installment_total":    { "type": "integer", "minimum": 1 },
              "purchase_method":      { "type": "string", "enum": ["physical","virtual_card","digital_wallet","recurring","unknown"] },
              "transaction_type":     { "type": "string", "enum": ["purchase","refund","payment","fee","iof","adjustment"] },
              "confidence":           { "type": "number", "minimum": 0, "maximum": 1 }
            }
          }
        },
        "warnings": {
          "type": "array",
          "items": { "type": "string" }
        }
      }
    }
    """#
}
