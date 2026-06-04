import Foundation
import GRDB

// MARK: - AttachmentResolver

extension NoteStoreReader: AttachmentResolver {
    public func resolveInlineText(uuid: String) -> String? {
        guard let db = try? openDB() else { return nil }
        return try? db.read { conn in
            try String.fetchOne(
                conn,
                sql: "SELECT ZALTTEXT FROM ZICCLOUDSYNCINGOBJECT WHERE ZIDENTIFIER = ?",
                arguments: [uuid]
            )
        }
    }

    public func resolveTableData(uuid: String) -> Data? {
        guard let db = try? openDB() else { return nil }
        return try? db.read { conn in
            try Data.fetchOne(
                conn,
                sql: "SELECT ZMERGEABLEDATA1 FROM ZICCLOUDSYNCINGOBJECT WHERE ZIDENTIFIER = ?",
                arguments: [uuid]
            )
        }
    }

    public func resolveURLCard(uuid: String) -> (title: String, url: String)? {
        guard let db = try? openDB() else { return nil }
        return try? db.read { conn in
            let row = try Row.fetchOne(
                conn,
                sql: "SELECT ZTITLE, ZURLSTRING FROM ZICCLOUDSYNCINGOBJECT WHERE ZIDENTIFIER = ?",
                arguments: [uuid]
            )
            guard let row,
                  let title = row["ZTITLE"] as String?,
                  let url = row["ZURLSTRING"] as String? else { return nil }
            return (title: title, url: url)
        }
    }

    public func resolveInternalLink(uuid: String) -> String? {
        guard let db = try? openDB() else { return nil }
        return try? db.read { conn in
            guard let noteIdentifier = try String.fetchOne(
                conn,
                sql: "SELECT ZTOKENCONTENTIDENTIFIER FROM ZICCLOUDSYNCINGOBJECT WHERE ZIDENTIFIER = ?",
                arguments: [uuid]
            ) else { return nil }

            return try String.fetchOne(
                conn,
                sql: "SELECT ZTITLE1 FROM ZICCLOUDSYNCINGOBJECT WHERE ZIDENTIFIER = ?",
                arguments: [noteIdentifier]
            )
        }
    }
}
