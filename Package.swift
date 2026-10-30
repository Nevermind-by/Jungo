// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Jungo",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Jungo", targets: ["Jungo"])
    ],
    targets: [
        .target(name: "JungoCore", path: "Sources/JungoCore"),
        .executableTarget(
            name: "Jungo",
            dependencies: ["JungoCore"],
            path: "Sources/Jungo"
        ),
        .testTarget(
            name: "JungoTests",
            dependencies: ["JungoCore", "Jungo"],
            path: "Tests/JungoTests"
        )
    ]
)
