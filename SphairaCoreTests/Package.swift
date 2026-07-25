// swift-tools-version: 6.0
import PackageDescription

// Eigenständiges Testpaket: bindet die Core-Quellen des Xcode-Projekts
// per Symlink ein, damit es keine zweite Kopie der Dateien gibt.
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
