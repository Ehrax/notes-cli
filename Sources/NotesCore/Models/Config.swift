import Foundation

/// Configuration for the notes-cli CLI safety and display settings.
public struct Config: Codable, Sendable {
    public struct NotesScope: Codable, Sendable, Equatable {
        public var selectedAccount: String?
        public var rootFolder: String?

        public init(selectedAccount: String? = nil, rootFolder: String? = nil) {
            self.selectedAccount = selectedAccount
            self.rootFolder = rootFolder
        }

        public static let `default` = NotesScope()

        public func scopedFolderPath(_ folderPath: String) -> String {
            let trimmedPath = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPath.isEmpty else { return trimmedPath }
            guard let selectedAccount = normalizedSelectedAccount else { return trimmedPath }

            let components = trimmedPath.split(separator: "/", omittingEmptySubsequences: true)
            if components.first.map(String.init) == selectedAccount {
                return trimmedPath
            }

            return selectedAccount + "/" + trimmedPath
        }

        public func resolvedFolderPath(_ folderPath: String?) -> String {
            if let folderPath {
                let trimmedPath = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedPath.isEmpty {
                    return scopedFolderPath(trimmedPath)
                }
            }

            if let rootFolder = normalizedRootFolder {
                return scopedFolderPath(rootFolder)
            }

            return normalizedSelectedAccount ?? ""
        }

        public func folderPathVariants(for folderPath: String) -> Set<String> {
            let normalizedPath = folderPath.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalizedPath.isEmpty else { return [] }

            let components = normalizedPath.split(separator: "/", omittingEmptySubsequences: true)
            guard
                components.count > 1,
                let selectedAccount = normalizedSelectedAccount?.lowercased(),
                components.first == Substring(selectedAccount)
            else {
                return [normalizedPath]
            }

            return [normalizedPath, components.dropFirst().joined(separator: "/")]
        }

        public func matchesFolderPath(_ folderPath: String, filter: String) -> Bool {
            !folderPathVariants(for: folderPath).isDisjoint(with: folderPathVariants(for: filter))
        }

        public func isInSelectedAccount(_ folderPath: String) -> Bool {
            guard let selectedAccount = normalizedSelectedAccount else { return true }
            let normalizedPath = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedPath == selectedAccount || normalizedPath.hasPrefix(selectedAccount + "/")
        }

        private var normalizedSelectedAccount: String? {
            let trimmed = selectedAccount?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }

        private var normalizedRootFolder: String? {
            let trimmed = rootFolder?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
    }

    /// Default output format for CLI display.
    public var defaultFormat: OutputFormat?

    /// Apple Notes account scoping configuration.
    public var notes: NotesScope

    public enum OutputFormat: String, Codable, Sendable {
        case json
        case table
        case markdown
    }

    public init(
        defaultFormat: OutputFormat? = nil,
        notes: NotesScope = .default
    ) {
        self.defaultFormat = defaultFormat
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case defaultFormat
        case notes
    }

    public init(from decoder: Decoder) throws {
        // Tolerant of unknown keys: legacy config.json files still load.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultFormat = try container.decodeIfPresent(OutputFormat.self, forKey: .defaultFormat)
        notes = try container.decodeIfPresent(NotesScope.self, forKey: .notes) ?? .default
    }

    /// Sensible defaults for a fresh installation.
    public static let `default` = Config(
        defaultFormat: nil,
        notes: .default
    )
}
