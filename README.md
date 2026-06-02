# notes-cli

A small, fast, agent-first CLI over Apple Notes. Create, read, edit, delete, move, search, organize (folders), and export your notes from the terminal.

Apple Notes is the single source of truth. notes-cli keeps **no local copy, cache, mirror, search index, or history** — reads open Apple's live database directly (read-only), writes go straight to Apple Notes. The only local file it writes is `~/.notes-cli/config.json`.

Swift 6.2 — macOS 13+.

## Setup

```bash
git clone https://github.com/ehrax/notes-cli.git
cd notes-cli
brew install protobuf swift-protobuf   # protoc for codegen
make setup                             # resolve deps + generate protobuf
make release                           # build release binary
cp .build/release/notes-cli /usr/local/bin/
```

**Required**: Grant Full Disk Access to your terminal (System Settings → Privacy & Security → Full Disk Access) so notes-cli can read the Apple Notes database. Writes additionally trigger the macOS Automation prompt the first time, since they go through Apple Events.

## Usage

```bash
notes-cli init                          # pick an Apple Notes account → write ~/.notes-cli/config.json
notes-cli init --yes                    # non-interactive (accept defaults; for AI agents)
```

### Notes

```bash
notes-cli notes list                       # list all notes
notes-cli notes list --folder "Projects"   # filter by folder path
notes-cli notes search "swift"             # full-text search (live decode, recency-ranked)
notes-cli notes search "swift" --limit 20  # cap results (default 50)
notes-cli notes read <id>                  # decode + print one note
notes-cli notes create --title "New" --body "<p>Hello</p>" [--folder "Projects"]
notes-cli notes edit <id>                  # opens $EDITOR seeded with the note body
notes-cli notes edit <id> --title "T" --body "<p>...</p>"   # non-interactive edit
notes-cli notes move <id> --folder "Archive"
notes-cli notes delete <id>                # → Apple's Recently Deleted (~30 days)
```

Hashtags are plain body text and searchable like any other string; `notes-cli` does not treat them as a tagging system.

### Folders

```bash
notes-cli folders                          # list folders
notes-cli folders --tree                   # nested tree view
notes-cli folder create "Projects" [--parent "Work"]
notes-cli folder rename "Projects" "Active Projects"
notes-cli folder move "Projects" --parent "Work"
notes-cli folder delete "Projects"         # → Recently Deleted
```

### Export

```bash
notes-cli export --type md  --output ./out               # Markdown (with attachments)
notes-cli export --type json --output ./out              # JSON
notes-cli export --type md --folder "Projects"           # filter by folder
notes-cli export --type md --ignore-folders "Journal,Documents"   # exclude folders
```

### Options

```
--format json|table|markdown        output format (defaults to JSON when piped, table on a TTY)
--verbose                           debug output on stderr
```

stdout carries only the command's result; all human/debug chatter goes to stderr, so output stays pipe- and `jq`-clean.

## Make Commands

```
make setup            # one-time: resolve deps, generate protobuf
make build            # debug build
make release          # release build
make run              # run CLI
make run-verbose      # run with debug output
make test             # all tests
make test-core        # NotesCore library tests
make test-cli         # CLI tests
make test-integration # integration tests (write to real Notes — see Testing in AGENTS.md)
make test-e2e         # E2E smoke tests
make proto            # regenerate protobuf (after schema changes)
make clean            # clean build artifacts + generated code
make lint             # show warnings/errors
```

## Architecture

```
CLI Commands (init, notes, folders, folder, export)
       │
  NotesServiceProtocol
       │
  DirectNotesService
  ├── Reads  → NoteStoreReader (live NoteStore.sqlite, read-only) → ProtobufToMarkdown
  └── Writes → ScriptingBridgeWriter (Swift) → NotesCoreObjC (generated Notes.h) → Notes.app
```

- **NotesCLI** — CLI layer using [swift-argument-parser](https://github.com/apple/swift-argument-parser).
- **NotesCore** — library with models, services, and business logic.
- **Reads** open Apple's `NoteStore.sqlite` **read-only with no copy**, using [GRDB](https://github.com/groue/GRDB.swift) purely as the SQLite driver. Note bodies (gzipped protobuf) are decoded on demand via [SwiftProtobuf](https://github.com/apple/swift-protobuf). `search` decodes bodies into memory and scans them per call — there is no index.
- **Writes** go through a single ScriptingBridge path: `ScriptingBridgeWriter` (Swift) resolves the account/folder scope and calls the small `NotesCoreObjC` target, which is built against the generated `Notes.h` scripting interface. No AppleScript. See [docs/adr/0002-scriptingbridge-write-path.md](docs/adr/0002-scriptingbridge-write-path.md).
- **No local state** beyond `~/.notes-cli/config.json`: no `notes.db`, no cache, no sync, no history.

See [docs/architecture.md](docs/architecture.md) for detail, and `CONTEXT.md` + `docs/adr/` for the load-bearing decisions.

## License

MIT
