# notes-cli — TODOs

Tracking what's missing from the [design doc](2026-03-08-notes-cli-cli-design.md).

Priority is the thing to follow here, not the old design-doc phase numbers.

- `P0` = most important now
- `P1` = next after that
- `P2+` = important, but not the current focus
- `Phase X` = original design-doc grouping only, kept as historical context

## Current Recommended Build Order

1. `P6.1` Agent-ready core CLI
2. `P6.2` Output quality and predictability
3. `P0` Claude/OpenCode skill on top of stable CLI primitives
4. `P6.3` Better authoring and mutation flows
5. `P6.4` Reliability and platform correctness
6. `P1` Templates
7. `P2` Triage
8. `P3` Dashboards / Weekly View / Focus
9. `P4` Visualization
10. `P5` Small gaps

## P0 — Claude Code Skill

Original design-doc grouping: Phase 4.

The "AI-native" part. Without this, notes-cli is just a CLI.

- [ ] Create agent skill via `/skill-creator` wrapping all CLI commands
- [ ] Conversational intent mapping ("make me a meal plan" → `notes-cli notes create ...`)
- [ ] Skill should handle multi-step workflows (search → read → edit)
- [ ] Skill should respect safety layer (protected folders, soft-delete)

## P1 — Templates

Original design-doc grouping: Phase 7.

Foundation for triage and dashboards. Users and AI can stamp out structured notes.

- [ ] `Template` model + DB migration (name, body template, folder hint, tags)
- [ ] `TemplateServiceProtocol` + `TemplateService`
- [ ] `notes-cli templates list` — show available templates
- [ ] `notes-cli templates create <name>` — create from existing note or inline
- [ ] `notes-cli templates use <name> --folder <folder>` — stamp out a new note
- [ ] Starter templates: "weekly-meal-plan", "project-kickoff", "journal-entry"
- [ ] Template variables (e.g. `{{date}}`, `{{project}}`) with auto-fill

## P2 — Triage

Original design-doc grouping: Phase 7.

The killer ADHD feature. AI sorts Inbox so the user doesn't have to decide.

- [ ] `notes-cli triage` — list Inbox notes with AI-suggested destinations
- [ ] `notes-cli triage --auto` — fully automatic (move without confirmation)
- [ ] Suggestion logic: folder match by content/tags, recent patterns, linked notes
- [ ] Needs Claude Code skill for AI reasoning (depends on P0)

## P3 — Dashboards, Weekly View & Focus

Original design-doc grouping: Phase 7.

Aggregated views across all notes. Progress tracking and WIP limits.

### Dashboard
- [ ] `notes-cli dashboard <project>` — checkbox progress for a project
- [ ] `notes-cli dashboard all` — all active projects overview
- [ ] Output as table (TTY) or JSON (piped)

### Weekly View
- [ ] `notes-cli week` — unified weekly todo snapshot from all notes
- [ ] Group by: Now / This Week / Done
- [ ] Show due dates, source note, folder
- [ ] Option to push as Apple Note for mobile access

### Focus Mode
- [ ] `notes-cli focus` — top 3 tasks right now (WIP limit)
- [ ] AI picks from all open todos by urgency/due date
- [ ] Now / Next / Done lanes
- [ ] Depends on Reminders sync for due dates

## P4 — Visualization

Future / not in scope now.

Lower priority. Explicitly "not in scope now" in the design doc.

- [ ] `notes-cli graph serve` — local web UI showing note link graph
- [ ] Obsidian-style backlinks view
- [ ] Smart templates (auto-fill context from linked notes)
- [ ] Progress tracking over time (weekly summaries, streaks)

## P5 — Small Gaps

- [ ] `notes-cli config` command (edit config interactively)
- [ ] Shareable blueprints: "freelancer notes-cli", "student notes-cli", "adhd notes-cli"

## P6 — Agent Workflow & CLI UX

This is the most important active area before building the skill.

Make `notes-cli` much better for AI-agent usage and faster human CLI exploration.

Recommended implementation order for better agent workflows:

1. Define the CLI contract and safety boundaries.
2. Ship lightweight `list`, `search`, and `show` primitives.
3. Add stable sorting, limits, filters, snippets, and pagination.
4. Improve note creation/edit input ergonomics.
5. Build the agent skill on top of stable primitives.

### P6.1 — Highest Priority: Agent-ready core CLI

- [ ] Define agent-first note discovery goals: title lookup, folder lookup, and fast full-text content lookup across the local index
- [ ] Define the agent-facing CLI contract first (inputs, outputs, defaults, safety boundaries)
- [ ] Implement the first agent-ready primitive set in order: `list`, `search`, then `show`
- [ ] Add `notes-cli notes list` ergonomics: `--limit`, `--fields`, `--group-by`, compact output
- [ ] Add `notes-cli notes search` ergonomics: `--limit`, `--fields`, `--snippet`, better sorting/filtering, and clear title-vs-body match behavior
- [ ] Add `notes-cli notes show <id>` modes for `--summary`, `--body`, and `--max-chars`
- [ ] Add lightweight note listing options to avoid huge payloads
- [ ] Evaluate a dedicated agent-consumption command surface, e.g. `notes-cli notes list --fields title,folder --limit 50`
- [ ] Define safe defaults for locked/sensitive notes in agent-facing flows

### P6.2 — High Priority: Output quality and predictability

- [ ] Consider pagination and stable deterministic sorting for large result sets
- [ ] Add search/list filters for folder, tag, modified date, and locked state
- [ ] Support snippets and match-context rendering for prettier search results
- [ ] Decide and document ranking strategy for search results so full-text content matches surface quickly and predictably for agents
- [ ] Explore CLI output extensions for agent-friendly formats (titles-only, compact list, folder-grouped, machine-readable summaries)
- [ ] Reduce the need for external `python3` glue by making common extraction/composition flows first-class in the CLI
- [ ] Document the intended agent workflow, CLI contract, and wishlist backlog in `docs/`

### P6.3 — Medium Priority: Better authoring and mutation flows

- [ ] Add better input ergonomics for note creation/editing, e.g. stdin, file input, or editor-friendly body flows
- [ ] Add support for creating notes at the selected-account root/default location without requiring `--folder`
- [ ] Add CLI support for creating folders/subfolders so project structures like `ehrax.dev/notes-cli/...` can be created without leaving `notes-cli`
- [ ] Explore Markdown or lightweight block authoring for note bodies, rendered into conservative Apple Notes-compatible HTML
- [ ] Reduce raw hand-written HTML in note creation/edit flows and prefer a more native-feeling authoring model
- [ ] Create an Apple Notes formatting style guide / mini design system for how agents should structure titles, headings, spacing, lists, dashboards, and summaries

### P6.4 — Medium Priority: Reliability and platform correctness

- [ ] Audit the whole app for remaining multi-account path/identity bugs across create, edit, move, delete, undo, and related flows
- [ ] Prevent concurrent `notes-cli sync` runs with a lock/mutex and a clear `sync already running` UX
- [ ] Investigate why `notes-cli sync` can appear complete but delay CLI process exit, and improve shutdown/phase logging
- [ ] Revisit sync architecture and performance so repeat syncs are much faster after the initial full sync
- [ ] Investigate why second/subsequent syncs are still slow and prioritize incremental-sync or change-detection improvements

### P6.5 — Lower Priority: Agent skill and smart navigation

- [ ] Design agent skill UX for working with `notes-cli` from the CLI
- [ ] Define skill capabilities: note discovery, filtering, safe reads, mutations, summarization rules
- [ ] Build the Claude/OpenCode skill only after the CLI primitives are stable
- [ ] Explore an explicit `--agent` mode or dedicated `notes-cli agent ...` command surface
- [ ] Explore fuzzy title matching and top-hit selection flows like `notes-cli notes pick <query>`
- [ ] Explore related-note discovery via links, tags, or folder proximity
- [ ] Explore saved searches and recent-notes shortcuts
