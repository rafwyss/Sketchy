// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Sketchy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Sketchy", targets: ["Sketchy"])
    ],
    targets: [
        .executableTarget(
            name: "Sketchy",
            path: "Sources/Sketchy"
        ),
        .testTarget(
            name: "SketchyTests",
            dependencies: ["Sketchy"],
            path: "Sources/SketchyTests"
        )
    ]
)
