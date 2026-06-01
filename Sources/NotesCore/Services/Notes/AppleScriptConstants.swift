import Foundation

// swiftlint:disable line_length

/// All AppleScript source strings as static constants.
/// Uses `%@` style placeholders replaced before execution.
public enum AppleScriptConstants {
    private static func targetAccountHelper(accountName: String?) -> String {
        let sanitizedAccountName = (accountName ?? "").sanitizedForAppleScript
        return """
        on notes-cli_target_account()
            tell application "Notes"
                if "\(sanitizedAccountName)" is not "" then
                    try
                        return first account whose name is "\(sanitizedAccountName)"
                    on error
                        error "Notes account not found: \(sanitizedAccountName)"
                    end try
                end if

                try
                    return default account
                on error
                    error "No Apple Notes accounts available"
                end try
            end tell
        end notes-cli_target_account
        """
    }

    private static func folderPathHelpers(accountName: String?) -> String {
        """
        \(targetAccountHelper(accountName: accountName))
        on notes-cli_path_for_folder(aFolder)
            tell application "Notes"
                set pathParts to {name of aFolder}
                set currentContainer to container of aFolder
                repeat
                    if class of currentContainer is folder then
                        set beginning of pathParts to name of currentContainer
                        set currentContainer to container of currentContainer
                    else if class of currentContainer is account then
                        set beginning of pathParts to name of currentContainer
                        exit repeat
                    else
                        exit repeat
                    end if
                end repeat
            end tell

            set previousDelimiters to AppleScript's text item delimiters
            set AppleScript's text item delimiters to "/"
            set folderPath to pathParts as text
            set AppleScript's text item delimiters to previousDelimiters
            return folderPath
        end notes-cli_path_for_folder

        on notes-cli_parent_path_for_folder(aFolder)
            tell application "Notes"
                try
                    set currentContainer to container of aFolder
                    if class of currentContainer is folder then
                        return my notes-cli_path_for_folder(currentContainer)
                    end if
                end try
            end tell
            return ""
        end notes-cli_parent_path_for_folder

        on notes-cli_relative_folder_path(folderPath, accountName)
            set previousDelimiters to AppleScript's text item delimiters
            set AppleScript's text item delimiters to "/"
            set pathParts to every text item of folderPath
            set AppleScript's text item delimiters to previousDelimiters

            if (count of pathParts) > 0 and item 1 of pathParts is accountName then
                if (count of pathParts) is 1 then
                    return ""
                end if
                set pathParts to items 2 thru -1 of pathParts
            end if

            if (count of pathParts) > 0 then
                tell application "Notes" to set accountNames to name of every account
                if (item 1 of pathParts) is in accountNames then
                    error "Folder path belongs to a different account: " & folderPath
                end if
            end if

            set previousDelimiters to AppleScript's text item delimiters
            set AppleScript's text item delimiters to "/"
            set relativePath to pathParts as text
            set AppleScript's text item delimiters to previousDelimiters
            return relativePath
        end notes-cli_relative_folder_path

        on notes-cli_folder_for_path(folderPath)
            tell application "Notes"
                set targetAccount to my notes-cli_target_account()
                set relativePath to my notes-cli_relative_folder_path(folderPath, name of targetAccount)
                if relativePath is "" then
                    return targetAccount
                end if

                set previousDelimiters to AppleScript's text item delimiters
                set AppleScript's text item delimiters to "/"
                set pathParts to every text item of relativePath
                set AppleScript's text item delimiters to previousDelimiters

                set currentContainer to targetAccount
                repeat with folderName in pathParts
                    set matchingFolders to folders of currentContainer whose name is (contents of folderName)
                    if (count of matchingFolders) is 0 then
                        error "Folder not found: " & folderPath
                    end if
                    set currentContainer to item 1 of matchingFolders
                end repeat
                return currentContainer
            end tell
        end notes-cli_folder_for_path
        """
    }

    /// Create a note. First `%@` = folder path, second = title, third = body HTML.
    public static func createNote(accountName: String?) -> String {
        """
        \(folderPathHelpers(accountName: accountName))
        tell application "Notes"
            set targetFolder to my notes-cli_folder_for_path("%@")
            tell targetFolder
                make new note with properties {name:"%@", body:"%@"}
                return id of result
            end tell
        end tell
        """
    }

    /// Update a note. First `%@` = note ID, second = new title, third = new body HTML.
    public static let updateNote = """
        tell application "Notes"
            set aNote to note id "%@"
            set name of aNote to "%@"
            set body of aNote to "%@"
        end tell
        """

    /// Update note title only. First `%@` = note ID, second = new title.
    public static let updateNoteTitle = """
        tell application "Notes"
            set aNote to note id "%@"
            set name of aNote to "%@"
        end tell
        """

    /// Update note body only. First `%@` = note ID, second = new body HTML.
    public static let updateNoteBody = """
        tell application "Notes"
            set aNote to note id "%@"
            set body of aNote to "%@"
        end tell
        """

    /// Delete a note. Replace `%@` with the note ID.
    public static let deleteNote = """
        tell application "Notes"
            delete note id "%@"
        end tell
        """

    /// Move a note. First `%@` = folder path, second = note ID.
    public static func moveNote(accountName: String?) -> String {
        """
        \(folderPathHelpers(accountName: accountName))
        tell application "Notes"
            set targetFolder to my notes-cli_folder_for_path("%@")
            move note id "%@" to targetFolder
        end tell
        """
    }

    /// Create a top-level folder in the scoped account. Replace `%@` with folder name.
    public static func createFolder(accountName: String?) -> String {
        """
        \(folderPathHelpers(accountName: accountName))
        tell application "Notes"
            set targetAccount to my notes-cli_target_account()
            tell targetAccount
                make new folder with properties {name:"%@"}
            end tell
        end tell
        """
    }

    /// Create a subfolder. First `%@` = parent folder path, second = new folder name.
    public static func createSubfolder(accountName: String?) -> String {
        """
        \(folderPathHelpers(accountName: accountName))
        tell application "Notes"
            set parentFolder to my notes-cli_folder_for_path("%@")
            tell parentFolder
                make new folder with properties {name:"%@"}
            end tell
        end tell
        """
    }

}

// swiftlint:enable line_length
