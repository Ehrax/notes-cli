#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The single write path to Apple Notes, via ScriptingBridge (ADR 0002).
///
/// These functions wrap the generated Notes ScriptingBridge interface, which pure Swift
/// cannot drive (the element classes have no compiled symbols, and creation needs
/// `[[cls alloc] initWithProperties:]`). The Swift `ScriptingBridgeWriter` resolves folder
/// paths against the configured scope and calls in here.
///
/// `accountName` nil/empty selects the default account. `folderPath` is account-relative,
/// "/"-delimited; empty means the account root. Notes are addressed by their
/// `x-coredata://…/ICNote/p<pk>` id (the same id the SQLite reader emits).
extern NSString *const NotesScriptingBridgeErrorDomain;

/// Name of the default Notes account, or nil if Notes/Automation is unreachable.
NSString *_Nullable NotesSBDefaultAccountName(void);

/// Create a note; returns its new x-coredata id, or nil + error.
NSString *_Nullable NotesSBCreateNote(NSString *_Nullable accountName,
                                      NSString *folderPath,
                                      NSString *title,
                                      NSString *bodyHTML,
                                      NSError *_Nullable *_Nullable error);

/// Update a note's title and/or body (nil = leave unchanged).
BOOL NotesSBUpdateNote(NSString *noteID,
                       NSString *_Nullable title,
                       NSString *_Nullable bodyHTML,
                       NSError *_Nullable *_Nullable error);

/// Delete a note (moves to Apple's Recently Deleted).
BOOL NotesSBDeleteNote(NSString *noteID, NSError *_Nullable *_Nullable error);

/// Move a note to the resolved destination folder (or account root).
BOOL NotesSBMoveNote(NSString *noteID,
                     NSString *_Nullable accountName,
                     NSString *folderPath,
                     NSError *_Nullable *_Nullable error);

/// Create a folder, optionally nested under `parentPath` (nil = account root).
BOOL NotesSBCreateFolder(NSString *_Nullable accountName,
                         NSString *_Nullable parentPath,
                         NSString *name,
                         NSError *_Nullable *_Nullable error);

/// Rename the folder at `path` (account-relative, "/"-delimited) to `newName`.
BOOL NotesSBRenameFolder(NSString *_Nullable accountName,
                         NSString *path,
                         NSString *newName,
                         NSError *_Nullable *_Nullable error);

/// Delete the folder at `path` (moves to Apple's Recently Deleted).
BOOL NotesSBDeleteFolder(NSString *_Nullable accountName,
                         NSString *path,
                         NSError *_Nullable *_Nullable error);

/// Move the folder at `path` into the destination container at `destParentPath`
/// (nil/empty = account root).
BOOL NotesSBMoveFolder(NSString *_Nullable accountName,
                       NSString *path,
                       NSString *_Nullable destParentPath,
                       NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END
