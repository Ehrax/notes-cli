# Architecture

notes-cli is a thin, fast pipe to Apple Notes. **Apple Notes is the single source of truth**; the tool keeps no local copy, cache, mirror, search index, or history. The only file it writes is `~/.notes-cli/config.json`.

It is **pure mechanism, not policy**: it executes immediately and does exactly what it is told. Confirmation, protected paths, and "are you sure" belong to the calling agent, not the CLI.

## Layers

```
CLI Commands (init, notes, folders, folder, export)   ← Sources/NotesCLI
       │  parse input, format output (GlobalOptions / OutputFormatter)
  ServiceContainer (actor: config + notes)            ← Sources/NotesCore
       │
  NotesServiceProtocol  ──  DirectNotesService        ← Sources/NotesCore/Services/Notes
       │                          │
       │                          ├── Reads  → NoteStoreReader → ProtobufToMarkdown
       │                          └── Writes → ScriptingBridgeWriter → NotesCoreObjC
       │
  ConfigService (config.json)                         ← Sources/NotesCore/Services/Config
```

The CLI layer is kept thin: commands parse arguments and format output. Reading, decoding, writing, and formatting live in `NotesCore`. Services are reached through the `ServiceContainer` actor, which is slim — only `config` and `notes`.

## Reads — live, no copy

`NoteStoreReader` opens Apple's `NoteStore.sqlite` (under `~/Library/Group Containers/group.com.apple.notes/`) **read-only, with no file copy**, using GRDB purely as the SQLite *driver* (no migrations, no FTS5, no persistence). The connection is read-only with a busy-timeout so it sees committed WAL writes (including notes notes-cli just wrote) without taking Notes.app's writer lock.

- `list`, `read`, and folder listing are pure SQL against Apple's tables.
- Note bodies are stored as gzipped protobuf; `ProtobufToMarkdown` decodes them to Markdown on demand. Hashtags survive decoding as plain text. Attachment references are resolved for export fidelity.
- Reading requires **Full Disk Access**. A permission failure is a TCC grant problem, not a code bug.

## Search — in-memory, stateless

`notes search` decodes note bodies live and scans them in memory, recency-ranked by modification date. There is **no index** and no retained state. At personal scale (hundreds to low thousands of notes) this completes in well under a second (measured baseline ~45 ms for ~410 notes). If a library ever crossed many thousands of notes, the only sanctioned optimization is a SQL title/snippet prefilter plus parallel body decode — still with zero persistent state.

## Writes — one ScriptingBridge path

All mutations (`notes create|edit|delete|move`, `folder create|rename|move|delete`) go through a **single** write path:

- `ScriptingBridgeWriter` (Swift) resolves the account and `/`-delimited folder scope, then calls a small C API exposed by the **`NotesCoreObjC`** target.
- `NotesCoreObjC` is Objective-C built against the **generated `Notes.h`** scripting interface (generated from Notes.app's `.sdef`). It performs the ScriptingBridge element creation/update/delete/move.

Pure Swift cannot drive generic `SBApplication` element creation (no class symbols; you cannot `alloc` on the SB pseudo-class — hand-written `@objc` protocol shims abort the process), so that logic lives in ObjC. There is **no AppleScript** and no fallback writer. ScriptingBridge uses the same Apple Events bus as AppleScript, so writes still require the macOS Automation grant. See [ADR 0002](adr/0002-scriptingbridge-write-path.md).

Two write-path quirks are handled deliberately: a freshly created/moved SB note proxy reports `container == nil` until re-resolved (placement is verified via a live read / `folder.notes()`, not `note.container`), and a just-written note may briefly lag the live read snapshot (reads retry briefly).

## Safety & data integrity

- The live `NoteStore.sqlite` is **read-only — never written to**. All mutations go through ScriptingBridge.
- There is **no undo, no history, no action log, no protected-folder guard**. Edits are irreversible (Apple exposes no body/version history via scripting); deletes land in Apple's Recently Deleted (~30 days); locked notes are encrypted and skipped on read.
- The CLI does not confirm or gate destructive operations — the caller owns policy.

See [ADR 0001](adr/0001-apple-notes-is-the-sole-source-of-truth.md).

## Export

`export --type json|md` reads live Notes (no `notes.db`) and writes files to disk. Markdown export resolves and writes attachments; JSON export emits structured note data. Filters: `--folder <path>` and `--ignore-folders <a,b,c>`. There is no HTML export and no pre-export sync step.

## Output

Every command emits machine-readable output: JSON when piped or `--format json`, a table on a TTY, or `--format table|markdown` to override. stdout carries only the result; human/debug chatter goes to stderr (via `Log`, surfaced with `--verbose`), so pipes and `jq` stay clean. Read models (`Note`, `Folder`) conform to GRDB's `FetchableRecord` (decode only) and `Codable`; their JSON shape is the public output contract.

## Dependencies

- [swift-argument-parser](https://github.com/apple/swift-argument-parser) — CLI parsing.
- [GRDB](https://github.com/groue/GRDB.swift) — SQLite driver for the read-only live database (driver only; no persistence layer).
- [SwiftProtobuf](https://github.com/apple/swift-protobuf) — decode Apple Notes' gzipped-protobuf bodies. The schema lives in `Proto/notestore.proto`; regenerate with `make proto`.
- `NotesCoreObjC` — in-package Objective-C target for the ScriptingBridge write path, built against the generated `Notes.h`.
