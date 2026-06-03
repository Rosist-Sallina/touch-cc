// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "tbcd",
    platforms: [.macOS(.v13)],
    targets: [
        // M2 阶段：纯逻辑，无私有框架依赖。
        // Task 7 引入 TouchBarController 时再加 DFRFoundation 的 linkerSettings。
        .executableTarget(name: "tbcd"),
        .testTarget(name: "tbcdTests", dependencies: ["tbcd"])
    ]
)
