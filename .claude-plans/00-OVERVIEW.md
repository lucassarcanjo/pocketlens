# PocketLens — Phase Overview & Resume Protocol

This folder is the durable memory between Claude sessions. Every session starts by reading this file.

## Status Board

| # | Phase | Version | Status | Plan File |
|---|---|---|---|---|
| 0 | Bootstrap | — | ✅ done | [01-phase-0-bootstrap.md](01-phase-0-bootstrap.md) |
| 1 | LLM-Powered Statement Import | v0.1 | ⏭ ready | [02-phase-1-mvp.md](02-phase-1-mvp.md) |
| 2 | Local Memory & Rules | v0.2 | ⏸ blocked by Phase 1 | [03-phase-2-memory.md](03-phase-2-memory.md) |
| 3 | Dashboard | v0.3 | ⏸ blocked by Phase 2 | [04-phase-3-dashboard.md](04-phase-3-dashboard.md) |
| 4 | Bank Statement Import | v0.4 | ⏸ blocked by Phase 3 | [05-phase-4-bank.md](05-phase-4-bank.md) |
| 5 | LLM Expansion (Ollama, OpenAI, assist features) | v0.5 | ⏸ blocked by Phase 4 | [06-phase-5-llm.md](06-phase-5-llm.md) |
| 6 | Automation | v0.6 | ⏸ blocked by Phase 5 | [07-phase-6-automation.md](07-phase-6-automation.md) |

**Legend:** ✅ done · 🔄 in progress · ⏭ ready to start · ⏸ blocked · ❌ blocked by issue

## Resume Protocol

When starting a new Claude session on PocketLens:

1. **Read this file.** Identify the active phase (🔄 or next ⏭).
2. **Open the active phase file.** Jump to the `## Next Action` section — that's where the last session left a hand-off note.
3. **Scan recent `SESSION-LOG.md` entries** for context on recent decisions.
4. **Before ending the session**, you MUST:
   - Update the active phase file's task checkboxes and `## Next Action` section.
   - Append a dated entry to `SESSION-LOG.md` (see template below).
   - If a phase completed, update this table (status → ✅) and unblock the next phase (⏸ → ⏭).

## SESSION-LOG.md Entry Template

```markdown
## YYYY-MM-DD — <short session title>

**Active phase:** N — <phase name>
**Goal this session:** <1–2 sentences>
**Shipped:**
- <concrete deliverable>
- <concrete deliverable>
**Decisions made:**
- <decision + rationale>
**Open items / next action:**
- <what the next session should pick up>
```

## Phase File Template

Each phase file follows this shape:

```markdown
# Phase N — <name> (v0.X)

## Goal
<one paragraph>

## Definition of Done
- [ ] <testable condition>
- [ ] <testable condition>

## Tasks
- [ ] <task>
- [ ] <task>

## Files Touched
- `path/to/file` — <what changes>

## Dependencies
- Requires Phase <N-1> complete because …

## Test Coverage
- <what to test + fixture sources>

## Open Questions
- <unresolved item>

## Next Action
<the one thing the next session should do first>
```

## Decisions Locked In

These are binding choices made during planning. Revisit only with explicit user approval.

- **Build tool:** XcodeGen — `app/project.yml` is source of truth, `.xcodeproj` is regenerated and gitignored. Run `cd app && xcodegen generate` (or `make gen`).
- **Minimum macOS:** 14.0 Sonoma.
- **License:** MIT.
- **Persistence:** SQLite via **GRDB.swift v6.x** (locked Phase 1).
- **Module split:** 5 SPM packages — `Domain`, `Persistence`, `Importing`, `Categorization`, `LLM`.
- **Statement extraction:** **LLM-driven**, not bank-specific code. Anthropic Claude (Sonnet 4.6 default) is the Phase 1 provider, with `MockLLMProvider` for tests. New issuers are a fixture + (optionally) a small prompt addendum, not a new parser class.
- **Privacy:** PocketLens **is** an LLM-extraction tool — there is no non-LLM mode and no manual-entry fallback. If a user doesn't want their statement text sent to an LLM, this app isn't for them. Disclosure happens twice with low friction: a one-liner on first-launch onboarding (where the user pastes their Anthropic API key) and a one-liner inline on the drop zone ("By uploading you agree to send the redacted text to Anthropic Claude — not used for training"). Pre-LLM redaction strips full card numbers, CPF/CNPJ, and street addresses. Keys live in macOS Keychain. In Phase 5, users may swap providers (Ollama / OpenAI) — the disclosure line on the drop zone updates accordingly.
- **License author:** Lucas Arcanjo (MIT).
