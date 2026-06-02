#import "NotesScriptingBridge.h"
#import "Notes.h"
#import <ScriptingBridge/ScriptingBridge.h>

NSString *const NotesScriptingBridgeErrorDomain = @"NotesScriptingBridge";

/// Accounts and folders both expose `folders`/`notes` element arrays.
@protocol NCNavigable <NSObject>
- (SBElementArray *)folders;
- (SBElementArray *)notes;
@end

static NSError *NCError(NSString *message) {
    return [NSError errorWithDomain:NotesScriptingBridgeErrorDomain
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NotesApplication *NCApp(void) {
    return [SBApplication applicationWithBundleIdentifier:@"com.apple.Notes"];
}

static NotesAccount *_Nullable NCResolveAccount(NotesApplication *app, NSString *_Nullable accountName) {
    if (accountName.length > 0) {
        for (NotesAccount *account in app.accounts) {
            if ([account.name isEqualToString:accountName]) {
                return account;
            }
        }
        return nil;
    }
    return app.defaultAccount;
}

/// Walk a "/"-delimited account-relative path to the target account or folder.
static SBObject *_Nullable NCResolveContainer(NotesApplication *app,
                                              NSString *_Nullable accountName,
                                              NSString *relPath,
                                              NSError **error) {
    NotesAccount *account = NCResolveAccount(app, accountName);
    if (!account) {
        if (error) { *error = NCError(@"account not found"); }
        return nil;
    }
    SBObject *current = (SBObject *)account;
    if (relPath.length == 0) {
        return current;
    }
    for (NSString *component in [relPath componentsSeparatedByString:@"/"]) {
        if (component.length == 0) { continue; }
        NotesFolder *match = nil;
        for (NotesFolder *folder in [(id<NCNavigable>)current folders]) {
            if ([folder.name isEqualToString:component]) { match = folder; break; }
        }
        if (!match) {
            if (error) { *error = NCError([NSString stringWithFormat:@"folder not found: %@", relPath]); }
            return nil;
        }
        current = (SBObject *)match;
    }
    return current;
}

static NotesNote *_Nullable NCResolveNote(NotesApplication *app, NSString *noteID) {
    NotesNote *note = [[app notes] objectWithID:noteID];
    // Force evaluation: a specifier for a missing note yields a nil name.
    if (note == nil || note.name == nil) { return nil; }
    return note;
}

NSString *_Nullable NotesSBDefaultAccountName(void) {
    NotesAccount *account = NCApp().defaultAccount;
    return account ? account.name : nil;
}

NSString *_Nullable NotesSBCreateNote(NSString *_Nullable accountName,
                                      NSString *folderPath,
                                      NSString *bodyHTML,
                                      NSError **error) {
    NotesApplication *app = NCApp();
    SBObject *container = NCResolveContainer(app, accountName, folderPath, error);
    if (!container) { return nil; }
    Class noteClass = [app classForScriptingClass:@"note"];
    // Set `body` only: Apple derives the title from its first line. Setting `name` too
    // renders the title twice.
    NotesNote *note = [[noteClass alloc] initWithProperties:@{@"body": bodyHTML}];
    [[(id<NCNavigable>)container notes] addObject:note];
    NSString *newID = note.id;
    if (newID.length == 0) {
        if (error) { *error = NCError(@"note created but id unavailable"); }
        return nil;
    }
    return newID;
}

BOOL NotesSBUpdateNote(NSString *noteID, NSString *_Nullable title, NSString *_Nullable bodyHTML, NSError **error) {
    NotesNote *note = NCResolveNote(NCApp(), noteID);
    if (!note) {
        if (error) { *error = NCError(@"note not found"); }
        return NO;
    }
    if (bodyHTML != nil) { note.body = bodyHTML; }
    if (title != nil) { note.name = title; }
    return YES;
}

BOOL NotesSBDeleteNote(NSString *noteID, NSError **error) {
    NotesNote *note = NCResolveNote(NCApp(), noteID);
    if (!note) {
        if (error) { *error = NCError(@"note not found"); }
        return NO;
    }
    [note delete];
    return YES;
}

BOOL NotesSBMoveNote(NSString *noteID, NSString *_Nullable accountName, NSString *folderPath, NSError **error) {
    NotesApplication *app = NCApp();
    NotesNote *note = NCResolveNote(app, noteID);
    if (!note) {
        if (error) { *error = NCError(@"note not found"); }
        return NO;
    }
    SBObject *container = NCResolveContainer(app, accountName, folderPath, error);
    if (!container) { return NO; }
    [note moveTo:container];
    return YES;
}

BOOL NotesSBCreateFolder(NSString *_Nullable accountName, NSString *_Nullable parentPath, NSString *name, NSError **error) {
    NotesApplication *app = NCApp();
    SBObject *parent;
    if (parentPath.length > 0) {
        parent = NCResolveContainer(app, accountName, parentPath, error);
        if (!parent) { return NO; }
    } else {
        parent = (SBObject *)NCResolveAccount(app, accountName);
        if (!parent) {
            if (error) { *error = NCError(@"account not found"); }
            return NO;
        }
    }
    Class folderClass = [app classForScriptingClass:@"folder"];
    NotesFolder *folder = [[folderClass alloc] initWithProperties:@{@"name": name}];
    [[(id<NCNavigable>)parent folders] addObject:folder];
    return YES;
}

/// Resolve a non-empty "/"-delimited path to the folder it names.
static NotesFolder *_Nullable NCResolveFolder(NotesApplication *app,
                                              NSString *_Nullable accountName,
                                              NSString *path,
                                              NSError **error) {
    if (path.length == 0) {
        if (error) { *error = NCError(@"folder path is empty"); }
        return nil;
    }
    SBObject *resolved = NCResolveContainer(app, accountName, path, error);
    if (!resolved) { return nil; }
    return (NotesFolder *)resolved;
}

BOOL NotesSBRenameFolder(NSString *_Nullable accountName, NSString *path, NSString *newName, NSError **error) {
    NotesFolder *folder = NCResolveFolder(NCApp(), accountName, path, error);
    if (!folder) { return NO; }
    folder.name = newName;
    return YES;
}

BOOL NotesSBDeleteFolder(NSString *_Nullable accountName, NSString *path, NSError **error) {
    NotesFolder *folder = NCResolveFolder(NCApp(), accountName, path, error);
    if (!folder) { return NO; }
    [folder delete];
    return YES;
}

// NOTE: No NotesSBMoveFolder. Apple Notes' scripting `move` command marks a folder for deletion
// rather than re-parenting it (verified: the moved folder gets zmarkedfordeletion=1), so folder
// moves are composed in Swift from create + per-note move + delete. See ADR 0002.
