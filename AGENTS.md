# notes-cli

Small, fast, agent-first CLI over Apple Notes (create/read/edit/delete/move/search/organize/export) so LLMs and humans can drive Apple Notes from the terminal.

Domain language, invariants, and architecture: `CONTEXT.md` — read before changing load-bearing behavior. Design decisions: `docs/adr/`. Target scope: PRD `docs/plans/2026-06-01-notes-cli-direct-live-prd.md`.

## Status: migration substantially complete
Already deleted (do not reintroduce): the GRDB `notes.db` mirror + FTS5, `SyncService` / `sync` / `status`, `SafetyService` + undo/history/action log, tags, links, the AppleScript write path (`AppleScriptWriter`/`AppleScriptConstants`/`AppleScriptRunner`), Reminders/EventKit, `BlueprintService`, and HTML export. What ships now: live read-only SQLite reads, in-memory search, the ScriptingBridge (ObjC) write path, folder management, and JSON/Markdown export. See the PRD for the full target.

If you find code that contradicts the ADRs — a cache, a sync step, a tag/link table, an action log, an AppleScript writer — it is **legacy to delete, not a pattern to extend.**

## Footguns
- GRDB is a read-only SQLite driver only — never reintroduce a write/persistence layer, migrations, or FTS5.
- Do not reintroduce a cache, mirror, index, sync step, or history to "optimize." See ADR 0001 / CONTEXT.md.
- No interactive prompts or "are you sure" flows — the CLI is pure mechanism, the caller owns policy.
- Reading Apple's DB requires Full Disk Access; permission failures are a TCC grant problem, not a code bug.
- SwiftLint limits are enforced via the build plugin — see `.swiftlint.yml`.

## Commands
`make setup` (one-time: resolves packages, checks `protoc`, generates protobuf) · `make proto` (regenerate decoder after editing `Proto/notestore.proto`, never hand-edit the generated file) · `make test-core` / `make test-cli` (fast unit gates) · `make test-integration` / `make test-e2e` (ScriptingBridge writes, export end-to-end) · `make run-verbose` (debug loop).
