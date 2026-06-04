# Troubleshooting

## Read Commands Fail With Permission Errors

Grant Full Disk Access to your terminal app or to the `notes-cli` binary:

```text
System Settings -> Privacy & Security -> Full Disk Access
```

Restart the terminal after granting access.

## Write Commands Fail Or macOS Blocks Automation

Write commands use ScriptingBridge to ask Notes.app to mutate notes and folders. Allow Automation access:

```text
System Settings -> Privacy & Security -> Automation
```

Find your terminal app or `notes-cli` and enable Notes access.

## A Note I Just Created Does Not Immediately Appear

Notes.app writes asynchronously. notes-cli retries after writes, but a very recent change can still take a moment to appear in Apple's live database. Try the read/search command again.

## Locked Notes Are Missing

Locked notes are encrypted by Apple Notes. notes-cli skips them on read.

## Headings Come Back As Bold Text

Apple's scripting importer renders HTML headings visually, but does not store recoverable heading levels. When notes-cli reads or exports the note later, those headings may appear as bold Markdown instead of `#` headings.

## `notes-cli --version` Works But Notes Commands Fail

The binary is installed correctly. Check permissions next:

- Full Disk Access for reads.
- Automation -> Notes for writes.

See [permissions.md](permissions.md).
