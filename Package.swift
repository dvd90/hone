// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PromptForge",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "PromptForge", path: "Sources/PromptForge"),
        .testTarget(name: "PromptForgeTests", dependencies: ["PromptForge"], path: "Tests/PromptForgeTests"),
    ]
)
