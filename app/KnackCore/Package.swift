// swift-tools-version: 6.0
// Platform-independent core of Knack: manifests, permissions, model routing, the Knack Cloud client
// and structured-output decoding. Foundation only, so it builds and tests on Linux CI too.
import PackageDescription

let package = Package(
    name: "KnackCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KnackCore", targets: ["KnackCore"]),
    ],
    targets: [
        .target(name: "KnackCore"),
        .testTarget(
            name: "KnackTests",
            dependencies: ["KnackCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
