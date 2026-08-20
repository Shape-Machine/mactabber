// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacTabber",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MacTabber",
            path: "Sources/MacTabber",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
