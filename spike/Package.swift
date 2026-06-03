// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "spike",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "spike",
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/System/Library/PrivateFrameworks",
                    "-framework", "DFRFoundation"
                ])
            ]
        )
    ]
)
