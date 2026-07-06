# notes-cli

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

## Picking models for delegated work

Rankings, higher = better. Cost reflects real subscription pressure, not list price.
Intelligence = how hard a problem the model handles unsupervised. Taste = UI/UX, code
quality, API design, copy.

| model     | cost | intelligence | taste |
|-----------|------|--------------|-------|
| gpt-5.5   | 7    | 8            | 5     |
| opus-4.8  | 4    | 7            | 8     |
| sonnet-5  | 6    | 5            | 7     |

- Don't start dev servers (assume one is already running) and don't run builds unless told — verify with the project's check commands (typecheck, lint, tests).
- If asked to do too much work at once, stop and state that clearly.
- If computer use helps to complete or verify work (clicking through a UI, screenshots), shell out to gpt-5.5 with codex — it has built-in computer use.
- Defaults, not limits: if a cheaper model's output misses the bar, redo with a smarter one without asking. Judge the output, not the price tag.
- When axes conflict for anything that ships: intelligence > taste > cost.
- Bulk/mechanical with a tight brief (clear-spec implementation, migrations, commit/push sweeps): gpt-5.5. Never pick haiku on your own — the user invokes it explicitly when wanted.
- Anything user-facing (UI, copy, API design) needs taste ≥ 7: opus-4.8, sonnet-5 as budget option.
- Default driver split: gpt-5.5 drives backend and logic work (services, data, glue — including logic inside frontend code); Claude drives frontend/visual work.
- Reviews of plans/implementations: opus-4.8, plus gpt-5.5 as an independent second perspective.
- Also on the codex account (via `codex -m`): gpt-5.4, gpt-5.4-mini, gpt-5.3-codex-spark (very fast execution) — the user invokes these explicitly; don't auto-pick them.
- Mechanics: gpt-5.5 only via the codex CLI (`codex exec` / `codex review`); Claude models via the Agent/Workflow `model` parameter. Full delegation playbook: the `orchestrate` skill.
