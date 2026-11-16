#!/bin/bash
# 把 v30「声页」应用图标三变体装进 Xcode 资产目录。
#
# 用法：
#   scripts/install-icon.sh                  # 用本目录下的 AppIcon*.png
#   scripts/install-icon.sh <目录>            # 用指定目录里的 AppIcon*.png
#   scripts/install-icon.sh --regen           # 先重新生成（需要 playwright + Chromium）
#
# 为什么需要这个脚本：本仓库的写入通道只能逐字写入文本，二进制文件经该通道落库会变成
# base64 文本，Xcode 资产编译器会直接报错。所以图标 PNG 不随 PR 入库，改为本地安装。
# 矢量源（icon-light / icon-dark / icon-tinted.svg）与生成器（make-icon.py）都在仓库里。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
DEST="$ROOT/Tingye/Resources/Assets.xcassets/AppIcon.appiconset"
SRC="$HERE"

case "${1:-}" in
  --regen)
    echo "==> 重新生成图标（需要 playwright + Chromium）"
    (cd "$HERE" && python3 make-icon.py)
    SRC="$HERE"
    ;;
  "")
    ;;
  *)
    SRC="$1"
    ;;
esac

for n in AppIcon.png AppIcon-dark.png AppIcon-tinted.png; do
  if [ ! -f "$SRC/$n" ]; then
    echo "缺少 $SRC/$n" >&2
    echo "提示：可从交付的设计包里取，或先跑 'make-icon.py' 生成。" >&2
    exit 1
  fi
done

for n in AppIcon.png AppIcon-dark.png AppIcon-tinted.png; do
  cp "$SRC/$n" "$DEST/$n"
  echo "  ✓ $n"
done

echo "==> 已装入 $DEST"
echo "    确认：三个文件都是 1024×1024、RGB、无 alpha（iOS 资产校验会拒收带 alpha 的图标）。"
