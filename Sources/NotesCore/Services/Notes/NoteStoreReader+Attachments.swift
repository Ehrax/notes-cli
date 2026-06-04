import Foundation
import GRDB

// MARK: - Attachments

extension NoteStoreReader {
    /// Find the account UUID for a given note Z_PK via zowner column.
    func resolveAccountUUIDForNote(
        notePK: Int,
        accounts: [Int: AccountInfo],
        conn: Database
    ) throws -> String? {
        // Notes don't have ZOWNER directly; they have ZFOLDER -> folder has ZOWNER -> account.
        let rows = try Row.fetchAll(
            conn,
            sql: """
                SELECT f.zowner FROM ziccloudsyncingobject n
                JOIN ziccloudsyncingobject f ON f.z_pk = n.zfolder
                WHERE n.z_pk = ?
                """,
            arguments: [Int64(notePK)]
        )
        if let ownerPK = (rows.first?[0] as Int64?).map({ Int($0) }) {
            return accounts[ownerPK]?.identifier
        }
        return nil
    }

    func queryAttachments(
        conn: Database,
        noteID: String,
        notePK: Int,
        acctUUID: String?,
        attachEnt: Int64,
        mediaEnt: Int64
    ) throws -> [NoteAttachment] {
        let rows = try Row.fetchAll(
            conn,
            sql: """
                SELECT zidentifier, ztypeuti, zmedia
                FROM ziccloudsyncingobject
                WHERE z_ent = ? AND znote = ?
                """,
            arguments: [attachEnt, Int64(notePK)]
        )

        return try rows.compactMap { row -> NoteAttachment? in
            guard let attachUUID = row[0] as String? else { return nil }
            let typeUTI = row[1] as String?
            let mediaPK = (row[2] as Int64?).map({ Int($0) })

            let (filename, relativePath) = try resolveMediaPath(
                attachUUID: attachUUID,
                mediaPK: mediaPK,
                acctUUID: acctUUID,
                mediaEnt: mediaEnt,
                conn: conn
            )

            return NoteAttachment(
                id: attachUUID,
                noteID: noteID,
                filename: filename,
                typeUTI: typeUTI,
                relativePath: relativePath
            )
        }
    }

    func resolveMediaPath(
        attachUUID: String,
        mediaPK: Int?,
        acctUUID: String?,
        mediaEnt: Int64,
        conn: Database
    ) throws -> (filename: String?, relativePath: String) {
        guard let mediaPK else {
            return (nil, "Attachments/\(attachUUID)")
        }

        let mediaRows = try Row.fetchAll(
            conn,
            sql: """
                SELECT zidentifier, zfilename, zgeneration1
                FROM (SELECT *, NULL AS zgeneration1 FROM ziccloudsyncingobject)
                WHERE z_ent = ? AND z_pk = ?
                """,
            arguments: [mediaEnt, Int64(mediaPK)]
        )

        guard let mediaRow = mediaRows.first else {
            return (nil, "Attachments/\(attachUUID)")
        }

        let mediaUUID = mediaRow[0] as String? ?? attachUUID
        let filename = mediaRow[1] as String?
        let generation = mediaRow[2] as String?

        let base: String
        if let acctUUID {
            base = "Accounts/\(acctUUID)/Media/\(mediaUUID)"
        } else {
            base = "Media/\(mediaUUID)"
        }

        let relativePath: String
        if let gen = generation, !gen.isEmpty, let file = filename {
            relativePath = "\(base)/\(gen)/\(file)"
        } else if let file = filename {
            relativePath = "\(base)/\(file)"
        } else {
            relativePath = base
        }

        return (filename, relativePath)
    }
}
