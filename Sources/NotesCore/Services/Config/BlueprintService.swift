import Foundation

/// Parses and validates blueprint JSON, and generates folder creation operations.
/// This is a higher-level service that delegates to ConfigService for persistence
/// and NotesServiceProtocol for Apple Notes folder creation.
public final class BlueprintService: @unchecked Sendable {
    private let configService: ConfigServiceProtocol
    private let notes: NotesServiceProtocol

    public init(configService: ConfigServiceProtocol, notes: NotesServiceProtocol) {
        self.configService = configService
        self.notes = notes
    }

    /// Validates a blueprint for structural correctness.
    /// Returns a list of validation errors (empty if valid).
    public func validate(_ blueprint: Blueprint) -> [String] {
        var errors: [String] = []
        if blueprint.folders.isEmpty {
            errors.append("Blueprint must contain at least one folder")
        }
        for (index, folder) in blueprint.folders.enumerated() {
            errors.append(contentsOf: validateFolder(folder, atPath: "folders[\(index)]"))
        }
        return errors
    }

    /// Applies a blueprint by creating folders in Apple Notes and updating config.
    /// - Parameters:
    ///   - blueprint: The blueprint to apply.
    ///   - dryRun: If true, returns planned actions without executing.
    /// - Returns: List of actions taken (or that would be taken).
    public func apply(_ blueprint: Blueprint, dryRun: Bool) async throws -> [String] {
        let validationErrors = validate(blueprint)
        if !validationErrors.isEmpty {
            throw NotesError.blueprintInvalid(reason: validationErrors.joined(separator: "; "))
        }

        // Get planned actions from config service
        let actions = try await configService.applyBlueprint(blueprint, dryRun: dryRun)

        if !dryRun {
            // Actually create folders in Apple Notes
            let flatFolders = Blueprint.flattenFolders(blueprint.folders, parentPath: nil)
            for (_, folder, parentPath) in flatFolders {
                try await notes.createFolder(name: folder.name, parentName: parentPath)
            }
        }

        return actions
    }

    // MARK: - Private

    private func validateFolder(_ folder: Blueprint.BlueprintFolder, atPath path: String) -> [String] {
        var errors: [String] = []
        if folder.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("\(path).name must not be empty")
        }
        if let children = folder.children {
            for (index, child) in children.enumerated() {
                errors.append(contentsOf: validateFolder(child, atPath: "\(path).children[\(index)]"))
            }
        }
        return errors
    }
}
