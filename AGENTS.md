# notes-cli

<!-- TOOLING START -->
For **any file search or grep in this repository**, use the `fff` MCP tools:
`find_files`, `grep`, or `multi_grep`. Do not use `rg`, `grep`, `find`, or other
default file-search tools when an `fff` tool can perform the operation.
<!-- TOOLING END -->

Small, fast, agent-first CLI over Apple Notes (create/read/edit/delete/move/search/organize/export) so LLMs and humans can drive Apple Notes from the terminal.

Domain language, invariants, and architecture: `CONTEXT.md` — read before changing load-bearing behavior. Design decisions: `docs/adr/`. Target scope: PRD `docs/plans/2026-06-01-notes-cli-direct-live-prd.md`.

## Status: migration substantially complete
Already deleted (do not reintroduce): the GRDB `notes.db` mirror + FTS5, `SyncService` / `sync` / `status`, `SafetyService` + undo/history/action log, tags, links, the AppleScript write path (`AppleScriptWriter`/`AppleScriptConstants`/`AppleScriptRunner`), Reminders/EventKit, `BlueprintService`, and HTML export. What ships now: live read-only SQLite reads, in-memory search, the ScriptingBridge (ObjC) write path, folder management, and JSON/Markdown export. See the PRD for the full target.

If you find code that contradicts the ADRs — a cache, a sync step, a tag/link table, an action log, an AppleScript writer — it is **legacy to delete, not a pattern to extend.**

## Footguns
- GRDB is a read-only SQLite driver only — never reintroduce a write/persistence layer, migrations, or FTS5.
- Do not reintroduce a cache, mirror, index, sync step, or history to "optimize." See ADR 0001 / CONTEXT.md.
- No interactive prompts or "are you sure" flows — the CLI is pure mechanism, the caller owns policy.
- Reading Apple's DB requires Full Disk Access; permission failures are a TCC grant problem, not a code bug.
- SwiftLint limits are enforced via the build plugin — see `.swiftlint.yml`.

## Commands
`make setup` (one-time: resolves packages, checks `protoc`, generates protobuf) · `make proto` (regenerate decoder after editing `Proto/notestore.proto`, never hand-edit the generated file) · `make test-core` / `make test-cli` (fast unit gates) · `make test-integration` / `make test-e2e` (ScriptingBridge writes, export end-to-end) · `make run-verbose` (debug loop).

<!-- MODEL TABLE START -->
## Picking models for delegated work

Scores are directional defaults, not benchmarks. Higher is better. Cost means lower
real subscription pressure, not lower API list price. Intelligence = how hard a problem
the model handles unsupervised. Taste = UI/UX, code quality, API design, and copy. New
model scores are provisional until repeated project work gives us better evidence.

| model           | cost | intelligence | taste |
|-----------------|------|--------------|-------|
| gpt-5.6-sol     | 5    | 10           | 8     |
| fable-5         | 2    | 9            | 9     |
| gpt-5.6-terra   | 8    | 8            | 7     |
| gpt-5.6-luna    | 10   | 6            | 6     |
| opus-4.8        | 4    | 7            | 8     |
| sonnet-5        | 6    | 5            | 7     |

- Don't start dev servers (assume one is already running) and don't run builds unless told — verify with the project's check commands (typecheck, lint, tests).
- If asked to do too much work at once, stop and state that clearly.
- Use Codex-based computer use only when the user explicitly requests it. Do not route GUI, browser, screenshot, or visual-verification work through Codex merely because computer use would help.
- Defaults, not limits: if a cheaper model's output misses the bar, redo with a smarter one without asking. Judge the output, not the price tag.
- When axes conflict for anything that ships: intelligence > taste > cost.
- Tight, mechanical work (clear-spec implementation, migrations, data passes, commit/push sweeps): gpt-5.6-luna. Escalate to Terra if the task stops being mechanical.
- Default backend and logic driver (services, data, glue, and logic inside frontend code): gpt-5.6-terra.
- Hard unsupervised work, architecture, difficult debugging, and final high-stakes review: gpt-5.6-sol.
- Anything user-facing (UI, copy, API design) needs taste ≥ 7: fable-5 when quality matters most; opus-4.8 by default; Sol for work that also needs maximum reasoning; Terra or sonnet-5 as budget options.
- Reviews of plans or implementations: gpt-5.6-sol, with fable-5 or opus-4.8 as the independent taste-and-design perspective.
- Also on the Codex account (via `codex -m`): gpt-5.5, gpt-5.4, gpt-5.4-mini, and gpt-5.3-codex-spark. The user invokes these explicitly; don't auto-pick them.
- Mechanics: GPT models run through the Codex CLI (`codex exec` / `codex review`); Claude models run via the Agent/Workflow `model` parameter. Full delegation playbook: the `orchestrate` skill.
<!-- MODEL TABLE END -->
