#!/usr/bin/env bash
# gnome-theme / doctor.sh —— 桌面环境体检，只读，不改任何设置
# 用法: ./scripts/doctor.sh
set -uo pipefail

c_head=$'\033[1;36m'; c_key=$'\033[0;37m'; c_val=$'\033[0;32m'
c_warn=$'\033[0;33m'; c_bad=$'\033[0;31m'; c_off=$'\033[0m'

h() { printf '\n%s== %s ==%s\n' "$c_head" "$1" "$c_off"; }
# 显示宽度：按 (UTF-8 字节数 + 字符数 + 1)/2 估算（CJK 算 2 列，ASCII 算 1 列）
dw() { local b; b=$(LC_ALL=C; printf '%s' "$1" | wc -c); echo $(( (b + ${#1} + 1) / 2 )); }
kv() {
  local label=${1:-} val=${2:-—} pad
  pad=$(( 22 - $(dw "$label") )); [ "$pad" -lt 1 ] && pad=1
  printf '  %s%s%s%*s %s\n' "$c_key" "$label" "$c_off" "$pad" "" "$val"
}

has() { command -v "$1" >/dev/null 2>&1; }

h "系统"
kv "发行版" "$(grep -s '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')"
kv "内核" "$(uname -r)"
kv "主机" "$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo '未知')"
kv "机箱类型" "$(case "$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)" in 3|4|5|6|7|23) echo 台式机;; 8|9|10|14) echo 笔记本;; *) echo 未知;; esac)"
kv "内存" "$(awk '/MemTotal/{printf "%.0f GiB", $2/1024/1024}' /proc/meminfo)"

h "桌面会话"
kv "GNOME Shell" "$(gnome-shell --version 2>/dev/null || echo '未安装')"
kv "会话类型" "${XDG_SESSION_TYPE:-未知}"
kv "桌面环境" "${XDG_CURRENT_DESKTOP:-未知}"
kv "显示服务器" "$( [[ ${XDG_SESSION_TYPE:-} == wayland ]] && echo "Wayland（${WAYLAND_DISPLAY:-?}）" || echo "${DISPLAY:-未知}" )"
kv "显示管理器" "$(systemctl is-active gdm 2>/dev/null || echo 未运行)"

h "显卡与显示器"
if has lspci; then
  lspci 2>/dev/null | grep -Ei 'vga|3d controller|display' | sed 's/^/  /'
fi
for dev in /sys/class/drm/card*-*; do
  [ -e "$dev/status" ] || continue
  st=$(cat "$dev/status" 2>/dev/null)
  [ "$st" = "connected" ] || continue
  mode=$(sed -n '1p' "$dev/modes" 2>/dev/null)
  n=$(wc -l < "$dev/modes" 2>/dev/null)
  printf '  %-18s %s  %s（共 %s 个模式）\n' "${dev##*/}" "已连接" "${mode:-?}" "${n:-0}"
done
if [ -f "$HOME/.config/monitors.xml" ]; then
  mw=$(grep -o '<width>[0-9]*' "$HOME/.config/monitors.xml" | head -1 | cut -d'>' -f2)
  mh=$(grep -o '<height>[0-9]*' "$HOME/.config/monitors.xml" | head -1 | cut -d'>' -f2)
  mr=$(grep -o '<rate>[0-9.]*' "$HOME/.config/monitors.xml" | head -1 | cut -d'>' -f2)
  ms=$(grep -o '<scale>[0-9.]*' "$HOME/.config/monitors.xml" | head -1 | cut -d'>' -f2)
  printf '  %s×%s @%sHz 缩放 %s\n' "${mw:-?}" "${mh:-?}" "${mr:-?}" "${ms:-1}"
fi

h "外观设置"
gs() { gsettings get "$1" "$2" 2>/dev/null | sed "s/^'//; s/'$//"; }
kv "配色方案" "$(gs org.gnome.desktop.interface color-scheme)"
kv "强调色" "$(gs org.gnome.desktop.interface accent-color)"
kv "GTK 主题" "$(gs org.gnome.desktop.interface gtk-theme)"
kv "图标主题" "$(gs org.gnome.desktop.interface icon-theme)"
kv "光标" "$(gs org.gnome.desktop.interface cursor-theme) $(gs org.gnome.desktop.interface cursor-size)"
kv "界面字体" "$(gs org.gnome.desktop.interface font-name)"
kv "等宽字体" "$(gs org.gnome.desktop.interface monospace-font-name)"
kv "标题栏字体" "$(gsettings get org.gnome.desktop.wm.preferences titlebar-font 2>/dev/null | sed "s/^'//; s/'$//")"
kv "标题栏按钮" "$(gsettings get org.gnome.desktop.wm.preferences button-layout 2>/dev/null | sed "s/^'//; s/'$//")"
kv "Shell 主题" "$(gsettings get org.gnome.shell.extensions.user-theme name 2>/dev/null | sed "s/^'//; s/'$//" || echo '未安装 User Themes')"

h "已装主题 / 图标"
for d in /usr/share/themes "$HOME/.themes" "$HOME/.local/share/themes"; do
  [ -d "$d" ] && printf '  %s: %s\n' "$d" "$(ls "$d" 2>/dev/null | tr '\n' ' ' || echo 空)"
done
for d in /usr/share/icons "$HOME/.icons" "$HOME/.local/share/icons"; do
  [ -d "$d" ] && printf '  %s: %s\n' "$d" "$(ls "$d" 2>/dev/null | grep -v -E '^(default|hicolor|locolor|gnome-logo)' | tr '\n' ' ' || echo 空)"
done

h "字体"
if has fc-list; then
  kv "中文字体" "$(fc-list :lang=zh family 2>/dev/null | cut -d, -f1 | sort -u | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-90)"
  for f in Inter "Noto Sans CJK SC" "Maple Mono CN" "JetBrains Mono"; do
    if fc-match -f '%{family}' "$f" 2>/dev/null | grep -qi "^$f"; then
      printf '  %s✓%s %s\n' "$c_val" "$c_off" "$f"
    else
      printf '  %s✗%s %s（未安装）\n' "$c_warn" "$c_off" "$f"
    fi
  done
fi

h "扩展"
enabled=$(gnome-extensions list --enabled 2>/dev/null)
if [ -z "$enabled" ]; then
  kv "已启用" "无（纯默认界面）"
else
  echo "$enabled" | sed 's/^/  • /'
fi
kv "用户扩展目录" "$(ls "$HOME/.local/share/gnome-shell/extensions" 2>/dev/null | wc -l) 个"

h "工具链"
for t in yay paru flatpak gnome-tweaks dconf-editor extension-manager gnome-browser-connector curl unzip git magick; do
  if has "$t"; then printf '  %s✓%s %-24s %s\n' "$c_val" "$c_off" "$t" "$(command -v "$t")"
  else printf '  %s·%s %-24s 未安装\n' "$c_warn" "$c_off" "$t"; fi
done

h "潜在问题"
issues=0
[ "$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null)" = "'Adwaita'" ] && { echo "  • 仍在使用默认 Adwaita 主题（未做任何美化）"; issues=$((issues+1)); }
[ -z "$(gnome-extensions list --enabled 2>/dev/null)" ] && { echo "  • 没有启用任何 GNOME 扩展（无 Dock / 无模糊 / 无托盘）"; issues=$((issues+1)); }
if has fc-list && ! fc-list :lang=zh family 2>/dev/null | grep -qv -i 'maple'; then
  echo "  • 系统中文字体只有 Maple Mono CN（等宽），缺中文无衬线正文字体"; issues=$((issues+1))
fi
mon=$(ls -d /sys/class/drm/card*-DP-* /sys/class/drm/card*-HDMI-* 2>/dev/null | while read -r d; do [ "$(cat "$d/status" 2>/dev/null)" = connected ] && echo "$d"; done | head -1)
if [ -n "$mon" ]; then
  rate=$(grep -o '<rate>[0-9.]*' "$HOME/.config/monitors.xml" 2>/dev/null | head -1 | tr -d '<rate>')
  if [ -n "$rate" ] && awk -v r="$rate" 'BEGIN{exit !(r<90)}'; then
    echo "  • 刷新率 ${rate}Hz，若显示器支持高刷可在 设置 → 显示器 中调高"; issues=$((issues+1))
  fi
fi
[ "$issues" -eq 0 ] && echo "  • 未发现明显问题"

echo
