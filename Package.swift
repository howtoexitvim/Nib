// swift-tools-version: 6.0
import PackageDescription

/// Nib is a plain SwiftPM executable rather than an Xcode project: it builds
/// from the command line with no IDE state, and `make app` wraps the binary
/// into a .app bundle. No third-party dependencies.
let package = Package(
    name: "Nib",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Nib",
            path: "Sources/Nib"
        ),
        .testTarget(
            name: "NibTests",
            dependencies: ["Nib"],
            path: "Tests/NibTests"
        ),
    ]
)
