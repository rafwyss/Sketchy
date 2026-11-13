// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SketchPad",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SketchPad", targets: ["SketchPad"])
    ],
    targets: [
        .executableTarget(
            name: "SketchPad",
            path: "Sources/SketchPad"
        ),
        .testTarget(
            name: "SketchPadTests",
            dependencies: ["SketchPad"],
            path: "Sources/SketchPadTests"
        )
    ]
)
