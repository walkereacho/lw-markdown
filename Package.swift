// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MarkdownEditor",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.1.0")
    ],
    targets: [
        .executableTarget(
            name: "MarkdownEditor",
            dependencies: ["Highlightr"],
            path: "Sources/MarkdownEditor"
        ),
        .testTarget(
            name: "MarkdownEditorTests",
            dependencies: ["MarkdownEditor"],
            path: "Tests/MarkdownEditorTests"
        )
    ]
)
