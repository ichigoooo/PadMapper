// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "PadMapper",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "PadMapper",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("IOKit"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .testTarget(
            name: "PadMapperTests",
            dependencies: ["PadMapper"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
