// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fmev",
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(
            name: "fmev",
            path: "Sources/fmev",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
