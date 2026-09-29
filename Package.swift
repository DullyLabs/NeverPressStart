// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NeverPressStart",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "NeverPressStart"),
        .testTarget(name: "NeverPressStartTests", dependencies: ["NeverPressStart"]),
    ]
)
