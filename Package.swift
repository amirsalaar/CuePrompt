// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CuePrompt",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.15.0")
    ],
    targets: [
        .executableTarget(
            name: "CuePrompt",
            dependencies: ["WhisperKit"],
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CuePromptTests",
            dependencies: ["CuePrompt"],
            path: "Tests",
            exclude: ["Fixtures"]
        )
    ]
)
