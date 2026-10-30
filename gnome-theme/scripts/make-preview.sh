#!/usr/bin/env bash
# 生成方案预览卡片（配色 + 壁纸 + 字体示意）
# 依赖：imagemagick + Maple Mono CN（系统中文字体）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/preview/style-card.png"
SANS="Adwaita-Sans"
SANS_B="Adwaita-Sans-Bold"
MONO_B="Adwaita-Mono-Bold"
CJK="/usr/share/fonts/MapleMono-CN-Regular.ttf"

mkdir -p "$ROOT/preview"

magick -size 1600x1060 xc:'#0b0f14' \
  -font "$SANS_B" -pointsize 48 -fill '#e6edf3' -annotate +80+100 'Arctic Ink' \
  -font "$CJK" -pointsize 18 -fill '#5d7285' -annotate +80+140 'Arch Linux · GNOME 51.1 · Wayland · 2560×1440 @1.25×' \
  \
  -fill '#101b25' -draw 'roundrectangle 80,180 1000,700 20,20' \
  \( "$ROOT/wallpapers/arctic-ink-2560x1440.png" -resize 880x495! \) -geometry +100+192 -compose over -composite \
  -stroke '#213445' -strokewidth 2 -fill none -draw 'roundrectangle 100,192 980,687 12,12' -stroke none \
  \
  -font "$SANS_B" -pointsize 22 -fill '#e6edf3' -annotate +1050+207 'PALETTE' \
  -font "$CJK" -pointsize 15 -fill '#5d7285' -annotate +1050+235 '深色为主 · 青绿强调 · 冷蓝辅助' \
  \
  -fill '#0e1a24' -draw 'roundrectangle 1050,262 1112,324 14,14' \
  -stroke '#22384a' -strokewidth 2 -draw 'roundrectangle 1050,262 1112,324 14,14' -stroke none \
  -font "$MONO_B" -pointsize 20 -fill '#e6edf3' -annotate +1130+292 '#0E1A24' \
  -font "$CJK" -pointsize 14 -fill '#93a4b4' -annotate +1130+316 '底色 / 壁纸暗部' \
  \
  -fill '#16242f' -draw 'roundrectangle 1050,350 1112,412 14,14' \
  -stroke '#22384a' -strokewidth 2 -draw 'roundrectangle 1050,350 1112,412 14,14' -stroke none \
  -font "$MONO_B" -pointsize 20 -fill '#e6edf3' -annotate +1130+380 '#16242F' \
  -font "$CJK" -pointsize 14 -fill '#93a4b4' -annotate +1130+404 '浮层 / 卡片 / 面板' \
  \
  -fill '#2ec6b0' -draw 'roundrectangle 1050,438 1112,500 14,14' \
  -font "$MONO_B" -pointsize 20 -fill '#e6edf3' -annotate +1130+468 '#2EC6B0' \
  -font "$CJK" -pointsize 14 -fill '#93a4b4' -annotate +1130+492 '强调色 accent = teal' \
  \
  -fill '#7aa2f7' -draw 'roundrectangle 1050,526 1112,588 14,14' \
  -font "$MONO_B" -pointsize 20 -fill '#e6edf3' -annotate +1130+556 '#7AA2F7' \
  -font "$CJK" -pointsize 14 -fill '#93a4b4' -annotate +1130+580 '辅助色 / 选中 / 链接' \
  \
  -fill '#e6edf3' -draw 'roundrectangle 1050,614 1112,676 14,14' \
  -font "$MONO_B" -pointsize 20 -fill '#e6edf3' -annotate +1130+644 '#E6EDF3' \
  -font "$CJK" -pointsize 14 -fill '#93a4b4' -annotate +1130+668 '主文字 / 高对比' \
  \
  -fill '#93a4b4' -draw 'roundrectangle 1050,702 1112,764 14,14' \
  -font "$MONO_B" -pointsize 20 -fill '#e6edf3' -annotate +1130+732 '#93A4B4' \
  -font "$CJK" -pointsize 14 -fill '#93a4b4' -annotate +1130+756 '次级文字 / 说明' \
  \
  -font "$SANS_B" -pointsize 22 -fill '#e6edf3' -annotate +80+790 'TYPOGRAPHY' \
  -font "$SANS_B" -pointsize 34 -fill '#e6edf3' -annotate +80+845 'Inter' \
  -font "$CJK" -pointsize 19 -fill '#c3d0da' -annotate +210+843 '界面正文 11pt · 字重齐全' \
  -font "$CJK" -pointsize 14 -fill '#5d7285' -annotate +80+872 '几何无衬线，小字号清晰；替代默认 Adwaita Sans 更有精神' \
  -font "$CJK" -pointsize 26 -fill '#e6edf3' -annotate +80+930 'Maple Mono CN' \
  -font "$CJK" -pointsize 15 -fill '#c3d0da' -annotate +360+928 '等宽 11pt · 中英对齐' \
  -font "$CJK" -pointsize 14 -fill '#5d7285' -annotate +80+958 '已内置，直接用于终端 / 代码，无需额外下载' \
  \
  -font "$CJK" -pointsize 15 -fill '#5d7285' \
  -annotate +80+1010 '图标 Papirus-Dark　光标 Bibata-Modern-Ice 24　窗口按钮 最小化 / 最大化 / 关闭　强调色 teal' \
  -depth 8 -strip "$OUT"

echo "生成: $OUT"
magick identify "$OUT"
