# Phase 6 — Automation (v0.6)

## Goal
Hands-off import. When a new statement PDF lands in `~/Documents/PocketLens/Inbox` (e.g., saved by an Apple Mail rule), PocketLens automatically imports it and notifies the user.

## Definition of Done (per spec §10.2)
- [ ] User can configure one or more watched folders in Settings.
- [ ] Default watched folder is `~/Documents/PocketLens/Inbox` (created on first run).
- [ ] FSEvents-backed watcher detects new files and triggers an import.
- [ ] After import, a `UserNotifications` banner appears with a summary.
- [ ] Documentation for setting up an Apple Mail rule to save attachments to the Inbox.
- [ ] Watcher survives folder deletion/recreation and sleep/wake cycles.

## Tasks

### Importing package
- [ ] `FolderWatcher` — wraps `DispatchSource.makeFileSystemObjectSource` OR `EonilFSEvents` (decide during phase).
- [ ] `AutoImportCoordinator` — debounce, claim file (move to `Inbox/processing/` before parsing), handle already-imported files gracefully.
- [ ] Post-import notification via `UNUserNotificationCenter`.

### App target
- [ ] Settings → Automation section: watched folders list (add/remove), auto-import toggle.
- [ ] First-run: create `~/Documents/PocketLens/Inbox` if missing.
- [ ] Lifecycle — start watcher on app launch if auto-import enabled; stop on quit.

### Docs
- [ ] `docs/apple-mail-setup.md` — step-by-step screenshots-or-text for setting up a Mail rule that saves attachments to the Inbox. Linked from Settings.

## Dependencies
- Requires Phase 1 ✅ (import pipeline + dedup are the core of what gets triggered).
- Requires Phase 5 ⏭ optional — if LLM is enabled, auto-imported transactions go through the same categorization chain including LLM suggestions.

## Test Coverage
- `FolderWatcher` — create file, assert callback fires; delete folder, recreate, assert watcher recovers.
- `AutoImportCoordinator` — duplicate file arrival → skipped cleanly; corrupted PDF → logged, file moved to `Inbox/failed/`.
- Manual test: Apple Mail rule happy path on the user's real machine.

## Open Questions
- Sandboxing — auto-watching `~/Documents/PocketLens/Inbox` from a sandboxed app requires either a user-granted security-scoped bookmark for the folder or dropping the sandbox. Validate requirement at top of phase.
- Notification permission UX — request on first auto-import or upfront in Settings?

## Next Action
Validate sandboxing constraints first — this may affect app packaging decisions made back in Phase 0. If sandbox + auto-watch requires a bookmark dance, plan the Settings UX accordingly.
