# notes-cli

## Mission
- Build and maintain notes-cli as a fast, AI-native CLI for querying, syncing, tagging, linking, and exporting Apple Notes from the terminal.
- Keep the tool small, testable, and ready to grow without locking in premature architecture.
- Prefer reliable, native, simple behavior over clever abstractions. Stay especially careful around Apple Notes writes, sync/diffing, the rebuildable cache, action-log/undo integrity, and export fidelity.

## Tooling
- Use the `fff` MCP tools for all file search work: `find_files` for names, `grep` or `multi_grep` for contents.
- Prefer the repo-local `make` targets for building, running, and testing over ad hoc `swift build`/`swift test` flows; details are under the toolchain and testing sections below.
- After editing `Proto/notestore.proto`, regenerate the decoder with `make proto`; never hand-edit the generated `Sources/NotesCore/Protobuf/notestore.pb.swift`.
- Use the `tdd` skill for behavior changes, and consult `docs/` (architecture, design plans) before reshaping anything load-bearing.

## Source Of Truth
- CLI behavior: `Sources/NotesCLI/` (ArgumentParser commands, formatters, `GlobalOptions`)
- Library, models, services, and business logic: `Sources/NotesCore/`
- Service protocols: `Sources/NotesCore/Protocols/`; implementations: `Sources/NotesCore/Services/`
- Unit tests: `Tests/NotesCoreTests/` (library) and `Tests/NotesCLITests/` (CLI); integration: `Tests/NotesIntegrationTests/`; E2E smoke: `Tests/NotesE2ETests/`; shared mocks and factories: `Tests/NotesTestSupport/`
- Package configuration: `Package.swift`; build/test entrypoints: `Makefile`
- Architecture, design, and product notes: `docs/`; design plans: `docs/plans/`
- Apple Notes protobuf schema: `Proto/notestore.proto`

## Safety Guardrails
- Read current code before changing behavior. Fix root causes and preserve unrelated user changes.
- Treat Apple Notes as the source of truth and `~/.notes-cli/notes.db` as a rebuildable cache; never let a code path mutate the cache in a way that can't be reproduced from a sync.
- Writes to Apple Notes go through AppleScript via `NSAppleScript` only — never shell out to `osascript`/`Process`. Reads come from the read-only `NoteStore.sqlite` snapshot in `~/.notes-cli/cache/`; never write to that snapshot.
- Preserve action-log and undo integrity: any user-visible mutation (create/edit/delete/move/tag/link) must record an action so `notes-cli history` and `notes-cli undo` stay correct.
- Keep behavior in its owning layer: CLI commands wire arguments, options, and output; domain rules, models, persistence, sync, and formatting live in `NotesCore`, never inside command files.
- Do not bypass `SafetyService`/`ConfigService` boundaries or weaken Full Disk Access and destructive-operation checks.

## Architecture
- Preserve the existing app shape unless the task explicitly changes architecture; keep behavior native to a macOS command-line tool.
- Favor deep modules: put meaningful behavior behind small protocol interfaces with local invariants. Avoid shallow pass-through services that only move complexity around.
- Each service has a protocol in `NotesCore/Protocols/` with its implementation in `NotesCore/Services/`; access services through the `ServiceContainer` actor with `try await`.
- Keep the CLI layer thin: commands parse input and format output; they do not hold domain logic, SQL, or AppleScript.
- Do not define models, domain enums, reusable extensions, parsers, or formatting helpers inside command files; move them to `NotesCore/Models/`, `NotesCore/Extensions/`, `NotesCore/Utilities/`, or a focused service.
- Do not introduce a seam for theoretical flexibility. One adapter means hypothetical; two adapters means real.
- Make the protocol the test surface. If tests must reach past it, reconsider the boundary.
- When asked to improve architecture, first present deepening opportunities with files, problem, solution, and benefits before proposing concrete interfaces.
- Record load-bearing design decisions in `docs/architecture.md`, and check it before architecture changes.

## Engineering Discipline
- Write the smallest code that solves the requested problem. Do not add speculative features, abstractions, configuration, or extension points.
- Touch only what the request requires. Match existing style and local patterns.
- Remove only unused code introduced by your own change.
- If a change grows large, simplify before continuing.
- SwiftLint is enforced via the build plugin (`.swiftlint.yml`): line length 120 warn / 200 error, function body 50 / 100, type body 300 / 500, file length 500 / 1000, and no `force_unwrapping` or `implicitly_unwrapped_optional`. Let these limits drive splitting large files into focused siblings.
- When adding substantial behavior to an already large Swift file, prefer cohesive helpers or a focused sibling file in the same service/module.
- Every changed line should trace to the request, a failing test, or a required invariant.

## Workflow
- Read the current code and relevant design notes before changing behavior; preserve unrelated user changes.
- For behavior changes, bug fixes, and risky refactors, use the `tdd` skill: write one behavior-focused failing test, confirm it fails for the right reason, implement the smallest change, get it green, then repeat.
- For docs, mechanical cleanup, or low-risk formatter/output tweaks, use judgment instead of forcing test-first work.
- Keep tests focused on user-visible behavior, domain rules, persistence/sync boundaries, and regressions.
- Use focused `make test-core` / `make test-cli` runs while iterating; reach for `make test` and the integration/E2E gates when the scope justifies it.
- Choose verification commands that match the files and behavior changed. Prefer the repo-local `make` targets over ad hoc `swift build`/`swift test`.
- Keep commits small, conventional, and focused on one coherent step.
- Put a hard bound on commands that can hang or run open-ended. A 6-minute cap is the default; never leave sync watches, log follows, or interactive sessions running indefinitely.

## Output And Formatting
- notes-cli is scriptable: every command must produce clean, machine-readable output. Respect `GlobalOptions`, which auto-selects JSON when piped and a table on a TTY (`--format json|table|markdown` overrides).
- Send human and debug chatter to stderr (via `Log` with `--verbose`); keep stdout reserved for the command's actual result so pipes and `jq` stay clean.
- Models conform to GRDB's `FetchableRecord` + `PersistableRecord`; keep their `Codable`/JSON shape stable, since it is the public output contract.
- Use the `NotesError` enum for all errors so exit codes stay typed and meaningful.

## Toolchain
- Use the repo-local `make` targets, not raw `swift`/`xcodebuild` invocations, unless debugging the build itself: `make build` (debug), `make release`, `make run` / `make run-verbose`.
- One-time setup is `make setup` (resolves packages, checks for `protoc`, generates protobuf). Install codegen deps with `brew install protobuf swift-protobuf`.
- After editing `Proto/notestore.proto`, run `make proto` to regenerate `Sources/NotesCore/Protobuf/notestore.pb.swift`; never hand-edit the generated file.
- notes-cli reads the Apple Notes database directly, so it requires Full Disk Access for the terminal. If reads fail with permission errors, check that grant first, not the code.
- Use `make clean` to drop build artifacts, generated protobuf, and the local `~/.notes-cli/notes.db`; use `make clean-cache` to clear the cached `NoteStore.sqlite` snapshot.

## Testing
- Run the fast unit gates while iterating: `make test-core` for `NotesCore` library logic and `make test-cli` for CLI behavior.
- Run `make test` before closing a change; reach for `make test-integration` and `make test-e2e` when the change touches sync, persistence, AppleScript writes, or export end-to-end.
- Unit tests are mandatory after any implementation.
- Use the Swift Testing framework (`@Test`, `#expect`), not XCTest.
- Mock services through `ServiceContainer.override(...)` and `reset()` between tests; keep shared mocks and factories in `Tests/NotesTestSupport/`.
- Keep tests focused on user-visible behavior, domain rules, sync/persistence boundaries, and regressions.

## Debugging And Telemetry
- Use the `Log` helper (per-service `os.Logger`: sync, database, applescript, safety, config, reminders, general) for diagnostics; it integrates with Console.app and mirrors to stderr when `--verbose` is set.
- Reach for `make run-verbose` or `--verbose` as the primary debugging loop for sync, AppleScript writes, persistence, and data-flow problems.
- Add lightweight telemetry when behavior affects Apple Notes writes, sync/diffing, the action log, export, or hard-to-observe data flow.
- Prefer stable category and event names with useful context fields. Keep `privacy: .private` annotations on user note content. Remove noisy temporary probes before finishing unless they remain useful diagnostics.
- When debugging sync or cache behavior, record the cache/sync state in investigation notes and prefer a fresh `make clean-cache` snapshot for repeatability.
