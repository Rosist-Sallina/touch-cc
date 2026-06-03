// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "tbcd",
    platforms: [.macOS(.v13)],
    targets: [
        // M2 阶段：纯逻辑 + socket，无私有框架依赖。
        // Task 7 引入 TouchBarController 时再加 DFRFoundation 的 linkerSettings。
        // 守护进程并发用 NSLock + 信号量手动保证，采用 Swift 5 语言模式以避免严格并发检查。
        .executableTarget(
            name: "tbcd",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "tbcdTests",
            dependencies: ["tbcd"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
