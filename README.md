# notes-cli

AI-native Apple Notes CLI. Query, sync, tag, link, export, and manage your notes from the terminal.

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

**Required**: Grant Full Disk Access to your terminal (System Settings → Privacy & Security → Full Disk Access) so notes-cli can read the Apple Notes database directly.

## Usage

```bash
notes-cli init                          # set up ~/.notes-cli/ config & database
notes-cli sync                          # sync notes from Apple Notes
notes-cli status                        # show sync status
```

### Notes

```bash
notes-cli notes list                    # list all notes
notes-cli notes search "swift"          # full-text search (FTS5)
notes-cli notes read <id>               # read a note
notes-cli notes create --title "New"    # create a note
notes-cli notes edit <id>               # edit a note
notes-cli notes delete <id>             # delete a note
notes-cli notes move <id> --folder X    # move a note
```

### Tags & Links

```bash
notes-cli tag <id> "work"               # tag a note
notes-cli tags                          # list all tags
notes-cli link <from-id> <to-id>        # link two notes
notes-cli links <id>                    # show links for a note
```

### Export

```bash
notes-cli export --type md --output ./out           # export as Markdown (with images)
notes-cli export --type html --output ./out         # export as HTML (via pandoc)
notes-cli export --type json --output ./out         # export as JSON
notes-cli export --folder "Projects" --type md      # filter by folder
notes-cli export --tag "work" --type md             # filter by tag
notes-cli export --ignore-folders "Trash,Archive"   # exclude folders
notes-cli export --live --type md --output ./out    # sync before export
```

### History & Undo

```bash
notes-cli history                       # view action history
notes-cli undo                          # undo last action
```

### Options

```
--format json|table|markdown        output format (auto-detects TTY)
--verbose                           debug output on stderr
```

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
make test-integration # integration tests
make test-e2e         # E2E smoke tests
make proto            # regenerate protobuf (after schema changes)
make clean            # clean build artifacts + generated code
make lint             # show warnings/errors
```

## Architecture

```
CLI Commands (notes-cli sync, export, notes, ...)
       │
  NotesServiceProtocol
       │
  DirectNotesService
  ├── Reads  → NoteStoreReader (SQLite + protobuf)
  └── Writes → AppleScriptWriter (AppleScript → Notes.app)
       │
  notes.db (GRDB/SQLite)
  ├── notes (Markdown body + plaintext for FTS5)
  ├── tags, links, folders
  ├── action log (undo/history)
  └── attachments (image refs)
```

- **NotesCLI** — CLI layer using [swift-argument-parser](https://github.com/apple/swift-argument-parser)
- **NotesCore** — library with models, services, and business logic
- **SQLite** via [GRDB](https://github.com/groue/GRDB.swift) with FTS5 full-text search
- **Protobuf** via [SwiftProtobuf](https://github.com/apple/swift-protobuf) for Apple Notes body decoding
- **Apple Notes** read via direct NoteStore.sqlite access, write via AppleScript
- **Apple Reminders** integration via EventKit

## How Sync Works

1. Copy `NoteStore.sqlite` from Apple Notes to `~/.notes-cli/cache/` (read-only snapshot)
2. Query notes, folders, accounts via GRDB
3. Decode note bodies from gzipped protobuf → Markdown
4. Diff against notes.db, insert/update/delete
5. Track attachments (images, scans, drawings) for export

## License

MIT
