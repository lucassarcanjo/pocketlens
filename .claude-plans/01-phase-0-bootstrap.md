# Phase 0 — Bootstrap

## Goal
Make the repo buildable and install the durable cross-session planning + documentation infrastructure. No product features yet.

## Definition of Done
- [ ] `.claude-plans/` exists with overview, session log, and 7 phase files.
- [ ] `docs/` exists with 8 concept markdown files.
- [ ] `README.md`, `LICENSE`, `CONTRIBUTING.md`, `.gitignore`, `Makefile` at repo root; `app/project.yml` XcodeGen spec.
- [ ] `app/PocketLens/` contains a minimal SwiftUI app (`PocketLensApp.swift`, `ContentView.swift`, `Info.plist`, entitlements).
- [ ] 5 SPM packages (`Domain`, `Persistence`, `Importing`, `Categorization`, `LLM`) each compile and have one passing test.
- [ ] `xcodegen generate` produces `app/PocketLens.xcodeproj` without errors (requires `brew install xcodegen`).
- [ ] `xcodebuild -scheme PocketLens -destination 'platform=macOS' build` succeeds.
- [ ] `xcodebuild -scheme PocketLens test` runs one trivial XCTestCase and passes.
- [ ] `00-OVERVIEW.md` shows Phase 0 ✅ and Phase 1 ⏭.

## Tasks
- [x] Write `.claude-plans/00-OVERVIEW.md` + `SESSION-LOG.md` + 7 phase skeletons.
- [x] Write 8 `docs/*.md` concept files.
- [x] Write root files (README, LICENSE, CONTRIBUTING, .gitignore, Makefile).
- [x] Write `app/project.yml` (XcodeGen spec lives inside `app/` so spec-dir = SRCROOT = `app/`).
- [x] Scaffold 5 SPM packages.
- [x] Scaffold SwiftUI app target + test target.
- [x] Create fixtures/ placeholders.
- [x] Verify: all 5 SPM packages pass `swift test` (Swift 6.2, Xcode 26).
- [x] Verify: `make gen && make build && make test-app` succeeds end-to-end.

## Files Touched
See the plan at `(internal plan)` for the full file list. Nothing in `packages/` or `app/` contains real product logic yet.

## Dependencies
None — this is the first phase.

## Test Coverage
Each SPM package has a single trivial XCTestCase that imports the package and asserts `true`. App target has one XCTestCase for the same purpose. This proves the build + test wiring, not any behavior.

## Open Questions (deferred to Phase 1)
1. Does the user have a sample Itaú credit card PDF to seed `ItauInvoiceParser` fixtures?
2. SQLite library choice — GRDB.swift vs SQLite.swift vs raw C bindings?
3. `git init` locally this session and/or push to GitHub? (Default: local-only, user initiates remote.)
4. `LICENSE` author name — "PocketLens Contributors" vs user's personal name/email? (Default: "PocketLens Contributors".)

## Next Action
Phase 0 is complete. Start Phase 1 — see [`02-phase-1-mvp.md`](02-phase-1-mvp.md). First thing to settle: the four open questions at the top of that file (Itaú PDF fixture, SQLite library choice, `git init` + remote, LICENSE author name).
