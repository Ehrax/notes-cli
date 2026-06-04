# notes-cli

A small, fast CLI for Apple Notes.

notes-cli lets humans and agents create, read, edit, move, search, organize, and export Apple Notes from the terminal. Apple Notes stays the source of truth: there is no notes-cli database, cache, mirror, sync step, search index, or history.

macOS 13+ · Swift 6.2 · MIT

## What It Does

- Reads Apple's live Notes database directly, read-only.
- Writes through macOS ScriptingBridge, the same Apple Events permission surface used by Notes automation.
- Searches note titles and bodies.
- Manages folders: list, create, rename, move, and delete.
- Exports notes to Markdown or JSON.
- Produces script-friendly output: JSON when piped, table on a TTY, and explicit `--format json|table|markdown`.
- Writes only one local file: `~/.notes-cli/config.json`.

## Install

Install from source:

```bash
git clone https://github.com/ehrax/notes-cli.git
cd notes-cli
brew install protobuf swift-protobuf
make setup
make install
```

`make install` installs to `/usr/local/bin` by default. Use a writable prefix if you prefer:

```bash
make install PREFIX="$HOME/.local"
```

Make sure `PREFIX/bin` is on your `PATH`. See [docs/install.md](docs/install.md) for more detail.

## Permissions

macOS protects Apple Notes behind two permission gates:

- **Full Disk Access** for your terminal or the `notes-cli` binary, required for reads.
- **Automation -> Notes**, prompted on the first write, required for create/edit/move/delete/folder commands.

Permission errors usually mean macOS has not granted one of these yet. See [docs/permissions.md](docs/permissions.md).

## Quick Start

```bash
notes-cli init
notes-cli notes list
notes-cli notes search "project"
notes-cli notes read <note-id>
notes-cli notes create --title "Trip plan" --body "<p>Book flights.</p>"
notes-cli notes move <note-id> --folder "Archive"
notes-cli notes delete <note-id>

notes-cli folders --tree
notes-cli folder create "Projects" --parent "Work"
notes-cli folder rename "Work/Projects" "Client Projects"
notes-cli folder move "Work/Client Projects" --parent "Archive"

notes-cli export --type md --output ./notes-export
```

Run `notes-cli --help`, `notes-cli notes --help`, or `notes-cli folder --help` for the full command surface.

## Behavior To Know

notes-cli is mechanism, not policy. It executes the command you gave it immediately. There are no confirmation prompts, protected folders, undo stack, action log, or local history. Deletes land in Apple's Recently Deleted folder for roughly 30 days; edits are not versioned by Apple's scripting interface.

Reads open Apple's `NoteStore.sqlite` read-only. Writes never touch that SQLite database directly; all mutations go through Notes.app via ScriptingBridge.

Locked notes are encrypted by Apple Notes and are skipped on read.

## Formatted Notes

`notes create --body` and `notes edit --body` accept conservative HTML:

- headings: `<h1>`, `<h2>`, `<h3>`
- emphasis: `<b>`, `<i>`, `<u>`
- lists: `<ul>`, `<ol>`, `<li>`
- links: `<a href="...">`
- structure: `<br>`, `<div>`, `<p>`

Apple's importer renders heading tags as bold text rather than storing recoverable heading levels. When a note is read or exported later, those headings may come back as bold Markdown instead of `#` headings. That is a Notes scripting limitation, not a notes-cli cache issue.

## Agent Footer

By default, notes created through the CLI include an italic "Created by ..." footer. Set the model or agent name with:

```bash
notes-cli notes create --title "Plan" --body "<p>...</p>" --agent "Codex"
```

or:

```bash
NOTES_CLI_AGENT="Codex" notes-cli notes create --title "Plan" --body "<p>...</p>"
```

Disable the footer during setup with:

```bash
notes-cli init --no-ai-footer
```

## Troubleshooting

The common issues are macOS permissions, Notes.app not having flushed a very recent write yet, or trying to read locked notes. Start with [docs/troubleshooting.md](docs/troubleshooting.md).

## Development

```bash
make build          # debug build
make release        # release build
make test           # all tests, serial
make test-core      # NotesCore tests
make test-cli       # CLI tests
make proto          # regenerate protobuf decoder
make clean          # clean build artifacts
```

Integration and E2E tests can write to real Apple Notes. Use throwaway notes/folders and clean them up afterward.

Architecture notes live in [docs/architecture.md](docs/architecture.md), with the load-bearing decisions in [docs/adr/](docs/adr/).

## Release Status

This is an early public macOS CLI. The command surface is intentionally small and direct; see [CHANGELOG.md](CHANGELOG.md) for release notes.

## License

MIT. See [LICENSE](LICENSE).
