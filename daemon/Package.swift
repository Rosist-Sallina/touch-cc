// swift-tools-version:6.0
import PackageDescription

let dfr: [LinkerSetting] = [
    .unsafeFlags(["-F", "/System/Library/PrivateFrameworks", "-framework", "DFRFoundation"])
]

let package = Package(
    name: "tbcd",
    platforms: [.macOS(.v13)],
    targets: [
        // 守护进程并发用 NSLock + 信号量手动保证，采用 Swift 5 语言模式以避免严格并发检查。
        // 私有符号用 @_silgen_name 直接声明（见 TouchBarController），DFRFoundation 在 linkerSettings 链接。
        .executableTarget(
            name: "tbcd",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: dfr
        ),
        .testTarget(
            name: "tbcdTests",
            dependencies: ["tbcd"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: dfr
        )
    ]
)
