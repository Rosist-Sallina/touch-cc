# Spike 结果 (2026-06-03)

机型 Mac14,7 (MacBook Pro 13" M2 2022)，macOS 26.5 (Tahoe)，Swift 6.3.1。

- **接管 Touch Bar**: ✅ 成功。`DFRFoundation` 私有框架可链接，`DFRSystemModalShowsCloseBoxWhenFrontMost` 符号存在；`presentSystemModalTouchBar:systemTrayItemIdentifier:` selector 存在且生效。
- **显示文字**: ✅ 成功（蓝条 + 文字，用户可见并交互）。
- **左右滑手势**: ✅ 成功。三次右滑被识别，dx=283/269/367，方向判定正确。
- **释放与退出**: ✅ `dismissSystemModalTouchBar:` 正常释放，进程 `exit 0`，无崩溃。

## 结论: **PASS → 继续 M3（Touch Bar UI 路线成立）**

## 重要备注（影响 M2 构建方式）

- **SwiftPM manifest 在纯 Command Line Tools 环境下链接失败**：`swift build` 报 `Undefined symbols ... PackageDescription.Package.__allocating_init`（ManifestAPI 链接问题，无 Xcode 所致）。
- Spike 改用 **`swiftc` 直接编译单文件**成功绕过：
  ```
  swiftc Sources/spike/main.swift -o spike-bin \
    -F /System/Library/PrivateFrameworks -framework DFRFoundation
  ```
- **对后续计划的影响**：M2 原计划用 `swift build` / `swift test` 做 TDD，在本机不可行。需调整构建策略（见下）。

## 建议的 M2 构建策略调整（三选一）

1. **`swiftc` 直接编译多文件**（推荐，零额外依赖）：`swiftc Sources/tbcd/*.swift -o tbcd ...`；测试用独立的小型断言可执行文件（XCTest 需 `swift test`，本机不可用），或把纯逻辑（Protocol/RequestQueue）写成可独立 `swiftc` 编译并 `assert` 的测试 runner。
2. **安装完整 Xcode**：恢复 `swift build`/`swift test`/`xcodebuild` 全套（体积大，需用户同意）。
3. **`xcodebuild` + 手写 project**：无 Xcode 不可行，排除。

→ 默认走 **方案 1**，保持「无需安装 Xcode」的轻量前提；TDD 用轻量 assert runner 替代 XCTest。
