// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SimpleTextEdit",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "EditorCore"),
        .target(
            name: "EditorUI",
            dependencies: ["EditorCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "SimpleTextEdit",
            dependencies: ["EditorUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "EditorCoreTests", dependencies: ["EditorCore"]),
        .testTarget(
            name: "EditorUITests",
            dependencies: ["EditorUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
