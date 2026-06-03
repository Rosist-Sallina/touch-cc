# Touch Bar × Claude Code 权限审批工具 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Claude Code 的权限申请弹到 Touch Bar 上，右滑通过 / 左滑拒绝，不可用时无缝退化到 CC 原生终端提示。

**Architecture:** CC 的 `PreToolUse` hook（`hook.sh`）通过 Unix domain socket 把申请发给常驻菜单栏守护进程 `tbcd`（Swift）；`tbcd` 用私有 API 接管 Touch Bar 渲染审批界面、捕获左右滑、把决定写回 socket；hook 据此返回 allow/deny，超时或连接失败则静默退出让 CC 回退原生提示。多会话靠 socket 多连接 + FIFO 队列。

**Tech Stack:** Swift 6.3 (AppKit / NSTouchBar / 私有 DFRFoundation)、Swift Package Manager、Bash + jq + nc、launchd LaunchAgent。

**关键约束:** 本机仅有 Command Line Tools（无 Xcode）→ 用 `swift build` 构建可执行文件，手动组装 `.app`。`socat`/`bats` 未安装 → 测试用 `nc` + bash 断言。

**⚠️ Spike 决策门:** Task 1 (M0) 是整个项目的前提。Spike 失败（私有 Touch Bar API 在 macOS 26.5 失效）→ 停止，回退 spec §7 的 BTT 方案。**不要在 Task 1 通过前实现 M3 (Touch Bar UI)。** M1/M2（hook + 守护进程逻辑）与 Touch Bar 无关，即使 Spike 失败也可复用，可并行推进。

---

## 文件结构

```
touch-cc/
├── docs/superpowers/{specs,plans}/         # 已存在
├── spike/
│   ├── Package.swift                        # Spike 的最小 SPM 包
│   └── Sources/spike/main.swift             # < 80 行，验证接管+手势
├── daemon/
│   ├── Package.swift
│   ├── Sources/tbcd/
│   │   ├── main.swift                       # NSApplication 启动 + 组装
│   │   ├── Protocol.swift                   # 请求/响应 Codable + 编解码
│   │   ├── RequestQueue.swift               # 线程安全 FIFO
│   │   ├── SocketServer.swift               # Unix socket 监听 + 连接处理
│   │   ├── TouchBarController.swift         # 接管/释放 Touch Bar
│   │   ├── ApprovalView.swift               # 自定义 NSView + 滑动手势
│   │   └── MenuBarController.swift          # 菜单栏图标 + 状态
│   ├── Sources/CDFR/                        # 私有框架的 C 桥接
│   │   ├── include/CDFR.h
│   │   └── shim.c
│   └── Tests/tbcdTests/
│       ├── ProtocolTests.swift
│       └── RequestQueueTests.swift
├── hook/
│   ├── hook.sh                              # CC PreToolUse hook
│   └── test_hook.sh                         # 纯 bash 测试
└── install.sh                               # 打包 + 安装 + settings.json 注入
```

---

# M0 — Spike（决策门）

### Task 1: Touch Bar 接管 + 滑动手势验证

**Files:**
- Create: `spike/Package.swift`
- Create: `spike/Sources/spike/main.swift`

**目的:** 用最小代码验证在 macOS 26.5 上：① 私有 API 能接管 Touch Bar 显示文字；② 自定义 view 能收到左/右滑手势。这是基于 Pock/MTMR 已知方法的尝试，运行结果决定整个项目走向。

- [ ] **Step 1: 创建 SPM 包清单**

`spike/Package.swift`:
```swift
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
```

- [ ] **Step 2: 写 Spike 主程序**

`spike/Sources/spike/main.swift`:
```swift
import AppKit

// 私有 DFRFoundation 符号声明（来自 Pock/MTMR 逆向）
@_silgen_name("DFRSystemModalShowsCloseBoxWhenFrontMost")
func DFRSystemModalShowsCloseBoxWhenFrontMost(_ show: Bool)

// NSTouchBar 私有方法通过 ObjC runtime 调用
extension NSTouchBar {
    static func presentSystemModal(_ touchBar: NSTouchBar, identifier: String) {
        let sel = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
        if NSTouchBar.responds(to: sel) {
            typealias Fn = @convention(c) (AnyObject, Selector, NSTouchBar, NSString) -> Void
            let imp = NSTouchBar.method(for: sel)
            let fn = unsafeBitCast(imp, to: Fn.self)
            fn(NSTouchBar.self, sel, touchBar, identifier as NSString)
        } else {
            print("SPIKE-FAIL: presentSystemModalTouchBar selector 不存在")
        }
    }
    static func dismissSystemModal(_ touchBar: NSTouchBar) {
        let sel = NSSelectorFromString("dismissSystemModalTouchBar:")
        guard NSTouchBar.responds(to: sel) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, NSTouchBar) -> Void
        let imp = NSTouchBar.method(for: sel)
        unsafeBitCast(imp, to: Fn.self)(NSTouchBar.self, sel, touchBar)
    }
}

final class SwipeView: NSView {
    private var startX: CGFloat = 0
    override func touchesBegan(with event: NSEvent) {
        startX = event.allTouches().first?.location(in: self).x ?? 0
    }
    override func touchesEnded(with event: NSEvent) {
        let endX = event.allTouches().first?.location(in: self).x ?? 0
        let dx = endX - startX
        if abs(dx) > 40 {
            print("SPIKE-OK: 收到滑动 方向=\(dx > 0 ? "右(通过)" : "左(拒绝)") dx=\(Int(dx))")
        } else {
            print("SPIKE: 点击/微动 dx=\(Int(dx))")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    let itemId = NSTouchBarItem.Identifier("com.touchbarcc.spike.item")
    var touchBar: NSTouchBar!

    func applicationDidFinishLaunching(_ n: Notification) {
        DFRSystemModalShowsCloseBoxWhenFrontMost(false)
        touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [itemId]
        NSTouchBar.presentSystemModal(touchBar, identifier: "com.touchbarcc.spike.tray")
        print("SPIKE: 已尝试接管 Touch Bar，请在 Touch Bar 上左右滑动测试；10 秒后自动退出")
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            NSTouchBar.dismissSystemModal(self.touchBar)
            print("SPIKE: 已释放 Touch Bar，退出")
            NSApp.terminate(nil)
        }
    }

    func touchBar(_ tb: NSTouchBar, makeItemForIdentifier id: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard id == itemId else { return nil }
        let item = NSCustomTouchBarItem(identifier: id)
        let v = SwipeView()
        v.allowedTouchTypes = [.direct]
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.systemBlue.cgColor
        let label = NSTextField(labelWithString: "← 拒绝   滑我   通过 →")
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            v.widthAnchor.constraint(equalToConstant: 560)
        ])
        item.view = v
        return item
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 3: 构建**

Run: `cd spike && swift build 2>&1 | tail -20`
Expected: 编译成功，生成 `.build/debug/spike`。若报 `DFRSystemModalShowsCloseBoxWhenFrontMost` 链接错误 → 记录："私有符号在 Tahoe 已移除"，进入决策门失败分支。

- [ ] **Step 4: 运行并人工观察 Touch Bar**

Run: `cd spike && ./.build/debug/spike`
观察：
1. Touch Bar 是否出现蓝色条 + "← 拒绝 滑我 通过 →" 文字
2. 在 Touch Bar 上左右滑动，终端是否打印 `SPIKE-OK: 收到滑动 方向=...`
3. 10 秒后是否自动释放并退出

- [ ] **Step 5: 记录决策门结果**

在 `spike/RESULT.md` 写下结论：
```markdown
# Spike 结果 (2026-06-03)
- 接管 Touch Bar: [成功 / 失败 + 现象]
- 显示文字: [成功 / 失败]
- 左右滑手势: [成功 / 失败 + 现象]
- 结论: [PASS → 继续 M3 / FAIL → 回退 BTT 方案]
- 备注: [若部分失败，记录具体 selector/符号情况，供调整]
```

- [ ] **Step 6: Commit**

```bash
git add spike/ && git commit -m "spike: 验证 Touch Bar 接管与滑动手势 (M0 决策门)"
```

**🚦 决策门:** RESULT.md 结论为 PASS 才继续 M3。无论 PASS/FAIL，M1/M2 均可推进。

---

# M1 — hook.sh 与通信协议

### Task 2: hook.sh 的字段 dump 探针（实测 CC 契约）

**Files:**
- Create: `hook/hook.sh`（探针版）

**目的:** spec §10 标注 CC hook 字段名是待验证假设。第一版 hook 先把真实 stdin dump 到文件，用一次真实 CC 调用确认字段，再据此写正式逻辑。

- [ ] **Step 1: 写 dump 版 hook**

`hook/hook.sh`:
```bash
#!/usr/bin/env bash
# touchbar-cc PreToolUse hook —— 探针版（M1 临时）
set -euo pipefail
mkdir -p "$HOME/.touchbar-cc"
cat > "$HOME/.touchbar-cc/last-input.json"
# 探针版不做决定，直接放行（不输出 permissionDecision → CC 走原生流程）
exit 0
```

- [ ] **Step 2: 临时注册到 CC settings**

手动在 `~/.claude/settings.json` 的 `hooks.PreToolUse` 加入（matcher 用 `Bash`）：
```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "bash ~/Projects/touch-cc/hook/hook.sh" }] }
    ]
  }
}
```
Run: `chmod +x hook/hook.sh`

- [ ] **Step 3: 触发一次真实 CC Bash 申请**

在一个 CC 会话里让它跑一条需要权限的命令（如 `echo hi`）。然后：
Run: `cat ~/.touchbar-cc/last-input.json | jq .`
Expected: 看到真实字段。**核对** `session_id`、`cwd`、`tool_name`、`tool_input`、`hook_event_name` 的确切名字。

- [ ] **Step 4: 记录真实契约**

把实际字段名写入 `hook/CONTRACT.md`（后续 Task 据此实现）。若字段名与 spec §10 假设不同，以此为准。

- [ ] **Step 5: Commit**

```bash
git add hook/hook.sh hook/CONTRACT.md && git commit -m "feat(hook): 字段 dump 探针，确认 CC PreToolUse 契约"
```

---

### Task 3: hook.sh 正式逻辑（TDD）

**Files:**
- Modify: `hook/hook.sh`
- Create: `hook/test_hook.sh`

**目的:** hook 解析 stdin → 连 socket → 据响应输出决定 → 失败回退。用假 socket server 做 TDD。

> 下方代码假设 Task 3 探针确认的字段为 `session_id` / `cwd` / `tool_name` / `tool_input`（含 `.command` for Bash, `.file_path` for Edit/Write）。若 CONTRACT.md 不同，按实际调整 jq 路径。

- [ ] **Step 1: 写失败测试（allow 路径）**

`hook/test_hook.sh`:
```bash
#!/usr/bin/env bash
# 纯 bash 测试，无 bats 依赖
set -uo pipefail
HOOK="$(dirname "$0")/hook.sh"
SOCK="/tmp/tbcc-test-$$.sock"
PASS=0; FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 期望[$3] 实际[$2]"; FAIL=$((FAIL+1)); fi; }

# 假 server：收到一行，回固定决定
fake_server() { # $1=decision
  rm -f "$SOCK"
  ( echo "{\"id\":\"x\",\"decision\":\"$1\"}" | nc -lU "$SOCK" >/dev/null 2>&1 ) &
  sleep 0.3
}

# 测试1: allow → 输出含 "allow"
fake_server allow
INPUT='{"session_id":"s","cwd":"/tmp/proj","tool_name":"Bash","tool_input":{"command":"echo hi"}}'
OUT=$(echo "$INPUT" | TBCC_SOCK="$SOCK" TBCC_TIMEOUT=5 bash "$HOOK")
echo "$OUT" | grep -q '"permissionDecision":"allow"' && R=ok || R=no
check "allow路径" "$R" "ok"

# 测试2: deny → 输出含 "deny"
fake_server deny
OUT=$(echo "$INPUT" | TBCC_SOCK="$SOCK" TBCC_TIMEOUT=5 bash "$HOOK")
echo "$OUT" | grep -q '"permissionDecision":"deny"' && R=ok || R=no
check "deny路径" "$R" "ok"

# 测试3: socket 不存在 → 静默退出，无 permissionDecision
rm -f "$SOCK"
OUT=$(echo "$INPUT" | TBCC_SOCK="$SOCK" TBCC_TIMEOUT=2 bash "$HOOK")
echo "$OUT" | grep -q 'permissionDecision' && R=has || R=none
check "无server回退" "$R" "none"

rm -f "$SOCK"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `chmod +x hook/test_hook.sh && bash hook/test_hook.sh`
Expected: FAIL（当前 hook.sh 还是探针版，不连 socket）

- [ ] **Step 3: 实现正式 hook.sh**

`hook/hook.sh`（覆盖探针版）:
```bash
#!/usr/bin/env bash
# touchbar-cc PreToolUse hook
set -uo pipefail

SOCK="${TBCC_SOCK:-$HOME/.touchbar-cc/tbcd.sock}"
TIMEOUT="${TBCC_TIMEOUT:-55}"

INPUT="$(cat)"

# 提取字段（失败回退：任何 jq 错误都静默放行）
session=$(printf '%s' "$INPUT" | jq -r '.cwd // "" | split("/") | last' 2>/dev/null) || exit 0
cwd=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null) || exit 0
tool=$(printf '%s' "$INPUT" | jq -r '.tool_name // "?"' 2>/dev/null) || exit 0

# 摘要：按工具类型取关键参数
case "$tool" in
  Bash) summary=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) ;;
  Edit|Write|MultiEdit|NotebookEdit) summary=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) ;;
  *) summary=$(printf '%s' "$INPUT" | jq -rc '.tool_input // {}' 2>/dev/null) ;;
esac

id=$(/usr/bin/uuidgen)
req=$(jq -nc --arg id "$id" --arg s "$session" --arg c "$cwd" --arg t "$tool" --arg sum "$summary" \
  '{id:$id,session:$s,cwd:$c,tool:$t,summary:$sum,queue_remaining:0}')

# 连 socket，发请求，读一行响应（超时回退）
resp=$(printf '%s\n' "$req" | nc -U -w "$TIMEOUT" "$SOCK" 2>/dev/null | head -1) || exit 0
[ -z "$resp" ] && exit 0

decision=$(printf '%s' "$resp" | jq -r '.decision // ""' 2>/dev/null) || exit 0

case "$decision" in
  allow) jq -nc '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:"touchbar approved"}}' ;;
  deny)  jq -nc '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"touchbar rejected"}}' ;;
  *) exit 0 ;;  # 未知响应 → 回退
esac
exit 0
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `bash hook/test_hook.sh`
Expected: `PASS=3 FAIL=0`

> 注意：`nc -U -w` 在 macOS 自带 nc 上读到 EOF 即退出。假 server 用 `nc -lU` 回一行后关闭连接，hook 端 `head -1` 取首行。若实测 `nc` 行为差异导致挂起，把 `-w "$TIMEOUT"` 确认生效（macOS nc 支持 `-w` 超时）。

- [ ] **Step 5: Commit**

```bash
git add hook/hook.sh hook/test_hook.sh && git commit -m "feat(hook): 正式 socket 审批逻辑 + 回退，bash 测试通过"
```

---

# M2 — tbcd 守护进程逻辑（无 UI）

> **⚠️ M0 后修订（2026-06-03）：xcode-select 根因已解决**
> Spike 初期 `swift build` 失败，根因是 `xcode-select` 指向 CommandLineTools 而非已安装的 `/Applications/Xcode.app`。
> 执行 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` 后 SwiftPM (Swift 6.3.2) 正常。
> **M2-M4 按原计划用 SwiftPM + XCTest。** 唯一简化：私有符号沿用 Spike 验证可行的 `@_silgen_name` 直接声明，**省去 CDFR systemLibrary module**（Task 4 Step 2 跳过；Task 7 据此简化，DFRFoundation 仅在 linkerSettings 声明）。

### Task 4: SPM 包骨架 + 协议层（TDD）

**Files:**
- Create: `daemon/Package.swift`
- Create: `daemon/Sources/tbcd/Protocol.swift`
- Create: `daemon/Tests/tbcdTests/ProtocolTests.swift`

- [ ] **Step 1: 写 Package.swift**

`daemon/Package.swift`:
```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "tbcd",
    platforms: [.macOS(.v13)],
    targets: [
        .systemLibrary(name: "CDFR", path: "Sources/CDFR"),
        .executableTarget(
            name: "tbcd",
            dependencies: ["CDFR"],
            linkerSettings: [
                .unsafeFlags(["-F", "/System/Library/PrivateFrameworks", "-framework", "DFRFoundation"])
            ]
        ),
        .testTarget(name: "tbcdTests", dependencies: ["tbcd"])
    ]
)
```

> 暂时为让 Protocol/Queue 单元测试能跑且不被 AppKit/私有框架拖累，本 Task 先不引 CDFR 的实际符号；CDFR 桥接在 Task 7 建立。若 `swift test` 因 CDFR 缺失报错，先在 Step 2 建占位头文件。

- [ ] **Step 2: 建 CDFR 占位 system library（先空，Task 7 填）**

`daemon/Sources/CDFR/module.modulemap`:
```
module CDFR {
    header "include/CDFR.h"
    export *
}
```
`daemon/Sources/CDFR/include/CDFR.h`:
```c
#ifndef CDFR_H
#define CDFR_H
// 私有符号在 Task 7 声明
#endif
```

- [ ] **Step 3: 写协议失败测试**

`daemon/Tests/tbcdTests/ProtocolTests.swift`:
```swift
import XCTest
@testable import tbcd

final class ProtocolTests: XCTestCase {
    func testDecodeRequest() throws {
        let json = #"{"id":"abc","session":"proj","cwd":"/x/proj","tool":"Bash","summary":"echo hi","queue_remaining":2}"#
        let req = try ApprovalRequest.decode(from: json)
        XCTAssertEqual(req.id, "abc")
        XCTAssertEqual(req.tool, "Bash")
        XCTAssertEqual(req.summary, "echo hi")
        XCTAssertEqual(req.queueRemaining, 2)
    }
    func testEncodeResponse() throws {
        let line = ApprovalResponse(id: "abc", decision: .allow).encodeLine()
        XCTAssertTrue(line.contains("\"id\":\"abc\""))
        XCTAssertTrue(line.contains("\"decision\":\"allow\""))
        XCTAssertTrue(line.hasSuffix("\n"))
    }
}
```

- [ ] **Step 4: 运行，确认失败**

Run: `cd daemon && swift test 2>&1 | tail -20`
Expected: 编译失败（`ApprovalRequest` 未定义）

- [ ] **Step 5: 实现协议**

`daemon/Sources/tbcd/Protocol.swift`:
```swift
import Foundation

struct ApprovalRequest: Codable {
    let id: String
    let session: String
    let cwd: String
    let tool: String
    let summary: String
    let queueRemaining: Int

    enum CodingKeys: String, CodingKey {
        case id, session, cwd, tool, summary
        case queueRemaining = "queue_remaining"
    }

    static func decode(from line: String) throws -> ApprovalRequest {
        try JSONDecoder().decode(ApprovalRequest.self, from: Data(line.utf8))
    }
}

enum Decision: String, Codable { case allow, deny }

struct ApprovalResponse: Codable {
    let id: String
    let decision: Decision

    func encodeLine() -> String {
        let data = try! JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8)! + "\n"
    }
}
```

- [ ] **Step 6: 运行，确认通过**

Run: `cd daemon && swift test 2>&1 | tail -20`
Expected: 2 tests passed

- [ ] **Step 7: Commit**

```bash
git add daemon/Package.swift daemon/Sources/CDFR daemon/Sources/tbcd/Protocol.swift daemon/Tests && git commit -m "feat(tbcd): SPM 骨架 + 审批协议编解码 (TDD)"
```

---

### Task 5: RequestQueue 线程安全 FIFO（TDD）

**Files:**
- Create: `daemon/Sources/tbcd/RequestQueue.swift`
- Create: `daemon/Tests/tbcdTests/RequestQueueTests.swift`

**目的:** 多会话并发请求入队，一次只暴露一条给 UI，完成后取下一条。每个请求带一个 continuation/回调，决定产生时回传。

- [ ] **Step 1: 写失败测试**

`daemon/Tests/tbcdTests/RequestQueueTests.swift`:
```swift
import XCTest
@testable import tbcd

final class RequestQueueTests: XCTestCase {
    func req(_ id: String) -> ApprovalRequest {
        ApprovalRequest(id: id, session: "p", cwd: "/p", tool: "Bash", summary: "x", queueRemaining: 0)
    }

    func testFIFOOrderAndResolve() {
        let q = RequestQueue()
        var presented: [String] = []
        q.onPresent = { presented.append($0.id) }   // 当某请求成为"当前"时回调

        var got1: Decision?
        q.enqueue(req("a")) { got1 = $0 }            // a 立即成为当前
        var got2: Decision?
        q.enqueue(req("b")) { got2 = $0 }            // b 排队

        XCTAssertEqual(presented, ["a"])             // 只展示 a
        q.resolveCurrent(.allow)                     // a 完成 → 展示 b
        XCTAssertEqual(got1, .allow)
        XCTAssertEqual(presented, ["a", "b"])
        q.resolveCurrent(.deny)
        XCTAssertEqual(got2, .deny)
    }

    func testRemainingCount() {
        let q = RequestQueue()
        q.onPresent = { _ in }
        q.enqueue(req("a")) { _ in }
        q.enqueue(req("b")) { _ in }
        q.enqueue(req("c")) { _ in }
        XCTAssertEqual(q.remaining, 2)               // 当前 a 外还有 b,c
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `cd daemon && swift test --filter RequestQueueTests 2>&1 | tail -15`
Expected: 编译失败（`RequestQueue` 未定义）

- [ ] **Step 3: 实现 RequestQueue**

`daemon/Sources/tbcd/RequestQueue.swift`:
```swift
import Foundation

final class RequestQueue {
    private struct Pending { let req: ApprovalRequest; let resolve: (Decision) -> Void }
    private var items: [Pending] = []
    private let lock = NSLock()

    /// 当一个请求成为"当前展示项"时回调（主线程）
    var onPresent: ((ApprovalRequest) -> Void)?
    /// 当队列清空时回调（释放 Touch Bar）
    var onIdle: (() -> Void)?

    /// 当前项之外仍在排队的数量
    var remaining: Int {
        lock.lock(); defer { lock.unlock() }
        return max(0, items.count - 1)
    }

    func enqueue(_ req: ApprovalRequest, resolve: @escaping (Decision) -> Void) {
        lock.lock()
        items.append(Pending(req: req, resolve: resolve))
        let shouldPresent = items.count == 1
        let current = items.first?.req
        lock.unlock()
        if shouldPresent, let current { onPresent?(current) }
    }

    func resolveCurrent(_ decision: Decision) {
        lock.lock()
        guard !items.isEmpty else { lock.unlock(); return }
        let done = items.removeFirst()
        let next = items.first?.req
        lock.unlock()
        done.resolve(decision)
        if let next { onPresent?(next) } else { onIdle?() }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `cd daemon && swift test --filter RequestQueueTests 2>&1 | tail -15`
Expected: 2 tests passed

- [ ] **Step 5: Commit**

```bash
git add daemon/Sources/tbcd/RequestQueue.swift daemon/Tests/tbcdTests/RequestQueueTests.swift
git commit -m "feat(tbcd): 线程安全 FIFO 请求队列 (TDD)"
```

---

### Task 6: SocketServer Unix socket 监听

**Files:**
- Create: `daemon/Sources/tbcd/SocketServer.swift`

**目的:** 监听 Unix domain socket，每个连接读一行请求 → 投队列 → 等决定 → 写回响应 → 关闭。难以纯单元测试（涉及真实 socket），用一个手动集成测试脚本验证。

- [ ] **Step 1: 实现 SocketServer**

`daemon/Sources/tbcd/SocketServer.swift`:
```swift
import Foundation

final class SocketServer {
    private let path: String
    private var listenFD: Int32 = -1
    private let queue: RequestQueue

    init(path: String, queue: RequestQueue) {
        self.path = path
        self.queue = queue
    }

    func start() throws {
        unlink(path)
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EINVAL) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        path.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) {
                $0.withMemoryRebound(to: CChar.self, capacity: 104) { dst in
                    strncpy(dst, src, 103)
                }
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, len) }
        }
        guard bound == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EADDRINUSE) }
        guard listen(listenFD, 16) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EINVAL) }

        Thread.detachNewThread { [weak self] in self?.acceptLoop() }
    }

    private func acceptLoop() {
        while true {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 { continue }
            Thread.detachNewThread { [weak self] in self?.handle(clientFD) }
        }
    }

    private func handle(_ fd: Int32) {
        defer { close(fd) }
        guard let line = readLine(fd), let req = try? ApprovalRequest.decode(from: line) else { return }
        let sem = DispatchSemaphore(value: 0)
        var decision: Decision = .deny
        DispatchQueue.main.async {
            self.queue.enqueue(req) { d in decision = d; sem.signal() }
        }
        sem.wait()
        let resp = ApprovalResponse(id: req.id, decision: decision).encodeLine()
        _ = resp.withCString { write(fd, $0, strlen($0)) }
    }

    private func readLine(_ fd: Int32) -> String? {
        var data = Data(); var byte: UInt8 = 0
        while read(fd, &byte, 1) == 1 {
            if byte == UInt8(ascii: "\n") { break }
            data.append(byte)
        }
        return data.isEmpty ? nil : String(data: data, encoding: .utf8)
    }
}
```

- [ ] **Step 2: 临时 main 验证 socket（不接 Touch Bar）**

临时把 `daemon/Sources/tbcd/main.swift` 写为：
```swift
import Foundation

let q = RequestQueue()
// 无 UI：收到请求立即自动 allow，用于验证 socket 链路
q.onPresent = { req in
    print("收到请求: \(req.session) \(req.tool) \(req.summary)")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { q.resolveCurrent(.allow) }
}
let sock = "\(NSHomeDirectory())/.touchbar-cc/tbcd.sock"
try! FileManager.default.createDirectory(atPath: "\(NSHomeDirectory())/.touchbar-cc", withIntermediateDirectories: true)
let server = SocketServer(path: sock, queue: q)
try! server.start()
print("监听: \(sock)")
RunLoop.main.run()
```

- [ ] **Step 3: 构建并起守护进程**

Run: `cd daemon && swift build 2>&1 | tail -10 && ./.build/debug/tbcd &`
Expected: 打印 `监听: .../tbcd.sock`

- [ ] **Step 4: 用 hook.sh 端到端打通 socket**

Run:
```bash
echo '{"session_id":"s","cwd":"/tmp/demo","tool_name":"Bash","tool_input":{"command":"echo hi"}}' \
  | TBCC_SOCK="$HOME/.touchbar-cc/tbcd.sock" TBCC_TIMEOUT=5 bash hook/hook.sh
```
Expected: 输出 `{"hookSpecificOutput":{..."permissionDecision":"allow"...}}`，且守护进程端打印 `收到请求: demo Bash echo hi`

- [ ] **Step 5: 关掉临时守护进程**

Run: `kill %1 2>/dev/null; true`

- [ ] **Step 6: Commit**

```bash
git add daemon/Sources/tbcd/SocketServer.swift daemon/Sources/tbcd/main.swift
git commit -m "feat(tbcd): Unix socket 服务器，与 hook 端到端打通"
```

---

# M3 — Touch Bar UI（⚠️ 需 Task 1 Spike PASS）

### Task 7: CDFR 桥接 + TouchBarController

**Files:**
- Modify: `daemon/Sources/CDFR/include/CDFR.h`
- Create: `daemon/Sources/CDFR/shim.c`
- Create: `daemon/Sources/tbcd/TouchBarController.swift`

> 用 Task 1 Spike 中**实测可用**的接管方式实现。下方按 Spike 的 `presentSystemModalTouchBar:` selector 路线写；若 Spike 发现别的可用路径，以 Spike 为准替换。

- [ ] **Step 1: 声明私有符号桥接**

`daemon/Sources/CDFR/include/CDFR.h`:
```c
#ifndef CDFR_H
#define CDFR_H
#include <stdbool.h>
void DFRSystemModalShowsCloseBoxWhenFrontMost(bool show);
#endif
```
`daemon/Sources/CDFR/shim.c`:
```c
// 符号由 DFRFoundation 私有框架在链接期提供，这里无需实现体。
```
更新 `daemon/Sources/CDFR/module.modulemap`（已存在）保持 `header "include/CDFR.h"`。

- [ ] **Step 2: 实现 TouchBarController**

`daemon/Sources/tbcd/TouchBarController.swift`:
```swift
import AppKit
import CDFR

final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let itemId = NSTouchBarItem.Identifier("com.touchbarcc.approval")
    private var touchBar: NSTouchBar?
    private var approvalView: ApprovalView?
    var onSwipe: ((Decision) -> Void)?

    func present(_ req: ApprovalRequest) {
        if touchBar == nil {
            DFRSystemModalShowsCloseBoxWhenFrontMost(false)
            let tb = NSTouchBar()
            tb.delegate = self
            tb.defaultItemIdentifiers = [Self.itemId]
            touchBar = tb
            Self.presentSystemModal(tb)
        }
        approvalView?.update(req)
    }

    func dismiss() {
        if let tb = touchBar { Self.dismissSystemModal(tb) }
        touchBar = nil
        approvalView = nil
    }

    func touchBar(_ tb: NSTouchBar, makeItemForIdentifier id: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard id == Self.itemId else { return nil }
        let item = NSCustomTouchBarItem(identifier: id)
        let v = ApprovalView()
        v.onDecision = { [weak self] d in self?.onSwipe?(d) }
        approvalView = v
        item.view = v
        return item
    }

    // MARK: 私有 system-modal 调用（与 Spike 一致）
    static func presentSystemModal(_ tb: NSTouchBar) {
        let sel = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
        guard NSTouchBar.responds(to: sel) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, NSTouchBar, NSString) -> Void
        unsafeBitCast(NSTouchBar.method(for: sel), to: Fn.self)(
            NSTouchBar.self, sel, tb, "com.touchbarcc.tray" as NSString)
    }
    static func dismissSystemModal(_ tb: NSTouchBar) {
        let sel = NSSelectorFromString("dismissSystemModalTouchBar:")
        guard NSTouchBar.responds(to: sel) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, NSTouchBar) -> Void
        unsafeBitCast(NSTouchBar.method(for: sel), to: Fn.self)(NSTouchBar.self, sel, tb)
    }
}
```

- [ ] **Step 3: 构建确认编译通过**

Run: `cd daemon && swift build 2>&1 | tail -15`
Expected: 编译通过（ApprovalView 在 Task 8 创建，这一步会因 ApprovalView 缺失而失败 → 先建空壳）。

- [ ] **Step 4: 建 ApprovalView 空壳让其编译**

临时 `daemon/Sources/tbcd/ApprovalView.swift`:
```swift
import AppKit
final class ApprovalView: NSView {
    var onDecision: ((Decision) -> Void)?
    func update(_ req: ApprovalRequest) {}
}
```
Run: `cd daemon && swift build 2>&1 | tail -10`
Expected: 编译通过

- [ ] **Step 5: Commit**

```bash
git add daemon/Sources/CDFR daemon/Sources/tbcd/TouchBarController.swift daemon/Sources/tbcd/ApprovalView.swift
git commit -m "feat(tbcd): CDFR 桥接 + TouchBarController 接管/释放"
```

---

### Task 8: ApprovalView 渲染 + 滑动手势

**Files:**
- Modify: `daemon/Sources/tbcd/ApprovalView.swift`

- [ ] **Step 1: 实现完整 ApprovalView**

`daemon/Sources/tbcd/ApprovalView.swift`:
```swift
import AppKit

private func emoji(for tool: String) -> String {
    switch tool {
    case "Bash": return "⚡"
    case "Edit", "MultiEdit": return "✏️"
    case "Write": return "📝"
    case "NotebookEdit": return "📓"
    default: return "🔧"
    }
}

final class ApprovalView: NSView {
    var onDecision: ((Decision) -> Void)?
    private let label = NSTextField(labelWithString: "")
    private var startX: CGFloat = 0
    private let threshold: CGFloat = 60

    override init(frame: NSRect) {
        super.init(frame: frame)
        allowedTouchTypes = [.direct]
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: 600)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ req: ApprovalRequest) {
        let sessionTag = req.queueRemaining > 0 ? "[\(req.session) +\(req.queueRemaining)]" : "[\(req.session)]"
        var sum = req.summary.replacingOccurrences(of: "\n", with: " ")
        if sum.count > 35 { sum = String(sum.prefix(35)) + "…" }
        label.stringValue = "✗  \(sessionTag) \(emoji(for: req.tool)) \(req.tool)  \(sum)  ✓"
    }

    override func touchesBegan(with event: NSEvent) {
        startX = event.allTouches().first?.location(in: self).x ?? 0
    }
    override func touchesEnded(with event: NSEvent) {
        let endX = event.allTouches().first?.location(in: self).x ?? 0
        let dx = endX - startX
        if dx > threshold { onDecision?(.allow) }
        else if dx < -threshold { onDecision?(.deny) }
        // 阈值内不触发，等待再次操作
    }
}
```

- [ ] **Step 2: 构建**

Run: `cd daemon && swift build 2>&1 | tail -10`
Expected: 编译通过

- [ ] **Step 3: Commit**

```bash
git add daemon/Sources/tbcd/ApprovalView.swift
git commit -m "feat(tbcd): 审批界面渲染 + 左右滑手势判定"
```

---

### Task 9: 组装 main.swift + MenuBarController（接通全链路）

**Files:**
- Create: `daemon/Sources/tbcd/MenuBarController.swift`
- Modify: `daemon/Sources/tbcd/main.swift`

- [ ] **Step 1: 实现 MenuBarController**

`daemon/Sources/tbcd/MenuBarController.swift`:
```swift
import AppKit

final class MenuBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    init(capable: Bool) {
        statusItem.button?.title = capable ? "⌇" : "⚠️"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: capable ? "touchbar-cc 运行中" : "Touch Bar 不可用（请求将回退终端）",
                                action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
}
```

- [ ] **Step 2: 实现正式 main.swift**

`daemon/Sources/tbcd/main.swift`（覆盖临时版）:
```swift
import AppKit
import CDFR

final class AppDelegate: NSObject, NSApplicationDelegate {
    let queue = RequestQueue()
    let touchBar = TouchBarController()
    var menu: MenuBarController?

    func applicationDidFinishLaunching(_ n: Notification) {
        // 能力探测：presentSystemModalTouchBar selector 是否存在
        let capable = NSTouchBar.responds(to: NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:"))
        menu = MenuBarController(capable: capable)

        touchBar.onSwipe = { [weak self] decision in
            self?.queue.resolveCurrent(decision)
        }
        queue.onPresent = { [weak self] req in
            DispatchQueue.main.async { self?.touchBar.present(req) }
        }
        queue.onIdle = { [weak self] in
            DispatchQueue.main.async { self?.touchBar.dismiss() }
        }

        let dir = "\(NSHomeDirectory())/.touchbar-cc"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let sock = "\(dir)/tbcd.sock"
        do {
            let server = SocketServer(path: sock, queue: queue)
            try server.start()
            NSLog("touchbar-cc 监听 \(sock) capable=\(capable)")
        } catch {
            NSLog("touchbar-cc socket 启动失败: \(error)")
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 3: 构建**

Run: `cd daemon && swift build 2>&1 | tail -10`
Expected: 编译通过

- [ ] **Step 4: 手动端到端（单会话）**

Run: `cd daemon && ./.build/debug/tbcd & sleep 1`
然后触发一次申请：
```bash
echo '{"session_id":"s","cwd":"/tmp/myproj","tool_name":"Bash","tool_input":{"command":"npm run build"}}' \
  | TBCC_TIMEOUT=20 bash ../hook/hook.sh &
```
观察：Touch Bar 出现审批条 `✗ [myproj] ⚡ Bash npm run build ✓`，右滑 → hook 输出 `allow` JSON；左滑 → `deny`。
Run: `kill %1 2>/dev/null; true`

- [ ] **Step 5: Commit**

```bash
git add daemon/Sources/tbcd/MenuBarController.swift daemon/Sources/tbcd/main.swift
git commit -m "feat(tbcd): 菜单栏 + 全链路组装，单会话端到端可用"
```

---

# M4 — 打包与安装

### Task 10: 组装 .app bundle + LaunchAgent + install.sh

**Files:**
- Create: `install.sh`
- Create: `packaging/Info.plist`
- Create: `packaging/com.touchbarcc.tbcd.plist`

- [ ] **Step 1: 写 Info.plist（LSUIElement 隐藏 Dock 图标）**

`packaging/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>tbcd</string>
  <key>CFBundleIdentifier</key><string>com.touchbarcc.tbcd</string>
  <key>CFBundleName</key><string>tbcd</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
```

- [ ] **Step 2: 写 LaunchAgent plist**

`packaging/com.touchbarcc.tbcd.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.touchbarcc.tbcd</string>
  <key>ProgramArguments</key>
  <array><string>__APP_PATH__/Contents/MacOS/tbcd</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict></plist>
```

- [ ] **Step 3: 写 install.sh**

`install.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="/Applications/tbcd.app"
HOOK_DIR="$HOME/.claude/hooks/touchbar-cc"
SETTINGS="$HOME/.claude/settings.json"
LA="$HOME/Library/LaunchAgents/com.touchbarcc.tbcd.plist"

echo "==> 构建 release"
( cd "$ROOT/daemon" && swift build -c release )

echo "==> 组装 .app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/daemon/.build/release/tbcd" "$APP/Contents/MacOS/tbcd"
cp "$ROOT/packaging/Info.plist" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "(ad-hoc 签名跳过)"

echo "==> 安装 hook"
mkdir -p "$HOOK_DIR"
cp "$ROOT/hook/hook.sh" "$HOOK_DIR/hook.sh"
chmod +x "$HOOK_DIR/hook.sh"

echo "==> 注入 settings.json (幂等)"
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
TMP="$(mktemp)"
jq --arg cmd "bash $HOOK_DIR/hook.sh" '
  .hooks //= {} |
  .hooks.PreToolUse //= [] |
  if any(.hooks.PreToolUse[]?; .hooks[]?.command == $cmd) then .
  else .hooks.PreToolUse += [{
    "matcher":"Bash|Edit|Write|MultiEdit|NotebookEdit",
    "hooks":[{"type":"command","command":$cmd}]
  }] end
' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"

echo "==> 安装 LaunchAgent"
mkdir -p "$(dirname "$LA")"
sed "s#__APP_PATH__#$APP#g" "$ROOT/packaging/com.touchbarcc.tbcd.plist" > "$LA"
launchctl unload "$LA" 2>/dev/null || true
launchctl load "$LA"

echo "==> 完成。tbcd 已启动并随登录运行。"
echo "    验证: 菜单栏应出现 ⌇ 图标；在 CC 里跑一条 Bash 命令试试。"
echo "    若图标为 ⚠️，表示 Touch Bar 私有 API 不可用，请求会回退终端。"
```

- [ ] **Step 4: 运行安装**

Run: `chmod +x install.sh && ./install.sh 2>&1 | tail -20`
Expected: 各步骤打印 OK，菜单栏出现图标，`launchctl list | grep touchbarcc` 有记录。

- [ ] **Step 5: 校验 settings.json 注入正确且幂等**

Run: `jq '.hooks.PreToolUse' "$HOME/.claude/settings.json"`
Expected: 含 touchbar-cc 的 matcher。再跑一次 `./install.sh`，确认 PreToolUse 数组未重复添加。

- [ ] **Step 6: Commit**

```bash
git add install.sh packaging/
git commit -m "feat: .app 打包 + LaunchAgent + 幂等安装脚本"
```

---

# M5 — 端到端与回退验证

### Task 11: 多会话排队 + 回退路径验证

**Files:**
- Create: `VERIFY.md`（仓库根，验证记录）

- [ ] **Step 1: 多会话并发排队**

开两个终端，各起一个 CC 会话，几乎同时各触发一条 Bash 申请。
观察：Touch Bar 一次只显示一条，左区显示 `[proj +1]`；处理完第一条后立即切到第二条；两个 hook 各自收到正确决定。

- [ ] **Step 2: 回退 — 守护进程未运行**

Run: `launchctl unload "$HOME/Library/LaunchAgents/com.touchbarcc.tbcd.plist"`
在 CC 里触发 Bash 申请。
Expected: CC 显示**原生终端权限提示**（y/n），无卡顿、无长延迟。

- [ ] **Step 3: 回退 — 超时**

重新 `launchctl load` 启动守护进程，触发申请后**不去碰 Touch Bar**，等 hook 超时。
Expected: 超时后 CC 回退原生提示（或按 CC 对无输出 hook 的默认行为处理）。记录实际表现到 VERIFY.md。

- [ ] **Step 4: 回退 — 能力不可用模拟**

若 Spike 为 PASS，本步可跳过；否则确认菜单栏 ⚠️ 状态下所有请求立即回退。

- [ ] **Step 5: 记录验证结果**

`VERIFY.md` 记录每个场景的实际表现（通过/问题）。

- [ ] **Step 6: Commit**

```bash
git add VERIFY.md
git commit -m "test: 多会话排队与回退路径端到端验证记录"
```

---

### Task 12: README + 清理

**Files:**
- Create: `README.md`
- Create: `uninstall.sh`

- [ ] **Step 1: 写 README**

`README.md` 涵盖：用途、要求（M2 2022 Touch Bar + macOS）、安装（`./install.sh`）、工作原理（一段 + 架构图引用 spec）、卸载、故障排查（菜单栏 ⚠️ 含义、如何看日志 `log show --predicate 'process == "tbcd"'`）。

- [ ] **Step 2: 写 uninstall.sh**

`uninstall.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
LA="$HOME/Library/LaunchAgents/com.touchbarcc.tbcd.plist"
launchctl unload "$LA" 2>/dev/null || true
rm -f "$LA"
rm -rf /Applications/tbcd.app
rm -rf "$HOME/.claude/hooks/touchbar-cc"
echo "已移除 app / LaunchAgent / hook 脚本。"
echo "请手动从 ~/.claude/settings.json 的 hooks.PreToolUse 删除 touchbar-cc 条目。"
rm -rf "$HOME/.touchbar-cc"
```

- [ ] **Step 3: 清理临时文件**

Run: `rm -f "$HOME/.touchbar-cc/last-input.json"`（探针残留）

- [ ] **Step 4: Commit**

```bash
chmod +x uninstall.sh
git add README.md uninstall.sh
git commit -m "docs: README + 卸载脚本"
```

---

## 风险与备注

- **最大风险**: Task 1 Spike。私有 `presentSystemModalTouchBar:` selector 在 macOS 26.5 可能已变更/移除。Spike FAIL → 回退 spec §7 BTT 方案（交互降级为点击 ✗/✓ 按钮，hook+socket 架构基本复用，仅 Task 7-9 改为驱动 BTT）。
- **CC hook 契约不确定**: Task 2 探针先于一切实现 dump 真实字段，Task 3 据实调整。若 `permissionDecision` 字段名/结构与假设不同，只需改 hook.sh 最后的输出 JSON。
- **CC hook 超时上限未知**: 若 CC 对 hook 有内置超时且短于 55s，hook 会被强杀（表现为回退原生提示，安全但 Touch Bar 操作窗口变短）。Task 11 Step 3 实测后，按需调小 `TBCC_TIMEOUT`。
- **代码签名**: 用 ad-hoc 签名；首次运行可能需在「系统设置 → 隐私与安全性」放行，并授予「辅助功能/输入监控」（若手势捕获需要）。README 故障排查覆盖。
- **无 Xcode**: 全程 `swift build`，不依赖 `xcodebuild`。
