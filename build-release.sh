#!/usr/bin/env bash
# 打包 touch-cc 为可分发的 tar.gz（含预编译 app + hook + install.command）
# 运行前提：本机有 Xcode + swift。产出放 dist/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
STAGING="$ROOT/dist/staging/touch-cc"

if [ -d /Applications/Xcode.app ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "==> 构建 release 二进制"
( cd "$ROOT/daemon" && swift build -c release )

echo "==> 组装分发目录"
rm -rf "$DIST"; mkdir -p "$STAGING/tbcd.app/Contents/MacOS"
cp "$ROOT/daemon/.build/release/tbcd" "$STAGING/tbcd.app/Contents/MacOS/tbcd"
cp "$ROOT/packaging/Info.plist" "$STAGING/tbcd.app/Contents/Info.plist"
codesign --force --deep --sign - "$STAGING/tbcd.app" 2>/dev/null || true
cp "$ROOT/hook/hook.sh" "$STAGING/hook.sh"
chmod +x "$STAGING/hook.sh"
cp "$ROOT/packaging/com.touchbarcc.tbcd.plist" "$STAGING/LaunchAgent.plist"
cp "$ROOT/dist-assets/install.command" "$STAGING/install.command"
chmod +x "$STAGING/install.command"
cp "$ROOT/dist-assets/uninstall.command" "$STAGING/uninstall.command"
chmod +x "$STAGING/uninstall.command"

echo "==> 打包 tar.gz"
( cd "$ROOT/dist/staging" && tar czf "$DIST/touch-cc.tar.gz" touch-cc )
rm -rf "$ROOT/dist/staging"

SIZE=$(du -h "$DIST/touch-cc.tar.gz" | cut -f1)
echo "==> 完成: dist/touch-cc.tar.gz ($SIZE)"
echo ""
echo "用户安装方式（上传到 GitHub Releases 后）："
echo '  curl -fsSL https://github.com/你的用户名/touch-cc/releases/latest/download/touch-cc.tar.gz | tar xz && ./touch-cc/install.command'
