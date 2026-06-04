# PRD — notes-cli: the direct, live, agent-first Apple Notes CLI

- **Date:** 2026-06-01
- **Status:** In progress. M1 (live read, no copy), M2a (x-coredata note ids), and M2 (ScriptingBridge write path) done and validated; M3 (folders) and M4 (export + demolition + docs) landing.
- **Authoritative context:** [`CONTEXT.md`](../../CONTEXT.md) · [ADR 0001 — sole source of truth](../adr/0001-apple-notes-is-the-sole-source-of-truth.md) · [ADR 0002 — ScriptingBridge write path](../adr/0002-scriptingbridge-write-path.md)
- **Supersedes:** the `notes.db` mirror + sync architecture and the ScriptingBridge handoff's "keep AppleScript as fallback" plan.

## 1. Vision

notes-cli is **a thin, fast pipe to Apple Notes that LLMs and humans can call.** It creates, reads, edits, deletes, moves, searches, organizes (folders), and exports notes — and nothing else. Apple Notes is the single source of truth. There is **no cache, no mirror, no search index, no sync step, and no history** — reads hit Apple's live database directly, writes go straight to Apple Notes. The only local file is `~/.notes-cli/config.json`.

The tool is **pure mechanism, not policy**: it does exactly what it's told, immediately. Any "are you sure", protected paths, or confirmation belong to the calling agent, not the CLI.

## 2. Goals (each is checkable)

- **G1 — Zero retained note state.** After any command, the only notes-cli-authored file on disk is `~/.notes-cli/config.json`. No `notes.db`, no cache dir, no snapshot, no index. *Check:* `ls ~/.notes-cli/` shows only `config.json`.
- **G2 — Live reads, no copy.** Reads open Apple's `NoteStore.sqlite` read-only with no file copy. *Check:* a read command performs no write/copy under `~/.notes-cli/` (verify via fs tracing / code review); editing a note in Notes.app is reflected on the very next `notes-cli` read with no `sync`.
- **G3 — One write path.** All mutations go through a single ScriptingBridge write path: `ScriptingBridgeWriter` (Swift) calls the `NotesCoreObjC` target, which is built against the generated `Notes.h` scripting interface. `AppleScriptWriter`, `AppleScriptConstants`, `AppleScriptRunner`, and `String.sanitizedForAppleScript` are deleted; there is no AppleScript and no `@objc` SB protocol shims. *Check:* `grep -ri applescript Sources/` returns nothing in the write path.
- **G4 — Full-text search is fast and stateless.** `notes search <term>` returns body-content matches by decoding live, with no index. *Check:* cold `notes search` over the current library completes in well under 1s (measured baseline ~45 ms for ~410 notes); produces zero new files.
- **G5 — Folder management on the CLI.** `folders [--tree]`, `folder create [--parent]`, `folder rename`, `folder delete`, `folder move` all work against real Notes. *Check:* create a nested structure and verify it in Notes.app; delete it (lands in Recently Deleted).
- **G6 — Export to JSON and Markdown from live data.** `export --type json|md` reads live Notes (no `notes.db`), with attachments for Markdown. *Check:* export a folder, diff against Notes.app contents.
- **G7 — Clean, scriptable output.** Every command emits JSON when piped / `--format json`; stdout carries only the result; chatter goes to stderr. *Check:* every command's stdout parses with `jq`.
- **G8 — Honest docs.** `README.md`, `AGENTS.md`, `docs/architecture.md` describe only what exists. No advertised HTML/pandoc export, no `--live` flag, no tags/links/undo/sync. *Check:* doc claims map 1:1 to shipped commands.

## 3. Non-goals

- No `notes.db`, no caching layer, no search index, no sync, no `resync`.
- No undo, no history, no action log, no `SafetyService`, no protected-folder guard. **The caller owns safety.**
- No tags and no links as notes-cli concepts. Hashtags are plain body text (searchable); native note links render as Markdown on read only.
- No HTML export.
- No Reminders/EventKit integration.
- No `BlueprintService` / templates.
- No MCP server (explicitly deferred — see §8).

## 4. Target command surface

| Command | Purpose | Path |
|---|---|---|
| `init` | Pick account → write `config.json` (no DB) | read |
| `notes list [--folder] [--limit] [--fields]` | List notes (SQL, instant) | read |
| `notes search <term> [--limit]` | Full-text, live decode, recency-ranked | read |
| `notes read <id>` / `show` | Decode + print one note | read |
| `notes create --title --body [--folder]` | Create note | write |
| `notes edit <id> [--title] [--body]` | Update note | write |
| `notes move <id> --folder <path>` | Move note | write |
| `notes delete <id>` | Delete note (→ Recently Deleted) | write |
| `folders [--tree]` | List folders / tree | read |
| `folder create <name> [--parent <path>]` | Create folder/subfolder | write |
| `folder rename <path> <newName>` | Rename folder | write |
| `folder move <path> --parent <path>` | Move folder | write |
| `folder delete <path>` | Delete folder (→ Recently Deleted) | write |
| `export --type json\|md [--folder] [--output]` | Export live notes | read |

## 5. Cut list (delete)

- Commands: `sync`, `status`, `undo`, `history`, `tag`, `tags`, `link`, `links`.
- Services: `DatabaseService` (+ protocol), `SyncService` (+ protocol), `SafetyService` (+ protocol), `ReminderService` (+ EventKit dep), `BlueprintService`, `AppleScriptWriter`, `AppleScriptConstants`, `AppleScriptRunner`.
- Models / data: `Tag`, `Link`, `ActionRecord`, sync state; all GRDB migrations + FTS5; `PersistableRecord` conformances; `String.sanitizedForAppleScript`.
- Behavior: the `refresh()` file-copy; hashtag stripping in `ProtobufToMarkdown` (hashtags must survive as text).
- Config/Make: `~/.notes-cli/notes.db` and `cache/` handling; `make clean-cache`; stale README export claims and `--live`.

## 6. Keep / adapt

- **Keep as-is:** `ConfigService`, `ProtobufToMarkdown` (but stop stripping hashtags), `AttachmentResolver` (export fidelity), `GlobalOptions`/formatters, `NotesError`.
- **Adapt:** `NoteStoreReader` → open the live DB read-only, drop the copy. `DirectNotesService` → drop `refresh()`-copy, swap writer to `ScriptingBridgeWriter`. `ServiceContainer` → slim to config + notes. `Note`/`Folder` → `FetchableRecord` + `Codable` only (no persistence).
- **GRDB stays** — as the read-only SQLite driver only.

## 7. Build list (new)

- **W1 — Live read path.** Rework `NoteStoreReader.refresh()`/open to read Apple's `NoteStore.sqlite` read-only with no copy (read-only connection + busy-timeout; decide `immutable=1` vs WAL-aware — see §9 R1). Stop stripping hashtags.
- **W2 — ScriptingBridge writer.** A single ScriptingBridge write path: a small ObjC target (`NotesCoreObjC`) built against the generated `Notes.h` does the SB element creation/update/delete/move (pure Swift can't `alloc` on the SB pseudo-class — see ADR 0002); `ScriptingBridgeWriter` (Swift) resolves account + folder scope and calls its C API. Conforms to the write surface; delete the AppleScript path. No `@objc` SB protocol shims.
- **W3 — Folder management.** Extend the write surface with `renameFolder` / `deleteFolder` / `moveFolder`; add the folder CLI commands; `folders --tree` listing.
- **W4 — Search.** `notes search` decodes bodies live and scans in memory, recency-ranked by `zmodificationdate1`. (Add `--deep` / SQL prefilter only if a library crosses a few thousand notes — not now.)
- **W5 — Export.** JSON + Markdown from the live reader; remove HTML and `--live`.
- **W6 — Demolition + docs.** Delete the cut list; rewrite `README.md` and `docs/architecture.md` to match. (`AGENTS.md`/`CLAUDE.md` already updated.)

## 8. Milestones

1. **M1 — Live read, no copy (W1). DONE.** `list`/`read`/`search`/`folders` work read-only against the live DB; `notes.db`/`cache` no longer created by reads. *Exit:* G1 (reads), G2, G4.
2. **M2 — ScriptingBridge writer (W2). DONE.** `create`/`edit`/`delete`/`move` work via the single SB path (`ScriptingBridgeWriter` → `NotesCoreObjC` / generated `Notes.h`); AppleScript deleted. *Exit:* G3, verified round-trips against real Notes.
3. **M3 — Folders (W3). DONE.** Full folder CRUD on the CLI (`folders [--tree]`, `folder create|rename|move|delete`). *Exit:* G5.
4. **M4 — Export + demolition + docs (W5, W6). In progress.** JSON/MD export live; cut list removed; docs honest. *Exit:* G6, G8, and G1 fully (no DB anywhere).

## 9. Risks & open implementation questions

- **R1 — Live WAL read mode.** Reading a SQLite DB Notes.app is writing: choose `immutable=1` (fastest, no locks, but ignores `-wal` so very recent writes — incl. our own — may not appear until Notes checkpoints) vs read-only + `busy_timeout` (sees committed WAL sooner, may briefly wait on a lock). Matters for "create note → immediately read it back". *Decide during W1/W2; verify the read-back-after-write path.*
- **R2 — SB `container == nil`.** A freshly created/moved SB note proxy returns `container == nil` until re-resolved; verify folder placement by counting `folder.notes()`, not `note.container`.
- **R3 — Post-write staleness.** After a SB write, the live read may briefly lag (async write + WAL flush); reads should retry briefly.
- **R4 — ObjC C-target in SwiftPM.** Note `create` needs ~10 lines of ObjC; ensure the target builds cleanly in the package and via `make`.
- **R5 — Snippet cleanliness.** Search snippets must come from the real `ProtobufToMarkdown` decode (clean), not naive byte extraction.

## 10. Success definition

notes-cli ships when: it creates/reads/edits/deletes/moves notes and folders against real Apple Notes through one ScriptingBridge path; searches body content live in well under a second with zero retained state; exports JSON + Markdown from live data; `~/.notes-cli/` contains only `config.json`; and every doc claim maps to a real command. Smaller, faster, and honest than what it replaced.
