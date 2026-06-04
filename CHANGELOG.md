# Changelog

All notable user-facing changes are tracked here.

## 0.1.0 - Initial Public Preview

- Added live, read-only access to Apple Notes without a local notes database, cache, mirror, sync step, or search index.
- Added note commands for list, search, read, create, edit, move, and delete.
- Added folder commands for list/tree, create, rename, move, and delete.
- Added Markdown and JSON export from live Apple Notes data.
- Added ScriptingBridge write path for all mutations.
- Added machine-readable output behavior: JSON when piped, table on TTY, and explicit `--format` overrides.
- Documented macOS Full Disk Access and Automation permissions.

Known limitations:

- macOS only.
- Reads require Full Disk Access.
- Writes require Automation permission for Notes.
- Locked notes are skipped on read.
- Apple Notes does not expose recoverable heading levels through its scripting importer.
