# notes-cli

A small, fast, **agent-first** CLI over Apple Notes — create, read, edit, move, search, organize, and export your notes from the terminal. Built so LLMs and humans can drive Apple Notes programmatically.

**Apple Notes is the single source of truth.** notes-cli keeps no local copy, cache, mirror, search index, or history. Reads open Apple's live database directly (read-only); writes go straight to Apple Notes via ScriptingBridge. The only file it writes is `~/.notes-cli/config.json`.

macOS 13+ · Swift 6.2

## Features

- **Live, read-only** access to the Notes database — no sync, no mirror, no index.
- **Rich note creation** from HTML: headings, bold/italic/underline, lists, links — with automatic title and section spacing.
- **Folders**: list (flat or tree), create, rename, move, delete.
- **Search** across titles and bodies (recency-ranked, decoded on demand).
- **Export** to Markdown or JSON.
- **Machine-readable output** — JSON when piped, table on a TTY; clean for `jq` and scripts.
- **AI provenance footer** — notes created via the CLI get an optional 🤖 "created by {model}" credit.

## Install

```bash
git clone https://github.com/ehrax/notes-cli.git
cd notes-cli
brew install protobuf swift-protobuf   # codegen toolchain
make setup                             # resolve deps + generate protobuf
make install                           # build release + install to /usr/local/bin
```

`make install` may need `sudo`, or pick a writable prefix: `make install PREFIX=$HOME/.local` (then make sure `$PREFIX/bin` is on your `PATH`). After installing, `notes-cli` is available globally.

**Permissions (macOS):**
- **Full Disk Access** for your terminal (or the binary) — required to *read* the Notes database.
- **Automation → Notes** — prompted on the first *write* (writes go through Apple Events).

## Quick start

```bash
notes-cli init                 # pick an Apple Notes account → ~/.notes-cli/config.json
notes-cli init --yes           # non-interactive (for agents)

notes-cli notes list
notes-cli notes search "swift" --limit 20
notes-cli notes read <id>
notes-cli notes create --title "Trip plan" --body "<h2>Day 1</h2><div>Arrive in <b>Lisbon</b>.</div>"
notes-cli notes move <id> --folder "Archive"
notes-cli notes delete <id>    # → Recently Deleted (~30 days)

notes-cli folders --tree
notes-cli folder create "Projects" --parent "Work"

notes-cli export --type md --output ./out
```

IDs come from the `id` field of `notes list` / `notes search`. Run `notes-cli notes --help` for the full verb list.

### Writing formatted notes

`--body` is HTML, handed straight to Apple Notes. Honored: `<h1>/<h2>/<h3>`, `<b> <i> <u>`, `<ul>/<ol>/<li>`, `<a href>`, `<br>/<div>/<p>` (CSS, classes, and colors are ignored). The CLI bakes `--title` in as the note's first line and spaces sections automatically — just write semantic HTML.

### AI footer

Notes created via the CLI get an italic *🤖 Created by … via notes-cli* footer. Name the model with `--agent "Claude Opus 4.8"` or the `NOTES_CLI_AGENT` environment variable. Turn it off at setup with `notes-cli init --no-ai-footer`.

## Output

```
--format json|table|markdown   # default: JSON when piped, table on a TTY
--verbose                       # debug output on stderr
```

stdout carries only the command's result; human/debug chatter goes to stderr, so pipes and `jq` stay clean.

## Development

```bash
make build      # debug build         make test        # all tests (serial)
make release    # release build        make test-core   # library tests
make run        # run the CLI          make test-cli    # CLI tests
make proto      # regenerate protobuf   make clean       # clean artifacts
```

Integration/E2E suites write to real Notes — see [AGENTS.md](AGENTS.md) for how to run them.

## Architecture

```
CLI (init · notes · folders · folder · export)
   │  NotesServiceProtocol
   └─ DirectNotesService
       ├─ Reads  → NoteStoreReader (live NoteStore.sqlite, read-only) → ProtobufToMarkdown
       └─ Writes → ScriptingBridgeWriter → NotesCoreObjC (generated Notes.h) → Notes.app
```

Reads open Apple's `NoteStore.sqlite` read-only (GRDB as the SQLite driver only); bodies are gzipped protobuf decoded on demand (SwiftProtobuf). Writes go through a single ScriptingBridge path — no AppleScript, no local persistence beyond the config file.

See [docs/architecture.md](docs/architecture.md), [CONTEXT.md](CONTEXT.md), and [docs/adr/](docs/adr/) for the load-bearing decisions.

## License

MIT — see [LICENSE](LICENSE).
