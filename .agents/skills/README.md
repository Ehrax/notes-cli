# Obsidian Vault Skills

A suite of Claude Code skills for managing an Obsidian knowledge base — from initial migration to ongoing maintenance.

## The Pipeline

```
Apple Notes ──→ notes-migration ──→ wikilink-cross-reference ──→ Obsidian vault
   (raw)         (clean + sort)       (linked + hub notes)        (ready to use)
```

After setup, the ongoing workflow:

```
You write notes in Inbox/
        │
        ├── /obsidian-capture  (instant — create + sort + quick-link)
        ├── /obsidian-sort     (batch — triage inbox)
        │
        ├── /obsidian-relink   (weekly — find new connections)
        ├── /obsidian-health   (monthly — check for issues)
        │
        └── /obsidian-sync     (all-in-one — sort + relink + health)
```

## Skills

### One-Time Setup

| Skill | Command | Purpose |
|-------|---------|---------|
| **notes-migration** | `/notes-migration` | Migrate messy notes from Apple Notes (or other tools) into clean, well-structured markdown. Fixes headings, lists, spacing, bold. Organizes into PARA-lite folders. |
| **wikilink-cross-reference** | `/wikilink-cross-reference` | Deep analysis of entire vault. Reads all notes, discovers patterns, creates hub notes (MOCs) + insight notes, inserts [[wikilinks]] everywhere. The "big brain" pass. |

### Daily Use

| Skill | Command | Purpose |
|-------|---------|---------|
| **obsidian-capture** | `/obsidian-capture` | Capture an idea or thought → creates a properly formatted note, sorts it into the right folder, quick-links to related notes. Zero friction. |
| **obsidian-sort** | `/obsidian-sort` | Sort inbox notes into the right folders. Interactive — one note at a time or batch mode. Applies style fixes along the way. |

### Maintenance

| Skill | Command | Purpose |
|-------|---------|---------|
| **obsidian-relink** | `/obsidian-relink` | Incremental relinking after adding new notes. Updates hub notes, extends insight notes, finds new connections. Fast — only processes what changed. |
| **obsidian-health** | `/obsidian-health` | Vault diagnostic. Finds orphan notes, broken links, stale hubs, inbox buildup. Suggests and applies fixes. |
| **obsidian-sync** | `/obsidian-sync` | All-in-one weekly maintenance. Runs sort → relink → health in a single pass. The "keep my vault healthy" command. |

## Prerequisites

- **notes-migration** + **wikilink-cross-reference**: Work on raw files, no Obsidian needed
- **obsidian-*** skills: Require Obsidian running with [obsidian-cli](https://github.com/Obsidian-CLI/obsidian-cli) installed

## Recommended Workflow

### Initial Setup (once)
1. `/notes-migration` — clean and organize your exported notes
2. Open the vault in Obsidian
3. `/wikilink-cross-reference` — deep pattern analysis + linking

### Ongoing (your rhythm)
- **When you have an idea**: `/obsidian-capture`
- **When inbox has 5+ notes**: `/obsidian-sort`
- **Weekly/bi-weekly**: `/obsidian-sync`
- **Monthly**: `/obsidian-health` (or just rely on sync)

### Philosophy

> Human writes the vault. Agents read it, suggest, execute.
> Your voice stays yours. The AI only adds structure and connections.
