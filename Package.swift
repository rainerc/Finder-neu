// swift-tools-version: 6.0
import PackageDescription
import Foundation

// Info.plist wird in die ausführbare Datei eingebettet, damit auch `swift run`
// die Berechtigung „Lokales Netzwerk“ (Bonjour-Suche nach Servern) erhält.
let infoPlist = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Support/Info.plist")
    .path

let package = Package(
    name: "FinderErsatz",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "FinderErsatz",
            path: "Sources/FinderErsatz",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", infoPlist]),
            ]
        )
    ]
)
