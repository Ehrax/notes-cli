import Foundation
import GRDB

// swiftlint:disable function_body_length

enum NotesCLIMigrations {
    static let migrationNames = [
        "v1_createNotes",
        "v2_createFolders",
        "v3_createTags",
        "v4_createLinks",
        "v5_createActionLog",
        "v6_createSyncState",
        "v7_createFTS5",
        "v8_relaxActionLogNoteForeignKey",
        "v9_switchToMarkdownBody",
        "v10_switchToProtobufBody",
    ]

    static func registerAll(in migrator: inout DatabaseMigrator) {
        // v1: Notes table
        migrator.registerMigration(migrationNames[0]) { database in
            try database.create(table: "note") { table in
                table.primaryKey("id", .text)
                table.column("title", .text).notNull()
                table.column("bodyHTML", .text).notNull()
                table.column("bodyPlaintext", .text).notNull()
                table.column("folderPath", .text).notNull()
                table.column("creationDate", .datetime).notNull()
                table.column("modificationDate", .datetime).notNull()
                table.column("isLocked", .boolean).notNull().defaults(to: false)
                table.column("checksum", .text).notNull()
                table.column("syncedAt", .datetime).notNull()
            }
            try database.create(indexOn: "note", columns: ["folderPath"])
            try database.create(indexOn: "note", columns: ["modificationDate"])
        }

        // v2: Folders table
        migrator.registerMigration(migrationNames[1]) { database in
            try database.create(table: "folder") { table in
                table.primaryKey("id", .text)
                table.column("name", .text).notNull()
                table.column("path", .text).notNull().unique()
                table.column("parentPath", .text)
                table.column("icon", .text)
                table.column("isProtected", .boolean).notNull().defaults(to: false)
                table.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
        }

        // v3: Tags + NoteTags with foreign keys and ON DELETE CASCADE
        migrator.registerMigration(migrationNames[2]) { database in
            try database.create(table: "tag") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("name", .text).notNull().unique()
            }

            try database.create(table: "noteTag") { table in
                table.primaryKey {
                    table.column("noteID", .text).notNull()
                        .references("note", onDelete: .cascade)
                    table.column("tagID", .integer).notNull()
                        .references("tag", onDelete: .cascade)
                }
            }
        }

        // v4: Links with foreign keys, unique constraint, indexes
        migrator.registerMigration(migrationNames[3]) { database in
            try database.create(table: "link") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("sourceNoteID", .text).notNull()
                    .references("note", onDelete: .cascade)
                table.column("targetNoteID", .text).notNull()
                    .references("note", onDelete: .cascade)
                table.column("createdAt", .datetime).notNull()
                table.uniqueKey(["sourceNoteID", "targetNoteID"])
            }
            try database.create(indexOn: "link", columns: ["sourceNoteID"])
            try database.create(indexOn: "link", columns: ["targetNoteID"])
        }

        // v5: Action log + indexes
        migrator.registerMigration(migrationNames[4]) { database in
            try database.create(table: "actionLog") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("actionType", .text).notNull()
                table.column("noteID", .text).notNull()
                table.column("timestamp", .datetime).notNull()
                table.column("beforeState", .text)
                table.column("afterState", .text)
                table.column("metadata", .text)
                table.column("undone", .boolean).notNull().defaults(to: false)
            }
            try database.create(indexOn: "actionLog", columns: ["noteID"])
            try database.create(indexOn: "actionLog", columns: ["timestamp"])
        }

        // v6: Sync state
        migrator.registerMigration(migrationNames[5]) { database in
            try database.create(table: "syncState") { table in
                table.primaryKey("key", .text)
                table.column("value", .text).notNull()
            }
        }

        // v7: FTS5 content-sync on note(title, bodyPlaintext)
        migrator.registerMigration(migrationNames[6]) { database in
            try database.create(virtualTable: "noteFts", using: FTS5()) { table in
                table.synchronize(withTable: "note")
                table.tokenizer = .porter(wrapping: .unicode61())
                table.column("title")
                table.column("bodyPlaintext")
            }
        }

        migrator.registerMigration(migrationNames[7]) { database in
            try database.rename(table: "actionLog", to: "actionLog_old")
            try database.execute(sql: "DROP INDEX IF EXISTS index_actionLog_on_noteID")
            try database.execute(sql: "DROP INDEX IF EXISTS index_actionLog_on_timestamp")

            try database.create(table: "actionLog") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("actionType", .text).notNull()
                table.column("noteID", .text).notNull()
                table.column("timestamp", .datetime).notNull()
                table.column("beforeState", .text)
                table.column("afterState", .text)
                table.column("metadata", .text)
                table.column("undone", .boolean).notNull().defaults(to: false)
            }
            try database.create(indexOn: "actionLog", columns: ["noteID"])
            try database.create(indexOn: "actionLog", columns: ["timestamp"])

            try database.execute(sql: """
                INSERT INTO actionLog (id, actionType, noteID, timestamp, beforeState, afterState, metadata, undone)
                SELECT id, actionType, noteID, timestamp, beforeState, afterState, metadata, undone
                FROM actionLog_old
                """)

            try database.drop(table: "actionLog_old")
        }

        // v9: Switch body storage from HTML to Markdown; add accountName, snippet, noteAttachment
        migrator.registerMigration(migrationNames[8]) { database in
            // Drop dependent tables first, then the note table they reference
            try database.execute(sql: "DROP TABLE IF EXISTS noteFts")
            try database.execute(sql: "DROP TABLE IF EXISTS noteTag")
            try database.execute(sql: "DROP TABLE IF EXISTS link")
            try database.execute(sql: "DROP TABLE IF EXISTS actionLog")
            try database.execute(sql: "DROP TABLE IF EXISTS note")

            // Recreate note with bodyMarkdown instead of bodyHTML, plus new fields
            try database.create(table: "note") { table in
                table.primaryKey("id", .text)
                table.column("title", .text).notNull()
                table.column("bodyMarkdown", .text).notNull()
                table.column("bodyPlaintext", .text).notNull()
                table.column("folderPath", .text).notNull()
                table.column("accountName", .text)
                table.column("snippet", .text)
                table.column("creationDate", .datetime).notNull()
                table.column("modificationDate", .datetime).notNull()
                table.column("isLocked", .boolean).notNull().defaults(to: false)
                table.column("checksum", .text).notNull()
                table.column("syncedAt", .datetime).notNull()
            }
            try database.create(indexOn: "note", columns: ["folderPath"])
            try database.create(indexOn: "note", columns: ["modificationDate"])

            // New attachment tracking table
            try database.create(table: "noteAttachment") { table in
                table.primaryKey("id", .text)
                table.column("noteID", .text).notNull()
                    .references("note", onDelete: .cascade)
                table.column("filename", .text)
                table.column("typeUTI", .text)
                table.column("relativePath", .text).notNull()
            }
            try database.create(indexOn: "noteAttachment", columns: ["noteID"])

            // Recreate noteTag (unchanged schema)
            try database.create(table: "noteTag") { table in
                table.primaryKey {
                    table.column("noteID", .text).notNull()
                        .references("note", onDelete: .cascade)
                    table.column("tagID", .integer).notNull()
                        .references("tag", onDelete: .cascade)
                }
            }

            // Recreate link (unchanged schema)
            try database.create(table: "link") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("sourceNoteID", .text).notNull()
                    .references("note", onDelete: .cascade)
                table.column("targetNoteID", .text).notNull()
                    .references("note", onDelete: .cascade)
                table.column("createdAt", .datetime).notNull()
                table.uniqueKey(["sourceNoteID", "targetNoteID"])
            }
            try database.create(indexOn: "link", columns: ["sourceNoteID"])
            try database.create(indexOn: "link", columns: ["targetNoteID"])

            // Recreate actionLog (unchanged schema)
            try database.create(table: "actionLog") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("actionType", .text).notNull()
                table.column("noteID", .text).notNull()
                table.column("timestamp", .datetime).notNull()
                table.column("beforeState", .text)
                table.column("afterState", .text)
                table.column("metadata", .text)
                table.column("undone", .boolean).notNull().defaults(to: false)
            }
            try database.create(indexOn: "actionLog", columns: ["noteID"])
            try database.create(indexOn: "actionLog", columns: ["timestamp"])

            // Recreate FTS5 (indexes title + bodyPlaintext, unchanged)
            try database.create(virtualTable: "noteFts", using: FTS5()) { table in
                table.synchronize(withTable: "note")
                table.tokenizer = .porter(wrapping: .unicode61())
                table.column("title")
                table.column("bodyPlaintext")
            }
        }

        // v10: Switch body storage from Markdown (text) to raw protobuf (blob)
        migrator.registerMigration(migrationNames[9]) { database in
            // Drop dependent tables first, then the note table they reference
            try database.execute(sql: "DROP TABLE IF EXISTS noteFts")
            try database.execute(sql: "DROP TABLE IF EXISTS noteTag")
            try database.execute(sql: "DROP TABLE IF EXISTS link")
            try database.execute(sql: "DROP TABLE IF EXISTS noteAttachment")
            try database.execute(sql: "DROP TABLE IF EXISTS actionLog")
            try database.execute(sql: "DROP TABLE IF EXISTS note")

            // Recreate note with bodyProtobuf (blob) instead of bodyMarkdown (text)
            try database.create(table: "note") { table in
                table.primaryKey("id", .text)
                table.column("title", .text).notNull()
                table.column("bodyProtobuf", .blob).notNull()
                table.column("bodyPlaintext", .text).notNull()
                table.column("folderPath", .text).notNull()
                table.column("accountName", .text)
                table.column("snippet", .text)
                table.column("creationDate", .datetime).notNull()
                table.column("modificationDate", .datetime).notNull()
                table.column("isLocked", .boolean).notNull().defaults(to: false)
                table.column("checksum", .text).notNull()
                table.column("syncedAt", .datetime).notNull()
            }
            try database.create(indexOn: "note", columns: ["folderPath"])
            try database.create(indexOn: "note", columns: ["modificationDate"])

            // Recreate noteAttachment (unchanged schema)
            try database.create(table: "noteAttachment") { table in
                table.primaryKey("id", .text)
                table.column("noteID", .text).notNull()
                    .references("note", onDelete: .cascade)
                table.column("filename", .text)
                table.column("typeUTI", .text)
                table.column("relativePath", .text).notNull()
            }
            try database.create(indexOn: "noteAttachment", columns: ["noteID"])

            // Recreate noteTag (unchanged schema)
            try database.create(table: "noteTag") { table in
                table.primaryKey {
                    table.column("noteID", .text).notNull()
                        .references("note", onDelete: .cascade)
                    table.column("tagID", .integer).notNull()
                        .references("tag", onDelete: .cascade)
                }
            }

            // Recreate link (unchanged schema)
            try database.create(table: "link") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("sourceNoteID", .text).notNull()
                    .references("note", onDelete: .cascade)
                table.column("targetNoteID", .text).notNull()
                    .references("note", onDelete: .cascade)
                table.column("createdAt", .datetime).notNull()
                table.uniqueKey(["sourceNoteID", "targetNoteID"])
            }
            try database.create(indexOn: "link", columns: ["sourceNoteID"])
            try database.create(indexOn: "link", columns: ["targetNoteID"])

            // Recreate actionLog (unchanged schema)
            try database.create(table: "actionLog") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("actionType", .text).notNull()
                table.column("noteID", .text).notNull()
                table.column("timestamp", .datetime).notNull()
                table.column("beforeState", .text)
                table.column("afterState", .text)
                table.column("metadata", .text)
                table.column("undone", .boolean).notNull().defaults(to: false)
            }
            try database.create(indexOn: "actionLog", columns: ["noteID"])
            try database.create(indexOn: "actionLog", columns: ["timestamp"])

            // Recreate FTS5 (indexes title + bodyPlaintext, unchanged)
            try database.create(virtualTable: "noteFts", using: FTS5()) { table in
                table.synchronize(withTable: "note")
                table.tokenizer = .porter(wrapping: .unicode61())
                table.column("title")
                table.column("bodyPlaintext")
            }
        }
    }
}

// swiftlint:enable function_body_length
