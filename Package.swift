// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "WinFinder",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WinFinder",
            path: "Sources/WinFinder",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
            ]
        )
    ]
)
