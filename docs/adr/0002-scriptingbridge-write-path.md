# ScriptingBridge is the single write path

All writes to Apple Notes go through **ScriptingBridge**, but driven from a small Objective-C target (`NotesCoreObjC`) built around the **generated `Notes.h`** scripting interface — *not* from hand-written `@objc` protocol shims on `SBApplication`/`SBObject`. The previous string-templated AppleScript path (`AppleScriptWriter`, `AppleScriptConstants`, `AppleScriptRunner`, `String.sanitizedForAppleScript`) is deleted — there is no AppleScript fallback.

## Why ObjC, not pure Swift

Creating elements on a generic `SBApplication` (`make new note`, `make new folder`) requires the **generated, app-specific scripting interface** — the `Notes.h` header generated from Notes.app's `.sdef` (`sdef /Applications/Notes.app | sdp -fh --basename Notes`). Pure Swift cannot drive this:

- There are **no class symbols** to link against; the SB classes are synthesized at runtime.
- You **cannot `alloc`** on the SB pseudo-class from Swift. We tried hand-written `@objc` protocols on `SBApplication`/`SBObject` and `perform("alloc")`; that broke ScriptingBridge's message forwarding and **aborts** the process the moment you allocate a note.

So the writer logic that touches SB element creation lives in Objective-C, compiled against the generated `Notes.h`. Swift owns only what it does well: it resolves the target scope (account + `/`-delimited folder path) and calls a thin C API exposed by `NotesCoreObjC`; the ObjC side does the `[[NotesNote alloc] init...]` / `make`-equivalent SB calls.

We considered keeping AppleScript as a fallback and rejected it: a second, non-default write path bit-rots, and "one way to do each thing" matters more than a safety net for a personal tool. AppleScript was evaluated and **removed**.

## Consequences

- A future reader will find an **ObjC target (`NotesCoreObjC`) inside a Swift package**, built against a generated `Notes.h`. It exists only because ScriptingBridge element creation is impossible from pure Swift. Do not "clean it up" by porting it back to `@objc` protocol shims — that path was tried and aborts.
- ScriptingBridge uses the same Apple Events bus as AppleScript, so the **Automation TCC permission requirement is unchanged** — this is not a permission bypass.
- **R2 — `container == nil`.** A freshly created/moved SB note proxy returns `container == nil` until re-resolved; verify folder placement by counting `folder.notes()` or via a live read, **not** by reading `note.container`.
- **R3 — post-write staleness.** After a write, the live read snapshot may be briefly stale (async write + WAL flush); reads `refresh()` with a short retry.
- **No folder-move primitive.** Apple's scripting `move` command (what `moveTo:` and collection `addObject:` both compile to) **marks a folder for deletion instead of re-parenting it** — verified: the moved folder's row gets `zmarkedfordeletion=1`, so it lands in Recently Deleted and vanishes from reads. `container` is read-only, so there is no settable re-parent either. A folder move is therefore *composed in Swift* (`DirectNotesService.moveFolder` + `FolderMovePlanner`): recreate the source folder and its descendants under the new parent, move every note in (note ids survive a `moveTo:`), then delete the emptied source. Consequences: note ids are preserved but **folder ids change**, and the move is **not atomic** — a mid-way failure throws *before* the source is deleted, so notes are never lost.
- **HTML heading flattening.** Apple's HTML-`body` importer stores **no paragraph style** for `<h1>/<h2>/<h3>` — it renders them as **bold** runs. The note looks right in Notes.app, but a read-back (`notes read`, `export`) surfaces those headings as bold, not Markdown `#`/`##`; the heading level is unrecoverable because it was never stored (the title even merges into the first heading). Bold, italic, underline (→ bold), strikethrough, lists, and links round-trip. There is no scripting API to set paragraph styles, so this is a hard limitation of the write path — **not** a `ProtobufToMarkdown` reader bug. The reader's heading tests pass on synthetic protobuf with explicit `styleType`s, which the importer never actually produces.
