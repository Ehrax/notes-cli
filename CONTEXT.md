# notes-cli

An agent-first CLI over Apple Notes. Apple Notes is the single source of truth; the CLI reads it live and writes back through Apple's scripting bus. There is no local copy of note content.

## Language

**Apple Notes**:
The system of record for all note content, folders, tags, and links. Everything the CLI shows is derived from it live; nothing authoritative lives only in the CLI.
_Avoid_: "the backend", "the store" (ambiguous with the snapshot).

**NoteStore**:
Apple's own `NoteStore.sqlite` (in `~/Library/Group Containers/group.com.apple.notes/`). notes-cli opens it **directly, read-only, with no copy** — there is no cache, mirror, or snapshot. Every read goes straight to the live file.
_Avoid_: "cache", "mirror", "snapshot", "notes.db" — none of these exist anymore; reads are live.

**Note**:
A single Apple Notes note, identified by its Apple Notes ID. Body is decoded live from gzipped protobuf into Markdown.

**Folder**:
An Apple Notes folder, identified by its qualified path within an account (e.g. `Projects/notes-cli`). May nest.

**Hashtag**:
A `#word` that lives inline in a note's body, owned entirely by Apple Notes. notes-cli has **no tag concept of its own** — there is no `tag`/`untag`/`tags` command and no tag index. A hashtag is just body text; `search "#work"` matches it like any other string. (The reader no longer strips hashtags so they survive in output.)
_Avoid_: "tag" as a notes-cli feature — there isn't one.

**Link**:
A native Apple Notes note-to-note reference. notes-cli has **no link concept of its own** — no `link`/`links` command, no backlink index. Native links that already exist in a body render as Markdown links on read; that's the extent of it.
_Avoid_: implying notes-cli stores or creates links.

## Example dialogue

**Dev:** "When I run `notes-cli notes search foo`, what does it read?"
**Owner:** "Apple's `NoteStore.sqlite` directly, read-only — no copy, no cache. We open the live file, decode the bodies we need, and search. Apple Notes is always the source of truth; we never keep our own copy."
**Dev:** "And if I `tag` a note?"
**Owner:** "That writes a `#hashtag` into the body in Apple Notes. There's no separate tag list anymore — the hashtag *is* the tag, same as you'd see it in Notes.app on your phone."
