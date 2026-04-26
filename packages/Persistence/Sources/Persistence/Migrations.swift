import Foundation
import GRDB

/// Database migrations registry. Schema mirrors `docs/data-model.md` §"Schema v1".
///
/// Migrations are append-only — never edit a shipped migration; add a new one.
public enum Migrations {

    public static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        registerV1(&m)
        registerV2(&m)
        return m
    }

    private static func registerV1(_ m: inout DatabaseMigrator) {
        m.registerMigration("v1_phase1_schema") { db in

            // categories first — referenced by merchants and transactions.
            try db.create(table: "categories") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("parent_id", .integer)
                    .references("categories", onDelete: .setNull)
                t.column("color", .text)
                t.column("icon", .text)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }

            try db.create(table: "accounts") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("bank_name", .text).notNull()
                t.column("holder_name", .text).notNull()
                t.column("account_alias", .text)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }

            try db.create(table: "cards") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("account_id", .integer).notNull()
                    .references("accounts", onDelete: .cascade)
                t.column("last4", .text).notNull()
                t.column("holder_name", .text).notNull()
                t.column("network", .text)
                t.column("tier", .text)
                t.column("nickname", .text)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
                t.uniqueKey(["account_id", "last4"])
            }

            try db.create(table: "merchants") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("raw", .text).notNull()
                t.column("normalized", .text).notNull().unique()
                t.column("default_category_id", .integer)
                    .references("categories", onDelete: .setNull)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }

            try db.create(table: "import_batches") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("source_file_name", .text).notNull()
                t.column("source_file_sha256", .text).notNull().unique()
                t.column("source_pages", .integer).notNull()
                t.column("statement_period_start", .text)
                t.column("statement_period_end", .text)
                t.column("statement_close_date", .text)
                t.column("statement_due_date", .text)
                t.column("statement_total", .integer).notNull()
                t.column("previous_balance", .integer)
                t.column("payment_received", .integer)
                t.column("revolving_balance", .integer)
                t.column("currency", .text).notNull()
                t.column("llm_provider", .text).notNull()
                t.column("llm_model", .text).notNull()
                t.column("llm_prompt_version", .text).notNull()
                t.column("llm_input_tokens", .integer).notNull()
                t.column("llm_output_tokens", .integer).notNull()
                t.column("llm_cache_read_tokens", .integer)
                t.column("llm_cost_usd", .double).notNull()
                t.column("validation_status", .text).notNull()
                t.column("parse_warnings", .text)
                t.column("status", .text).notNull()
                t.column("imported_at", .text).notNull()
            }

            try db.create(table: "transactions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("import_batch_id", .integer).notNull()
                    .references("import_batches", onDelete: .cascade)
                t.column("card_id", .integer).notNull()
                    .references("cards", onDelete: .cascade)
                t.column("merchant_id", .integer)
                    .references("merchants", onDelete: .setNull)
                t.column("category_id", .integer)
                    .references("categories", onDelete: .setNull)
                t.column("posted_date", .text).notNull()
                t.column("posted_year_inferred", .integer).notNull()
                t.column("raw_description", .text).notNull()
                t.column("merchant_normalized", .text).notNull()
                t.column("merchant_city", .text)
                t.column("bank_category_raw", .text)
                t.column("amount", .integer).notNull()
                t.column("currency", .text).notNull()
                t.column("original_amount", .integer)
                t.column("original_currency", .text)
                t.column("fx_rate", .double)
                t.column("installment_current", .integer)
                t.column("installment_total", .integer)
                t.column("purchase_method", .text).notNull()
                t.column("transaction_type", .text).notNull()
                t.column("confidence", .double).notNull()
                t.column("categorization_reason", .text)
                t.column("fingerprint", .text).notNull().unique()
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }

            try db.create(
                index: "idx_transactions_card_date",
                on: "transactions",
                columns: ["card_id", "posted_date"]
            )
            try db.create(
                index: "idx_transactions_merchant",
                on: "transactions",
                columns: ["merchant_id"]
            )
            try db.create(
                index: "idx_transactions_category",
                on: "transactions",
                columns: ["category_id"]
            )
            try db.create(
                index: "idx_transactions_batch",
                on: "transactions",
                columns: ["import_batch_id"]
            )
        }
    }

    private static func registerV2(_ m: inout DatabaseMigrator) {
        m.registerMigration("v2_phase2_memory_and_rules") { db in

            try db.create(table: "merchant_aliases") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("merchant_id", .integer).notNull()
                    .references("merchants", onDelete: .cascade)
                t.column("alias", .text).notNull()
                t.column("source", .text).notNull()
                t.column("created_at", .text).notNull()
                t.uniqueKey(["merchant_id", "alias"])
            }

            try db.create(
                index: "idx_merchant_aliases_alias",
                on: "merchant_aliases",
                columns: ["alias"]
            )

            try db.create(table: "categorization_rules") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("pattern", .text).notNull()
                t.column("pattern_type", .text).notNull()
                t.column("merchant_id", .integer)
                    .references("merchants", onDelete: .setNull)
                t.column("category_id", .integer).notNull()
                    .references("categories", onDelete: .cascade)
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("created_by", .text).notNull()
                t.column("enabled", .integer).notNull().defaults(to: 1)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }

            try db.create(
                index: "idx_categorization_rules_enabled",
                on: "categorization_rules",
                columns: ["enabled", "created_by", "priority"]
            )

            try db.create(table: "user_corrections") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("transaction_id", .integer).notNull()
                    .references("transactions", onDelete: .cascade)
                t.column("old_category_id", .integer)
                    .references("categories", onDelete: .setNull)
                t.column("new_category_id", .integer).notNull()
                    .references("categories", onDelete: .cascade)
                t.column("correction_type", .text).notNull()
                t.column("note", .text)
                t.column("created_at", .text).notNull()
            }

            try db.create(
                index: "idx_user_corrections_transaction",
                on: "user_corrections",
                columns: ["transaction_id"]
            )

            try db.create(table: "bank_category_mappings") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("bank_name", .text)
                t.column("bank_category_raw", .text).notNull()
                t.column("category_id", .integer).notNull()
                    .references("categories", onDelete: .cascade)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
                t.uniqueKey(["bank_name", "bank_category_raw"])
            }
        }
    }
}
