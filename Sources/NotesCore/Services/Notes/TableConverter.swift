import Foundation
import SwiftProtobuf

/// Decodes Apple Notes CRDT table data from `ZMERGEABLEDATA1` and emits a Markdown table.
///
/// Ported from the Obsidian Importer's `convert-table.ts`.
public enum TableConverter {
    // MARK: - Constants

    private static let tableType = "com.apple.notes.ICTable"
    private static let keyRows = "crRows"
    private static let keyColumns = "crColumns"
    private static let keyCellColumns = "cellColumns"

    // MARK: - Parsed table context (bundles shared parsing state)

    private struct TableContext {
        let objects: [Ciofecaforensics_MergeableDataObjectEntry]
        let uuids: [String]
        var rowLocations: [String: Int] = [:]
        var columnLocations: [String: Int] = [:]
        var rowCount: Int = 0
        var columnCount: Int = 0
    }

    // MARK: - Public API

    /// Convert gzipped CRDT protobuf data to a Markdown table string.
    ///
    /// - Parameter data: Raw bytes from the `ZMERGEABLEDATA1` column (gzip-compressed protobuf).
    /// - Returns: A Markdown-formatted table, or `nil` if the data does not contain a valid table.
    /// - Throws: `NotesError.encodingFailure` if decompression or protobuf parsing fails.
    public static func convert(data: Data) throws -> String? {
        let decompressed = try Gzip.decompress(data)
        let proto = try Ciofecaforensics_MergableDataProto(serializedBytes: decompressed)
        return try parseTable(from: proto)
    }

    // MARK: - Parsing

    private static func parseTable(from proto: Ciofecaforensics_MergableDataProto) throws -> String? {
        let objectData = proto.mergableDataObject.mergeableDataObjectData
        let keys = objectData.mergeableDataObjectKeyItem
        let types = objectData.mergeableDataObjectTypeItem
        let uuids = objectData.mergeableDataObjectUuidItem.map { uuidToHex($0) }
        let objects = objectData.mergeableDataObjectEntry

        // Find the root ICTable object — it must have a customMap whose type string is ICTable.
        guard let root = objects.first(where: { entry in
            entry.hasCustomMap && Int(entry.customMap.type) < types.count
                && types[Int(entry.customMap.type)] == tableType
        }) else {
            return nil
        }

        var context = TableContext(objects: objects, uuids: uuids)
        var cellData: Ciofecaforensics_MergeableDataObjectEntry?

        for mapEntry in root.customMap.mapEntry {
            let keyIndex = Int(mapEntry.key)
            guard keyIndex < keys.count else { continue }
            let keyName = keys[keyIndex]
            let objectIndex = Int(mapEntry.value.objectIndex)
            guard objectIndex < objects.count else { continue }
            let object = objects[objectIndex]

            switch keyName {
            case keyRows:
                (context.rowLocations, context.rowCount) = findLocations(object: object, context: context)
            case keyColumns:
                (context.columnLocations, context.columnCount) = findLocations(object: object, context: context)
            case keyCellColumns:
                cellData = object
            default:
                break
            }
        }

        guard let cellData, context.rowCount > 0, context.columnCount > 0 else { return nil }
        let grid = computeCells(cellData: cellData, context: context)
        return renderMarkdownTable(grid)
    }

    // MARK: - CRDT Location Extraction

    /// Extract the ordered position map from a CRDT `OrderedSet` entry.
    ///
    /// Returns a dictionary mapping UUID → row/column index, plus the total count.
    private static func findLocations(
        object: Ciofecaforensics_MergeableDataObjectEntry,
        context: TableContext
    ) -> ([String: Int], Int) {
        var orderingIndex: [String: Int] = [:]
        var locations: [String: Int] = [:]

        // Build UUID → index map from the attachment array (O(1) lookup later).
        for (idx, attachment) in object.orderedSet.ordering.array.attachment.enumerated() {
            orderingIndex[uuidToHex(attachment.uuid)] = idx
        }

        // Map target UUID → index in the ordering.
        for element in object.orderedSet.ordering.contents.element {
            guard let keyUUID = targetUUID(from: element.key, context: context),
                  let valueUUID = targetUUID(from: element.value, context: context) else {
                continue
            }
            if let idx = orderingIndex[keyUUID] {
                locations[valueUUID] = idx
            }
        }

        return (locations, orderingIndex.count)
    }

    // MARK: - Cell Grid Construction

    private static func computeCells(
        cellData: Ciofecaforensics_MergeableDataObjectEntry,
        context: TableContext
    ) -> [[String]] {
        var grid: [[String]] = Array(
            repeating: Array(repeating: "", count: context.columnCount),
            count: context.rowCount
        )

        for column in cellData.dictionary.element {
            guard let columnUUID = targetUUID(from: column.key, context: context),
                  let columnIdx = context.columnLocations[columnUUID] else {
                continue
            }
            let rowDataIndex = Int(column.value.objectIndex)
            guard rowDataIndex < context.objects.count else { continue }
            let rowData = context.objects[rowDataIndex]

            for row in rowData.dictionary.element {
                guard let rowUUID = targetUUID(from: row.key, context: context),
                      let rowIdx = context.rowLocations[rowUUID],
                      rowIdx < context.rowCount, columnIdx < context.columnCount else {
                    continue
                }
                let cellIndex = Int(row.value.objectIndex)
                guard cellIndex < context.objects.count else { continue }
                let cellEntry = context.objects[cellIndex]
                guard cellEntry.hasNote else { continue }
                grid[rowIdx][columnIdx] = formatCellText(cellEntry.note)
            }
        }

        return grid
    }

    // MARK: - Cell Formatting

    /// Extract plain text from a cell's `Note` message.
    ///
    /// Inline Markdown formatting (bold, italic) is applied via attribute runs if present;
    /// otherwise the raw `noteText` is used directly.
    private static func formatCellText(_ note: Ciofecaforensics_Note) -> String {
        let text = note.noteText
        guard !note.attributeRun.isEmpty else { return text }

        var result = ""
        var cursor = text.startIndex

        for run in note.attributeRun {
            let length = Int(run.length)
            let end = text.index(cursor, offsetBy: min(length, text.distance(from: cursor, to: text.endIndex)))
            let slice = String(text[cursor..<end])
            result += applyInlineFormatting(slice, run: run)
            cursor = end
        }

        // Append any leftover text not covered by runs.
        if cursor < text.endIndex {
            result += String(text[cursor...])
        }

        return result
    }

    /// Apply inline Markdown formatting to a text slice based on the attribute run.
    ///
    /// fontWeight values: 1 = bold, 2 = italic (plain), 3 = bold+italic (bold only).
    /// Also applies strikethrough (`~~`) and underline (→ bold) wrapping.
    private static func applyInlineFormatting(_ text: String, run: Ciofecaforensics_AttributeRun) -> String {
        InlineMarkdownFormatter.apply(
            to: text,
            fontWeight: run.hasFontWeight ? run.fontWeight : nil,
            underlined: run.underlined != 0,
            strikethrough: run.strikethrough != 0,
            italicPolicy: .plain
        )
    }

    // MARK: - Markdown Rendering

    private static func renderMarkdownTable(_ grid: [[String]]) -> String {
        guard !grid.isEmpty else { return "" }
        let colCount = grid[0].count
        guard colCount > 0 else { return "" }

        func sanitize(_ cell: String) -> String {
            cell.replacingOccurrences(of: "|", with: "&#124;")
                .replacingOccurrences(of: "\n", with: "<br>")
        }

        var lines: [String] = []

        // Header row (first data row).
        lines.append("| " + grid[0].map(sanitize).joined(separator: " | ") + " |")

        // Separator row.
        let separator = Array(repeating: "--", count: colCount)
        lines.append("| " + separator.joined(separator: " | ") + " |")

        // Data rows.
        for row in grid.dropFirst() {
            lines.append("| " + row.map(sanitize).joined(separator: " | ") + " |")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - UUID / Object Helpers

    /// Resolve the UUID string for an `ObjectID` that points to a reference object.
    ///
    /// The reference object at `entry.objectIndex` is a customMap whose first mapEntry
    /// holds a `unsignedIntegerValue` indexing into the UUID item table.
    private static func targetUUID(
        from entry: Ciofecaforensics_ObjectID,
        context: TableContext
    ) -> String? {
        let refIndex = Int(entry.objectIndex)
        guard refIndex < context.objects.count else { return nil }
        let reference = context.objects[refIndex]
        guard reference.hasCustomMap,
              let firstEntry = reference.customMap.mapEntry.first else {
            return nil
        }
        let uuidIndex = Int(firstEntry.value.unsignedIntegerValue)
        guard uuidIndex < context.uuids.count else { return nil }
        return context.uuids[uuidIndex]
    }

    /// Convert raw UUID bytes to a lowercase hex string.
    ///
    /// Matches TypeScript `Buffer.from(uuid).toString('hex')`.
    private static func uuidToHex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

}
