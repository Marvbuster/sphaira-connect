// swift-tools-version: 6.0
import PackageDescription

// Standalone test package: pulls in the Xcode project's Core sources via a
// symlink, so there is never a second copy of the files.
let package = Package(
    name: "SphairaCoreTests",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "SphairaCore",
            path: "Sources/SphairaCore"
        ),
        .testTarget(
            name: "SphairaCoreTests",
            dependencies: ["SphairaCore"],
            path: "Tests/SphairaCoreTests"
        ),
    ]
)
