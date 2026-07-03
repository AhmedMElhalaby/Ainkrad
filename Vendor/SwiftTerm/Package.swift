// swift-tools-version:5.9
import PackageDescription

// Vendored copy of SwiftTerm (https://github.com/migueldeicaza/SwiftTerm,
// MIT — see LICENSE), pinned at 1.13.0, with a local patch that disables
// line-reflow on resize (Buffer.resize) — SwiftTerm's re-wrap duplicates
// output when a terminal is resized. This manifest builds only the SwiftTerm
// library (the upstream fuzz/benchmark/termcast targets and their external
// dependencies are intentionally omitted).
let package = Package(
    name: "SwiftTerm",
    platforms: [
        .iOS(.v14),
        .macOS(.v13),
        .tvOS(.v13),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "SwiftTerm", targets: ["SwiftTerm"]),
    ],
    targets: [
        .target(
            name: "SwiftTerm",
            path: "Sources/SwiftTerm",
            exclude: ["Mac/README.md"],
            resources: [
                .process("Apple/Metal/Shaders.metal"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
