#!/usr/bin/env bash
# 生成配套壁纸（Arctic Ink 深色 / Arctic Mist 浅色）
# 依赖：imagemagick (magick) —— Arch: pacman -S imagemagick
# 用法: ./make-wallpapers.sh [输出目录]
set -euo pipefail

OUT="${1:-$(cd "$(dirname "$0")/.." && pwd)/wallpapers}"
W=2560
H=1440
mkdir -p "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v magick >/dev/null || { echo "需要 imagemagick" >&2; exit 1; }

# 一个柔和的径向光斑：$1=尺寸 $2=颜色(r,g,b) $3=中心不透明度
blob() {
  local size=$1 color=$2 alpha=$3
  magick -size "${size}x${size}" radial-gradient:"rgba($color,${alpha})-rgba($color,0)" \
    -colorspace sRGB "$TMP/blob-${RANDOM}.png"
}

# ---------- 深色：Arctic Ink ----------
magick -size "${W}x${H}" gradient:'#12222e'-'#06090d' "$TMP/base-d.png"

magick -size 2000x2000 radial-gradient:'rgba(46,198,176,0.62)-rgba(46,198,176,0)' "$TMP/b1.png"
magick -size 1700x1700 radial-gradient:'rgba(76,110,245,0.52)-rgba(76,110,245,0)' "$TMP/b2.png"
magick -size 1300x1300 radial-gradient:'rgba(139,92,246,0.30)-rgba(139,92,246,0)' "$TMP/b3.png"
magick -size 1100x1100 radial-gradient:'rgba(46,198,176,0.22)-rgba(46,198,176,0)' "$TMP/b4.png"

magick "$TMP/base-d.png" \
  \( "$TMP/b1.png" \) -geometry -520-480 -compose over -composite \
  \( "$TMP/b2.png" \) -geometry +1500+780 -compose over -composite \
  \( "$TMP/b3.png" \) -geometry +1180-260 -compose over -composite \
  \( "$TMP/b4.png" \) -geometry +2100+150 -compose over -composite \
  -blur 0x70 \
  \( -size "${W}x${H}" radial-gradient:'#00000000-#00000040' \) -compose over -composite \
  -attenuate 0.055 +noise Gaussian -blur 0x0.4 \
  -depth 8 -strip "$OUT/arctic-ink-2560x1440.png"

# ---------- 浅色：Arctic Mist ----------
magick -size "${W}x${H}" gradient:'#eef4f7'-'#dbe6ec' "$TMP/base-l.png"

magick -size 2000x2000 radial-gradient:'rgba(46,180,160,0.38)-rgba(46,180,160,0)' "$TMP/l1.png"
magick -size 1700x1700 radial-gradient:'rgba(96,132,255,0.30)-rgba(96,132,255,0)' "$TMP/l2.png"
magick -size 1300x1300 radial-gradient:'rgba(180,160,255,0.22)-rgba(180,160,255,0)' "$TMP/l3.png"

magick "$TMP/base-l.png" \
  \( "$TMP/l1.png" \) -geometry -480-420 -compose over -composite \
  \( "$TMP/l2.png" \) -geometry +1460+700 -compose over -composite \
  \( "$TMP/l3.png" \) -geometry +1300-320 -compose over -composite \
  -blur 0x80 \
  -attenuate 0.03 +noise Gaussian -blur 0x0.4 \
  -depth 8 -strip "$OUT/arctic-mist-2560x1440.png"

echo "已生成:"
ls -lh "$OUT"/*.png | awk '{print "  "$9" ("$5")"}'
