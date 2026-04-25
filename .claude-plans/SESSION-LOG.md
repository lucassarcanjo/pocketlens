# PocketLens Session Log

Append-only log of Claude sessions. Most recent at the bottom.

---

## 2026-04-24 — Bootstrap: planning + repo scaffold

**Active phase:** 0 — Bootstrap
**Goal this session:** Create the cross-session planning infrastructure, concept docs, and a buildable empty SwiftUI app scaffold.

**Shipped:**
- `.claude-plans/` with `00-OVERVIEW.md`, `SESSION-LOG.md`, and 7 phase skeleton files.
- `docs/` with 8 concept markdown files (architecture, data-model, parsers, categorization, import-flow, privacy, llm-integration, contributing).
- Root tooling: `README.md`, `LICENSE` (MIT), `CONTRIBUTING.md`, `.gitignore`, `Makefile`, `project.yml`.
- `app/PocketLens/` SwiftUI placeholder app + `app/PocketLensTests/`.
- `packages/{Domain,Persistence,Importing,Categorization,LLM}/` empty SPM modules with trivial tests.
- `fixtures/{statements,expected-output}/` placeholder dirs.

**Decisions made:**
- XcodeGen over Tuist/manual Xcode/pure SPM — regenerable, VCS-friendly, minimal dependency.
- macOS 14 Sonoma minimum target — broad compatibility with modern SwiftUI/Swift Charts.
- MIT license — permissive, standard for consumer dev tools.
- 5 SPM packages (Domain, Persistence, Importing, Categorization, LLM) per spec §17.1; parsing lives inside Importing.

**Verification done this session:**
- All 5 SPM packages pass `swift test` on Swift 6.2 / Xcode 26 / arm64-apple-macos14.0.
- `make gen && make build && make test-app` succeeds end-to-end on user's machine.
- File tree matches the plan.

**Scaffold fixes applied mid-session:**
- Moved `project.yml` from repo root into `app/` so spec directory equals the Xcode `SRCROOT`. This was needed because XcodeGen writes `CODE_SIGN_ENTITLEMENTS` verbatim into the pbxproj; when spec was at repo root but project at `app/`, the path doubled to `app/app/PocketLens/PocketLens.entitlements`.
- `packages/*` paths in the spec are now `../packages/X` (one level up from `app/`).
- Makefile `gen` target is now `cd app && xcodegen generate`.
- User's environment also needed `xcodebuild -runFirstLaunch` once — resolved a stale CoreSimulator version that was blocking `IDESimulatorFoundation` plugin load.

**Accepted plist changes (made externally during session):**
- `app/PocketLens/Info.plist` — simplified to minimal bundle keys (no category/versioning placeholders). User/tooling decision; left as-is.
- `app/PocketLens/PocketLens.entitlements` — now empty `<dict/>`. App no longer sandboxed. Intentional per system reminder. Phase 6 (folder watching) will need to revisit if sandbox is re-enabled — security-scoped bookmarks would be required for `~/Documents/PocketLens/Inbox`.

**Open items / next action:**
- Phase 1 (v0.1 MVP) is ready to start — see `.claude-plans/02-phase-1-mvp.md` for the pinned "Next Action".
- Four open questions deferred to Phase 1 (Itaú PDF fixture, SQLite lib choice, git init + remote, LICENSE author name).
