# notes-cli

## Mission
- notes-cli is a small, fast, **agent-first** CLI over Apple Notes: create, read, edit, delete, move, search, organize (folders), and export notes from the terminal so LLMs and humans can drive Apple Notes programmatically.
- **Apple Notes is the single source of truth. notes-cli keeps no local copy, cache, mirror, search index, or history.** Reads open Apple's live database directly (read-only); writes go straight to Apple Notes. The only local file is `~/.notes-cli/config.json`.
- The CLI is **pure mechanism, not policy.** It executes immediately and does exactly what it is told. Confirmation, protected paths, and "are you sure" belong to the calling agent/harness — not the CLI.
- Prefer reliable, native, simple behavior over clever abstractions. Always write the smallest thing that works.
- **Authoritative design lives in:** `CONTEXT.md` (glossary), `docs/adr/0001-apple-notes-is-the-sole-source-of-truth.md`, `docs/adr/0002-scriptingbridge-write-path.md`, and the PRD `docs/plans/2026-06-01-notes-cli-direct-live-prd.md`. Read these before changing load-bearing behavior.

## Status: migration substantially complete
- The migration to the architecture below has landed. **Already deleted (do not reintroduce):** the GRDB `notes.db` mirror + FTS5, `SyncService` / `sync` / `status`, `SafetyService` + undo/history/action log, tags, links, the AppleScript write path (`AppleScriptWriter`/`AppleScriptConstants`/`AppleScriptRunner`), Reminders/EventKit, `BlueprintService`, and HTML export. What ships now: live read-only SQLite reads, in-memory search, the ScriptingBridge (ObjC) write path, folder management, and JSON/Markdown export. See the PRD for the full target.
- If you find code that contradicts the ADRs — a cache, a sync step, a tag/link table, an action log, an AppleScript writer — it is **legacy to delete, not a pattern to extend.**

## Tooling
- Use the `fff` MCP tools for all file search work: `find_files` for names, `grep` / `multi_grep` for contents.
- Prefer the repo-local `make` targets over ad hoc `swift build` / `swift test`; see Toolchain and Testing below.
- After editing `Proto/notestore.proto`, regenerate the decoder with `make proto`; never hand-edit the generated `Sources/NotesCore/Protobuf/notestore.pb.swift`.
- Use the `tdd` skill for behavior changes, and consult `CONTEXT.md` + `docs/adr/` before reshaping anything load-bearing.

## Source Of Truth (code map)
- CLI behavior: `Sources/NotesCLI/` (ArgumentParser commands, formatters, `GlobalOptions`)
- Library, models, services, business logic: `Sources/NotesCore/`
- Service protocols: `Sources/NotesCore/Protocols/`; implementations: `Sources/NotesCore/Services/`
- Unit tests: `Tests/NotesCoreTests/` (library) and `Tests/NotesCLITests/` (CLI); integration: `Tests/NotesIntegrationTests/`; E2E smoke: `Tests/NotesE2ETests/`; shared mocks/factories: `Tests/NotesTestSupport/`
- Package configuration: `Package.swift`; build/test entrypoints: `Makefile`
- Apple Notes protobuf schema: `Proto/notestore.proto`

## Architecture
- **Reads** open Apple's live `NoteStore.sqlite` (`~/Library/Group Containers/group.com.apple.notes/`) **read-only, with no copy.** `NoteStoreReader` uses GRDB purely as the SQLite *driver*; `ProtobufToMarkdown` decodes gzipped-protobuf bodies on demand. `list` / `show` / folder ops are pure SQL; `search` decodes bodies into memory and scans them per call. There is **no FTS index** — at personal scale (hundreds–low thousands of notes) decoding the whole corpus is tens of milliseconds (measured: ~409 bodies in ~36 ms, scan ~9 ms).
- **Writes** go through a single path: `ScriptingBridgeWriter` (Swift) drives ScriptingBridge via a small ObjC target (`NotesCoreObjC`) built against the generated `Notes.h` scripting interface — there are **no hand-written `@objc` SB protocol shims** (they broke SB's message forwarding) and **no AppleScript**. Swift resolves account/folder scope and calls the ObjC C API; the ObjC side does the SB element creation/update/delete/move. There is no fallback writer. See ADR 0002.
- **GRDB stays as a read-only SQLite driver only.** No migrations, no FTS5, no `PersistableRecord`, no persistence. Do not reintroduce a write/persistence layer.
- Keep the CLI layer thin: commands parse input and format output. Reading, decoding, writing, and formatting live in `NotesCore`, never inside command files.
- Access services through the `ServiceContainer` actor with `try await`. The container is now slim (config + notes). Each service has a protocol in `Protocols/` with its implementation in `Services/`.
- **Do not reintroduce a cache, mirror, index, sync step, or history to "optimize."** If a library is ever genuinely huge, the only sanctioned optimization is a SQL title/snippet prefilter + parallel body decode — still with zero persistent state.
- Do not introduce a seam for theoretical flexibility. One adapter means hypothetical; two means real. Make the protocol the test surface.
- Do not define models, domain enums, reusable extensions, parsers, or formatting helpers inside command files; move them to `NotesCore/Models/`, `Extensions/`, `Utilities/`, or a focused service.

## Safety & Data Integrity
- Apple Notes is the source of truth; **never keep a local copy of note content.** The live `NoteStore.sqlite` is **read-only — never write to it.** All mutations go through ScriptingBridge.
- There is **no undo, no history, no action log, no `SafetyService`, no protected-folder guard.** Edits are irreversible (Apple exposes no body/version history via scripting); deletes land in Apple's Recently Deleted (~30 days); locked notes are encrypted and skipped on read. **Do not reintroduce any of these layers** — see ADR 0001.
- The CLI does **not** confirm, gate, or guard destructive operations — the caller owns policy. Do not add interactive prompts or "are you sure" flows.
- Reading Apple's DB requires Full Disk Access. Permission failures are a TCC grant problem, not a code bug — check the grant first.

## Engineering Discipline
- Write the smallest code that solves the requested problem. No speculative features, abstractions, configuration, or extension points.
- Touch only what the request requires. Match existing style and local patterns.
- Remove only unused code introduced by your own change — except when explicitly deleting legacy per the PRD/ADRs.
- If a change grows large, simplify before continuing.
- SwiftLint is enforced via the build plugin (`.swiftlint.yml`): line length 120 warn / 200 error, function body 50 / 100, type body 300 / 500, file length 500 / 1000, no `force_unwrapping` or `implicitly_unwrapped_optional`. Let these limits drive splitting large files into focused siblings.
- Every changed line should trace to the request, a failing test, or a required invariant.

## Workflow
- Read the current code and the ADRs/PRD before changing behavior; preserve unrelated user changes.
- For behavior changes, bug fixes, and risky refactors, use the `tdd` skill: write one behavior-focused failing test, confirm it fails for the right reason, implement the smallest change, get it green, then repeat.
- For docs, mechanical cleanup, or low-risk output tweaks, use judgment instead of forcing test-first work.
- Use focused `make test-core` / `make test-cli` runs while iterating; reach for `make test` and the integration/E2E gates when touching ScriptingBridge writes or export end-to-end.
- Keep commits small, conventional, and focused on one coherent step.
- Put a hard bound on commands that can hang. A 6-minute cap is the default; never leave log follows or interactive sessions running indefinitely.

## Output & Formatting
- notes-cli is scriptable: every command must produce clean, machine-readable output. Respect `GlobalOptions` — JSON when piped, table on a TTY, `--format json|table|markdown` overrides.
- Send human/debug chatter to stderr (via `Log` with `--verbose`); keep stdout reserved for the command's actual result so pipes and `jq` stay clean.
- Read models conform to GRDB's `FetchableRecord` (decode only) and `Codable`; keep their JSON shape stable — it is the public output contract.
- Use the `NotesError` enum for all errors so exit codes stay typed and meaningful.

## Toolchain
- Use the repo-local `make` targets unless debugging the build itself: `make build` (debug), `make release`, `make run` / `make run-verbose`.
- One-time setup is `make setup` (resolves packages, checks for `protoc`, generates protobuf). Install codegen deps with `brew install protobuf swift-protobuf`.
- After editing `Proto/notestore.proto`, run `make proto` to regenerate the decoder; never hand-edit the generated file.
- notes-cli reads Apple's database directly, so it requires Full Disk Access for the terminal (or the binary). If reads fail with permission errors, check that grant first.
- `make clean` drops build artifacts and generated protobuf. (There is no `notes.db` or cache snapshot to clean anymore.)

## Testing
- Run the fast unit gates while iterating: `make test-core` for `NotesCore`, `make test-cli` for CLI behavior. Run `make test` before closing a change.
- Reach for `make test-integration` / `make test-e2e` when the change touches **ScriptingBridge writes** or export end-to-end. Exercise writes against real Notes using throwaway folders/notes and clean them up (they sit in Recently Deleted ~30 days).
- Unit tests are mandatory after any implementation. Use the Swift Testing framework (`@Test`, `#expect`), not XCTest.
- Mock services through `ServiceContainer.override(...)` and `reset()` between tests; keep shared mocks/factories in `Tests/NotesTestSupport/`.
- Keep tests focused on user-visible behavior, read/decode correctness, write round-trips, and export fidelity.

## Debugging & Telemetry
- Use the `Log` helper (per-service `os.Logger`) for diagnostics; it integrates with Console.app and mirrors to stderr when `--verbose` is set. Only two categories survive — `config` and `general`; there are no more sync/database/safety/reminders/applescript categories. Add a focused category if a surviving service needs one.
- Reach for `make run-verbose` or `--verbose` as the primary debugging loop for ScriptingBridge writes, live reads, body decoding, and export.
- Add lightweight telemetry when behavior affects Apple Notes writes, body decoding, or export. Keep `privacy: .private` annotations on user note content. Remove noisy temporary probes before finishing.
