// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "notes-cli",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "notes-cli", targets: ["NotesCLI"]),
        .library(name: "NotesCore", targets: ["NotesCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.5.0"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.58.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
    ],
    targets: [
        .executableTarget(
            name: "NotesCLI",
            dependencies: [
                "NotesCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
        .target(
            name: "NotesCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
        .target(
            name: "NotesTestSupport",
            dependencies: ["NotesCore"],
            path: "Tests/NotesTestSupport"
        ),
        .testTarget(
            name: "NotesCoreTests",
            dependencies: [
                "NotesCore",
                "NotesTestSupport",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        .testTarget(
            name: "NotesCLITests",
            dependencies: [
                "NotesCLI",
                "NotesCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "NotesIntegrationTests",
            dependencies: ["NotesCore", "NotesTestSupport"]
        ),
        .testTarget(
            name: "NotesE2ETests",
            dependencies: []
        ),
    ]
)
