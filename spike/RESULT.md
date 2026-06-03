# Spike 结果 (2026-06-03)

机型 Mac14,7 (MacBook Pro 13" M2 2022)，macOS 26.5 (Tahoe)，Swift 6.3.1。

- **接管 Touch Bar**: ✅ 成功。`DFRFoundation` 私有框架可链接，`DFRSystemModalShowsCloseBoxWhenFrontMost` 符号存在；`presentSystemModalTouchBar:systemTrayItemIdentifier:` selector 存在且生效。
- **显示文字**: ✅ 成功（蓝条 + 文字，用户可见并交互）。
- **左右滑手势**: ✅ 成功。三次右滑被识别，dx=283/269/367，方向判定正确。
- **释放与退出**: ✅ `dismissSystemModalTouchBar:` 正常释放，进程 `exit 0`，无崩溃。

## 结论: **PASS → 继续 M3（Touch Bar UI 路线成立）**

## 重要备注（构建工具链根因）

- Spike 初期 `swift build` 报 `Undefined symbols ... PackageDescription.Package.__allocating_init`。
- **根因**：`xcode-select` 指向 `/Library/Developer/CommandLineTools`，而非已安装的 `/Applications/Xcode.app`，导致 SwiftPM 用了不匹配的 ManifestAPI。
- **解决**：`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` 后，`swift build` / `swift test` 用 Xcode 工具链（Swift 6.3.2）完全正常。
- **结论**：M2-M4 按原计划用 **SwiftPM + XCTest**。私有符号沿用 Spike 的 `@_silgen_name` 直接声明（省去 CDFR module）。
- 临时顶替方式（未永久切换时）：命令前加 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。
