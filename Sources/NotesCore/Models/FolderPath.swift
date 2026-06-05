import Foundation

/// Canonical handling for Apple Notes folder paths.
///
/// Paths are slash-delimited. A path may be account-prefixed (`iCloud/Projects`) or
/// account-relative (`Projects`), depending on the boundary using it.
public struct FolderPath: Sendable, Equatable, Hashable {
    public let value: String

    public init(_ value: String) {
        self.value = Self.trim(value)
    }

    public static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = trim(value)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func scoped(to account: String?) -> FolderPath {
        guard let account = Self.normalized(account), !value.isEmpty else { return self }
        if value == account || components.first == account {
            return self
        }
        return FolderPath("\(account)/\(value)")
    }

    public func relative(to account: String) -> String {
        guard let account = Self.normalized(account), !account.isEmpty else {
            return accountRelativeValue
        }
        if value == account { return "" }
        if value.hasPrefix(account + "/") {
            return FolderPath(String(value.dropFirst(account.count + 1))).accountRelativeValue
        }
        return accountRelativeValue
    }

    public func isInAccount(_ account: String?) -> Bool {
        guard let account = Self.normalized(account) else { return true }
        return value == account || value.hasPrefix(account + "/")
    }

    public func variants(selectedAccount: String?) -> Set<String> {
        let normalizedPath = value.lowercased()
        guard !normalizedPath.isEmpty else { return [] }
        guard
            let account = Self.normalized(selectedAccount)?.lowercased(),
            components.count > 1,
            components.first?.lowercased() == account
        else {
            return [normalizedPath]
        }
        return [normalizedPath, components.dropFirst().joined(separator: "/").lowercased()]
    }

    public func matches(filter: String, selectedAccount: String?) -> Bool {
        !variants(selectedAccount: selectedAccount).isDisjoint(
            with: FolderPath(filter).variants(selectedAccount: selectedAccount)
        )
    }

    public var accountRelativeValue: String {
        var result = value
        while result.hasPrefix("/") { result.removeFirst() }
        while result.hasSuffix("/") { result.removeLast() }
        return result
    }

    private var components: [String] {
        value.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private static func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
