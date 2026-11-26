// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FinderErsatz",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "FinderErsatz",
            path: "Sources/FinderErsatz"
        )
    ]
)
