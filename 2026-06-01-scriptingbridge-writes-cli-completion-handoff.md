# Handoff — ScriptingBridge writes + CLI completion

Date: 2026-06-01
Status: Investigation complete, validated by live probes. No production code changed yet.

## Focus for the next session

Two intertwined workstreams, validated as feasible during this session:

1. **Replace the AppleScript write path with ScriptingBridge** (faster, in-process, type-safe, no `osascript` subprocess / no string escaping). Reads stay on the existing direct-SQLite reader.
2. **Fill the CLI gaps** — chiefly folder management (read/write/update), tag/link removal, and recursive search — to make `notes-cli` a complete CLI tool.

Direction the owner is steering toward: a **CLI-only tool with no custom `notes.db`** for note content (read live from `NoteStore.sqlite`, write via ScriptingBridge). See "Open decisions" for what that costs.

## What was validated this session (live, against real Notes)

All probes ran on macOS 26.5, Notes.app v4.13, Swift 6.2 toolchain. Temp folders/notes were created and deleted (they sit in Recently Deleted ~30 days). Throwaway probe sources were under `/tmp/sbtest/` (ephemeral — recreate if needed).

**ScriptingBridge from Swift works**, but with specific friction:
- The `sdef | sdp -fh` output is an **Objective-C** header. Referencing its `@interface` classes (`NotesApplication`, `NotesNote`…) as concrete Swift types **fails to link** (`Undefined symbols: _OBJC_CLASS_$_NotesApplication`) — they're declaration-only.
- The idiom that **does** work in Swift: hand-written `@objc protocol`s with conformance declared on `SBApplication`/`SBObject`, dispatched dynamically. **No bridging header, no ObjC target needed** → fits the existing SwiftPM package. Proven: read account/folder/note, set `body`/`name` via KVC, `delete`, `moveTo`.
- **Create is the exception.** `classForScriptingClass:` returns an `SBPseudoClass`; faking ObjC's `[[cls alloc] initWithProperties:]` from pure Swift via `perform("alloc")` **crashes** (`NSForwarding … __NSMessageBuilder … abort`). Create requires ~10 lines of **ObjC** (`[[cls alloc] initWithProperties:]`), compiled as a small SwiftPM C/ObjC target and imported from Swift. Proven working in ObjC.

**Verified write lifecycle (ObjC probe, real Notes, all cleaned up):**

| Op | Result | Time | Folder targeting |
|---|---|---|---|
| Create folder | ✅ | 56 ms | — |
| Create note in specific folder | ✅ | 773 ms | ✅ (`folderA count==1`) |
| Update body/title | ✅ | ~1.9 s | — (`name`→updated H1) |
| Move note A→B | ✅ | 48 ms | ✅ (`A==0, B==1`) |
| Delete note + folders | ✅ | ~58 ms | — |

**Speed reality (important for "make writes faster"):** big win on lightweight ops (folder create/move/delete ≈ 50 ms — beats AppleScript's ~100–300 ms subprocess spawn + round-trip). Only a **modest** win on note create (773 ms) and body update (~1.9 s) — those are dominated by Notes.app rendering HTML + CloudKit, not the IPC mechanism, so AppleScript pays similar cost there.

**`container` quirk:** a freshly created/moved SB note proxy returns `container == nil` until re-resolved. Verify folder placement by counting `folder.notes()` instead of reading `note.container`.

**TCC unchanged:** ScriptingBridge uses the same Apple Events bus → same Automation permission as AppleScript. Not a permission bypass. (Worked silently because permission was already granted.)

**DB-less caveat:** after an SB write, the direct-SQLite reader may be briefly stale (Notes writes async + WAL flush). Re-`refresh()` with a small retry after writes.

## Current state — gap analysis

Capabilities exist at three layers (CLI / Notes service / DB). The hole is everything **folder-shaped** and a **read/write asymmetry** (DB can remove/CRUD, CLI/writer can't).

- **Notes**: create/read/update/delete/move/list/search — **complete** at CLI.
- **Folders**: `createFolder` (with `parentName` → subfolders) exists in the Notes service but is **not on the CLI** (only used internally by `BlueprintService`). No rename/delete/move at the service level. DB has full folder CRUD. No `notes-cli folders` listing/tree command.
- **Tags/Links**: add/list exposed; **remove not exposed** at CLI despite DB `removeTag`/`deleteLink`.
- **Search**: flat FTS5 on title+body with `--tag`/`--folder` (exact-path) filters. No recursive subfolder search, date-range, title-only, attachment filters.
- **Export**: Markdown only. `ExportFormat` enum = `.md`. **README is stale** — it advertises HTML (pandoc) + JSON that no longer exist. Export reads from `notes.db`, not live Notes.

## Proposed roadmap (prioritized)

**P0 — ScriptingBridge writer + folder management (one workstream; same SB mechanisms already proven):**
- Add a small ObjC C-target for create (`[[cls alloc] initWithProperties:]`) + Swift `@objc protocol` shims for read/update(KVC)/delete/move.
- New `ScriptingBridgeWriter` conforming to the existing write surface; swap into `DirectNotesService`, keep `AppleScriptWriter` as fallback.
- Extend `NotesServiceProtocol` with `renameFolder` / `deleteFolder` / `moveFolder` (folder `name` is writable in the sdef → rename trivial; delete/move proven).
- New CLI: `notes-cli folders [--tree]`, `notes-cli folder create <name> [--parent X]`, `folder rename`, `folder delete`, `folder move`.

**P1 — Close tag/link asymmetry:** `notes-cli untag <id> <tag>`, `notes-cli unlink <from> <to>` (DB already supports both).

**P2 — Search depth:** recursive subfolder search (`--folder X --recursive`), optionally date-range / title-only / has-attachment.

**P3 — Export honesty:** restore HTML/JSON or fix README; allow export from live `NoteStoreReader` (supports the DB-less direction).

## Open decisions (need owner input before/while building)

1. **Keep or drop `notes.db`?** It currently hosts tags, links, and undo/history — these have **no home** without it (or must be encoded into note bodies / a thin sidecar). Reads can go fully live; export would need repointing to `NoteStoreReader`.
2. **Create path**: accept the tiny ObjC C-target, or keep AppleScript *only* for create and use SB for everything else?
3. **Folder rename/delete safety**: deletes move contents to Recently Deleted (no hard delete via scripting). Wire into the existing Safety service / undo log?

## Key files (reference, not duplicated here)

- Write path: `Sources/NotesCore/Services/Notes/AppleScriptWriter.swift`, `AppleScriptConstants.swift`, `AppleScriptRunner.swift`
- Read path: `Sources/NotesCore/Services/Notes/NoteStoreReader.swift`, `DirectNotesService.swift`
- Service contract: `Sources/NotesCore/Protocols/NotesServiceProtocol.swift`
- DB contract: `Sources/NotesCore/Protocols/DatabaseServiceProtocol.swift`
- Export: `Sources/NotesCore/Services/Export/ExportService.swift`, `Sources/NotesCLI/Commands/ExportCommand.swift`, `Sources/NotesCore/Models/ExportFormat.swift`
- CLI registration: `Sources/NotesCLI/RootCommand.swift`; note subcommands under `Sources/NotesCLI/Commands/Notes/`
- Folder model (has `parentPath`): `Sources/NotesCore/Models/Folder.swift`
- Prior design context: `docs/plans/2026-03-08-notes-cli-cli-design.md`, `docs/architecture.md`

## Working SB snippets (reconstruct probes if needed)

- Generate header: `sdef /System/Applications/Notes.app | sdp -fh --basename Notes`
- Swift read idiom: `@objc protocol` + `extension SBObject: …`, `raw as NotesApplicationP`, `app.accounts?()`
- ObjC create idiom: `[[[notes classForScriptingClass:@"note"] alloc] initWithProperties:@{@"body":…}]; [[folder notes] addObject:note];`
- Compile Swift probe: `swiftc probe.swift -framework Foundation -framework AppKit -framework ScriptingBridge -o probe`
- Compile ObjC probe: `clang -fobjc-arc objc_probe.m -framework Foundation -framework AppKit -framework ScriptingBridge -o objc_probe`

## Suggested skills for the next session

- **Plan agent / `EnterPlanMode`** — turn the P0–P3 roadmap into an ordered, file-level implementation plan before editing.
- **`tdd`** — build `ScriptingBridgeWriter` + folder commands test-first (there are existing test mocks for the service protocols).
- **`verify` / `run`** — exercise new write/folder commands against real Notes and confirm behavior (use throwaway temp folders; clean up).
- **`code-review`** then **`simplify`** — review the new writer + commands for correctness, then tidy.
- **`gh`** — open a PR per workstream (P0 writer, P0 folder CLI, P1 untag/unlink, P2 search, P3 export/README) following conventional commits.
- **`claude-md-management:revise-claude-md`** — record the SB write architecture + ObjC-create-shim decision in project memory.
- **`to-issues`** — optionally split the roadmap into independently-grabbable issues.
