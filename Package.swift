// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "NeverPressStart",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "NeverPressStart"),
        .testTarget(name: "NeverPressStartTests", dependencies: ["NeverPressStart"]),
    ],
    swiftLanguageModes: [.v5]
)
