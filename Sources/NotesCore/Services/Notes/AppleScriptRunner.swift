import Foundation

/// Low-level NSAppleScript executor. Must run on the main thread.
@MainActor
public final class AppleScriptRunner: Sendable {
    public init() {}

    /// Execute an AppleScript and return the result descriptor.
    public func execute(_ source: String) throws -> NSAppleEventDescriptor {
        let firstLine = source.prefix(while: { $0 != "\n" })
        Log.debug("[applescript] executing script_length=\(source.count) first_line=\"\(firstLine)\"", logger: Log.applescript)

        let start = CFAbsoluteTimeGetCurrent()
        var errorDict: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            Log.error("[applescript] failed error=\"Failed to create NSAppleScript\"", logger: Log.applescript)
            throw NotesError.appleScriptError(message: "Failed to create NSAppleScript", number: nil)
        }
        let result = script.executeAndReturnError(&errorDict)

        if let errorDict {
            let message = errorDict[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            let number = errorDict[NSAppleScript.errorNumber] as? Int
            Log.error("[applescript] failed error=\"\(message)\" code=\(number.map(String.init) ?? "nil")", logger: Log.applescript)
            throw NotesError.appleScriptError(message: message, number: number)
        }

        let durationMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        Log.info("[applescript] succeeded result_type=\(result.descriptorType) duration_ms=\(durationMs)", logger: Log.applescript)

        return result
    }

    /// Execute an AppleScript and return string result.
    public func executeString(_ source: String) throws -> String {
        let descriptor = try execute(source)
        return descriptor.stringValue ?? ""
    }

    /// Execute an AppleScript and return list of strings (for multi-value results).
    public func executeList(_ source: String) throws -> [String] {
        let descriptor = try execute(source)
        var results: [String] = []
        let count = descriptor.numberOfItems
        guard count > 0 else { return results }
        for index in 1...count {
            if let item = descriptor.atIndex(index)?.stringValue {
                results.append(item)
            }
        }
        return results
    }
}
