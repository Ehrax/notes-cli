# notes-cli

Small, agent-first, pure-mechanism CLI over Apple Notes. Apple Notes is the sole source of truth: reads use its live database read-only and writes use ScriptingBridge.

Read `CONTEXT.md` before changing domain behavior and the applicable ADRs under `docs/adr/` before changing architecture.

## Non-negotiables

- Never write to `NoteStore.sqlite` or add a local note store, cache, mirror, index, sync step, or history.
- Keep the Objective-C `NotesCoreObjC` + generated `Notes.h` ScriptingBridge write path. The attempted pure-Swift element-creation path aborts.
- Never use ScriptingBridge's folder `move`; it marks the folder for deletion. Preserve the composed recreate → move notes → delete source flow from ADR 0002.
- Keep policy in the caller: no CLI confirmations or protected-folder guards.

## Commands

- `make test` — full serial suite; the CLI tests can deadlock under the parallel scheduler. Focus with `make test-core` or `make test-cli`.
- `make proto` — regenerate after editing `Proto/notestore.proto`; do not hand-edit generated output.
- `NOTES_CLI_LIVE_TESTS=1 make test-integration` — intentional real-Notes round-trips; requires Full Disk Access + Automation.
