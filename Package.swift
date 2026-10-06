// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VibeTranslator",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "VibeTranslator", targets: ["VibeTranslator"]),
    ],
    targets: [
        // Pure logic (markup protection, translation pipeline). No AppKit, fully unit-tested.
        .target(name: "VibeTranslatorCore"),
        // Menu bar app: hotkeys, Accessibility, clipboard, Apple Translation.
        .executableTarget(
            name: "VibeTranslator",
            dependencies: ["VibeTranslatorCore"]
        ),
        .testTarget(
            name: "VibeTranslatorCoreTests",
            dependencies: ["VibeTranslatorCore"]
        ),
    ]
)
