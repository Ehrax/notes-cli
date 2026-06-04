# Apple Notes is the sole source of truth; no local store

We removed the GRDB `notes.db` mirror, the sync engine, the undo/history action log, and the in-CLI `SafetyService`. notes-cli now reads Apple's `NoteStore.sqlite` **directly, read-only, with no copy** and writes back through Apple's scripting bus. Nothing is retained locally except `config.json` — no mirror, no cache, no snapshot.

We did this because notes-cli is a personal, single-user, agent-first tool: the mirror only created staleness and a manual `sync` step, and confirmation/policy belong to the *calling agent* (Claude Code's tool approval, plan mode), not duplicated inside the CLI. The CLI is pure mechanism; the caller owns policy.

## Consequences

- **Edits are irreversible.** Apple Notes exposes no body/version history through scripting, and we keep no action log — there is no `notes-cli undo` and no `notes-cli history`. A bad edit destroys the prior body with no trace.
- **Deletes are still recoverable** via Apple's Recently Deleted (~30 days); **locked notes** stay protected by Apple's encryption regardless. These are the only surviving "safety nets," and both are Apple's, not ours.
- **No protected-folder guard.** An agent can write to or delete any folder; the caller is trusted.
- **Tags and links must become native Apple Notes constructs or be dropped** — they no longer have a local home.
- **Search has no FTS index** (it lived in `notes.db`). `list`/`show`/folder ops are pure SQL against the live DB; `search` decodes note bodies (gzipped protobuf) into memory and scans them per call. **Measured** on the live DB (~411 notes / 409 bodies): decoding *all* bodies into memory takes ~36 ms, and a full-text scan of the decoded corpus takes ~9 ms — so a cold search with no copy, no index, no cache is ~45 ms total. Results rank by `zmodificationdate1` (recency) for free. Only if the library reaches a few thousand notes would a SQL title/snippet prefilter + parallel decode be worth adding — still no persistent index.
