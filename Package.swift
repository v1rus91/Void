// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Void",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "VoidApp",
            path: "Sources/VoidApp",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("SystemConfiguration"), .linkedFramework("ServiceManagement")]
        )
    ]
)
