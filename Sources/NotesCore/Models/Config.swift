import Foundation

/// Configuration for notes-cli account scope and write settings.
public struct Config: Codable, Sendable {
    public struct NotesScope: Codable, Sendable, Equatable {
        public struct ResolvedFolder: Sendable, Equatable {
            public let account: String?
            public let fullPath: String
            public let accountRelativePath: String
        }

        public var selectedAccount: String?
        public var rootFolder: String?

        public init(selectedAccount: String? = nil, rootFolder: String? = nil) {
            self.selectedAccount = selectedAccount
            self.rootFolder = rootFolder
        }

        public static let `default` = NotesScope()

        public func scopedFolderPath(_ folderPath: String) -> String {
            FolderPath(folderPath).scoped(to: normalizedSelectedAccount).value
        }

        public func resolvedFolderPath(_ folderPath: String?) -> String {
            if let path = FolderPath.normalized(folderPath) {
                return scopedFolderPath(path)
            }

            if let rootFolder = normalizedRootFolder {
                return scopedFolderPath(rootFolder)
            }

            return normalizedSelectedAccount ?? ""
        }

        public func resolvedFolder(_ folderPath: String?) -> ResolvedFolder {
            resolvedFolder(folderPath, defaultAccount: nil)
        }

        public func resolvedFolder(_ folderPath: String?, defaultAccount: String?) -> ResolvedFolder {
            let fullPath = resolvedFolderPath(folderPath)
            guard let account = normalizedSelectedAccount ?? Self.normalized(defaultAccount) else {
                return ResolvedFolder(account: nil, fullPath: fullPath, accountRelativePath: fullPath)
            }
            if fullPath == account {
                return ResolvedFolder(account: account, fullPath: fullPath, accountRelativePath: "")
            }
            if fullPath.hasPrefix(account + "/") {
                return ResolvedFolder(
                    account: account,
                    fullPath: fullPath,
                    accountRelativePath: String(fullPath.dropFirst(account.count + 1))
                )
            }
            return ResolvedFolder(account: account, fullPath: fullPath, accountRelativePath: fullPath)
        }

        public func folderPathVariants(for folderPath: String) -> Set<String> {
            FolderPath(folderPath).variants(selectedAccount: normalizedSelectedAccount)
        }

        public func matchesFolderPath(_ folderPath: String, filter: String) -> Bool {
            FolderPath(folderPath).matches(filter: filter, selectedAccount: normalizedSelectedAccount)
        }

        public func isInSelectedAccount(_ folderPath: String) -> Bool {
            FolderPath(folderPath).isInAccount(normalizedSelectedAccount)
        }

        private var normalizedSelectedAccount: String? {
            Self.normalized(selectedAccount)
        }

        private var normalizedRootFolder: String? {
            let trimmed = Self.normalized(rootFolder)
            return trimmed?.isEmpty == false ? trimmed : nil
        }

        private static func normalized(_ value: String?) -> String? {
            FolderPath.normalized(value)
        }
    }

    /// Apple Notes account scoping configuration.
    public var notes: NotesScope

    /// When true, `notes create` appends an italic "created by AI" footer (default on).
    public var aiFooterEnabled: Bool

    public init(
        notes: NotesScope = .default,
        aiFooterEnabled: Bool = true
    ) {
        self.notes = notes
        self.aiFooterEnabled = aiFooterEnabled
    }

    enum CodingKeys: String, CodingKey {
        case notes
        case aiFooterEnabled
    }

    public init(from decoder: Decoder) throws {
        // Tolerant of unknown keys: legacy config.json files still load.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notes = try container.decodeIfPresent(NotesScope.self, forKey: .notes) ?? .default
        aiFooterEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiFooterEnabled) ?? true
    }

    /// Sensible defaults for a fresh installation.
    public static let `default` = Config(notes: .default)
}
