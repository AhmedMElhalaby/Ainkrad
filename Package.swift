// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ainkrad",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Ainkrad",
            path: "Sources/Ainkrad"
        ),
        .testTarget(
            name: "AinkradTests",
            dependencies: ["Ainkrad"],
            path: "Tests/AinkradTests"
        ),
    ]
)
