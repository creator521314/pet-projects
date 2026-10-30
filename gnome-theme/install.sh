#!/usr/bin/env bash
# ============================================================================
#  Arctic Ink —— GNOME 美化方案安装器
#  适用于 Arch Linux + GNOME 51 (Wayland)，其他发行版需自行替换包管理器部分
#
#  用法:
#    ./install.sh doctor                # 只体检，不改任何东西
#    ./install.sh base                  # 安装依赖包（图标/字体/光标/主题）
#    ./install.sh theme                 # 安装壁纸、设置图标文件夹配色
#    ./install.sh extensions            # 安装并启用 GNOME 扩展
#    ./install.sh apply                 # 应用全部外观设置（可反复执行）
#    ./install.sh all                   # base + theme + extensions + apply
#    ./install.sh rollback              # 恢复安装前的设置
#    ./install.sh status                # 查看当前外观设置
#
#  选项:
#    --dry-run            只打印将执行的命令
#    --with-shell-theme   额外安装 Colloid 桌面主题（GNOME 51 兼容性无保证）
#    --no-extensions      跳过扩展安装
#    -y, --yes            包管理器免交互
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="$ROOT/backup"
WALLPAPER_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/backgrounds"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions"

CMD=""
DRY_RUN=0
WITH_SHELL_THEME=0
WITH_EXT=1
ASSUME_YES=0

c_d=$'\033[2m'; c_g=$'\033[0;32m'; c_y=$'\033[0;33m'; c_r=$'\033[0;31m'
c_b=$'\033[1;36m'; c_off=$'\033[0m'

say()  { printf '%s▸ %s%s\n' "$c_b" "$1" "$c_off"; }
info() { printf '  %s%s%s\n' "$c_d" "$1" "$c_off"; }
ok()   { printf '  %s✓%s %s\n' "$c_g" "$c_off" "$1"; }
warn() { printf '  %s!%s %s\n' "$c_y" "$c_off" "$1"; }
die()  { printf '%s错误:%s %s\n' "$c_r" "$c_off" "$1" >&2; exit 1; }

usage() { awk 'NR>2 { if (/^# ====/) exit; if (/^#/) { sub(/^# ?/,""); print } }' "${BASH_SOURCE[0]}"; }

have_theme() { [ -d "/usr/share/themes/$1" ] || [ -d "$HOME/.themes/$1" ] || [ -d "$HOME/.local/share/themes/$1" ]; }
have_icon()  { [ -d "/usr/share/icons/$1" ] || [ -d "$HOME/.icons/$1" ] || [ -d "$HOME/.local/share/icons/$1" ]; }

# 执行（尊重 --dry-run）
run() {
  if [ "$DRY_RUN" = 1 ]; then printf '  %s[dry] %s%s\n' "$c_d" "$*" "$c_off"; return 0; fi
  "$@"
}
runsh() {
  if [ "$DRY_RUN" = 1 ]; then printf '  %s[dry] %s%s\n' "$c_d" "$1" "$c_off"; return 0; fi
  bash -c "$1"
}

# ---------------------------------------------------------------------------
# 参数解析
# ---------------------------------------------------------------------------
[ $# -eq 0 ] && { usage; exit 0; }
while [ $# -gt 0 ]; do
  case "$1" in
    doctor|base|theme|extensions|apply|all|rollback|status) CMD="$1" ;;
    --dry-run)           DRY_RUN=1 ;;
    --with-shell-theme)  WITH_SHELL_THEME=1 ;;
    --no-extensions)     WITH_EXT=0 ;;
    -y|--yes)            ASSUME_YES=1 ;;
    -h|--help)           usage; exit 0 ;;
    *)                   die "未知参数: $1（--help 查看用法）" ;;
  esac
  shift
done
[ -n "$CMD" ] || die "请指定子命令（--help 查看用法）"

# ---------------------------------------------------------------------------
# 环境检查
# ---------------------------------------------------------------------------
need_gnome() {
  command -v gnome-shell >/dev/null || die "未找到 gnome-shell，这不是 GNOME 桌面"
  [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || warn "当前没有图形会话的 DBus，gsettings 可能不生效（建议在桌面终端里运行）"
}

is_arch() { [ -f /etc/arch-release ]; }

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null || die "需要 root 或 sudo 来安装系统软件包"
  SUDO="sudo"
fi
PAC_FLAGS=(--needed)
YAY_FLAGS=(--needed)
[ "$ASSUME_YES" = 1 ] && PAC_FLAGS+=(--noconfirm) && YAY_FLAGS+=(--noconfirm)

REPO_PKGS=(
  papirus-icon-theme          # 图标主题
  inter-font                  # 界面正文字体
  noto-fonts-cjk              # 中文正文字体（当前系统缺失）
  gnome-shell-extension-appindicator  # 托盘图标
  gnome-browser-connector     # 从 extensions.gnome.org 一键安装扩展
)
AUR_PKGS=(
  adw-gtk-theme               # GTK3 应用的 Adwaita 风格主题（配合 libadwaita）
  bibata-cursor-theme         # Bibata 光标
  papirus-folders             # 切换 Papirus 文件夹配色
  extension-manager           # 图形化扩展管理（可选但强烈建议）
)
SHELL_THEME_PKGS=(gnome-shell-extensions)   # 提供 User Themes 扩展
AUR_SHELL_THEME_PKGS=(colloid-gtk-theme)    # Colloid 主题（含 Shell 主题）

# 扩展：uuid|来源说明
EGO_EXTENSIONS=(
  "blur-my-shell@aunetx|面板/概览/托盘毛玻璃模糊"
  "dash-to-dock@micxgx.gmail.com|底部浮动 Dock"
  "just-perfection-desktop@just-perfection|界面微调（动画/元素显隐）"
)
REPO_EXTENSIONS=(
  "ubuntu-appindicators@ubuntu.com|托盘图标（来自 pacman 包）"
)
SHELL_THEME_EXT="user-theme@gnome-shell-extensions.gcampax.github.com"

# ---------------------------------------------------------------------------
# 设置写入（带 schema/键存在性判断，避免旧版 GNOME 报错）
# ---------------------------------------------------------------------------
gset() {
  local schema=$1 key=$2 value=$3
  if ! gsettings get "$schema" "$key" >/dev/null 2>&1; then
    warn "跳过 $schema $key（当前 GNOME 无此键）"
    return 0
  fi
  run gsettings set "$schema" "$key" "$value"
}

gset_soft() {
  local schema=$1 key=$2 value=$3
  if ! gsettings get "$schema" "$key" >/dev/null 2>&1; then return 0; fi
  if [ "$DRY_RUN" = 1 ]; then printf '  %s[dry] gsettings set %s %s %s%s\n' "$c_d" "$schema" "$key" "$value" "$c_off"; return 0; fi
  gsettings set "$schema" "$key" "$value" 2>/dev/null || warn "未能写入 $schema $key"
}

backup_once() {
  mkdir -p "$STATE"
  if [ -f "$STATE/latest.dconf" ]; then
    info "已存在备份：$STATE/latest.dconf（保留首次备份，便于完全回滚）"
    return 0
  fi
  local ts; ts=$(date +%Y%m%d-%H%M%S)
  if [ "$DRY_RUN" = 1 ]; then printf '  %s[dry] dconf dump /org/gnome/ > %s/gnome-%s.dconf%s\n' "$c_d" "$STATE" "$ts" "$c_off"; return 0; fi
  dconf dump /org/gnome/ > "$STATE/gnome-$ts.dconf"
  cp -f "$STATE/gnome-$ts.dconf" "$STATE/latest.dconf"
  {
    echo "备份时间: $ts"
    echo "GNOME:    $(gnome-shell --version 2>/dev/null)"
    for k in org.gnome.desktop.interface:gtk-theme org.gnome.desktop.interface:icon-theme \
             org.gnome.desktop.interface:cursor-theme org.gnome.desktop.interface:font-name \
             org.gnome.desktop.interface:color-scheme org.gnome.desktop.background:picture-uri; do
      printf '%-52s %s\n' "$k" "$(gsettings get "${k%%:*}" "${k##*:}" 2>/dev/null)"
    done
  } > "$STATE/before.txt"
  ok "已备份原设置 → backup/gnome-$ts.dconf"
}

# ---------------------------------------------------------------------------
# base：安装软件包
# ---------------------------------------------------------------------------
cmd_base() {
  need_gnome
  is_arch || die "当前脚本的包管理部分只支持 Arch Linux"
  backup_once

  say "安装官方仓库软件包"
  run $SUDO pacman -S "${PAC_FLAGS[@]}" "${REPO_PKGS[@]}"

  say "安装 AUR 软件包（需要 yay）"
  if command -v yay >/dev/null; then
    run yay -S "${YAY_FLAGS[@]}" "${AUR_PKGS[@]}"
  else
    die "未找到 yay，请先安装 AUR 助手，或手动安装：${AUR_PKGS[*]}"
  fi

  if [ "$WITH_SHELL_THEME" = 1 ]; then
    say "安装桌面主题相关（User Themes + Colloid）"
    run $SUDO pacman -S "${PAC_FLAGS[@]}" "${SHELL_THEME_PKGS[@]}"
    if command -v yay >/dev/null; then
      run yay -S "${YAY_FLAGS[@]}" "${AUR_SHELL_THEME_PKGS[@]}"
    else
      warn "缺少 yay，跳过 Colloid 主题"
    fi
  fi

  say "刷新字体缓存"
  run fc-cache -f
  ok "base 完成"
}

# ---------------------------------------------------------------------------
# theme：壁纸 + 文件夹配色 + （可选）Shell 主题
# ---------------------------------------------------------------------------
cmd_theme() {
  need_gnome
  backup_once

  say "安装壁纸到 $WALLPAPER_DIR"
  run mkdir -p "$WALLPAPER_DIR"
  for f in "$ROOT"/wallpapers/*-2560x1440.png; do
    [ -f "$f" ] || continue
    run cp -f "$f" "$WALLPAPER_DIR/"
    ok "壁纸 $(basename "$f")"
  done

  if command -v papirus-folders >/dev/null || [ "$DRY_RUN" = 1 ]; then
    say "设置 Papirus 文件夹配色"
    # 按偏好挑一个当前 papirus-folders 支持的配色
    local color="" c
    if command -v papirus-folders >/dev/null; then
      for c in teal nordic cyan blue; do
        if papirus-folders -l 2>/dev/null | grep -qw "$c"; then color=$c; break; fi
      done
    fi
    [ -n "$color" ] || color="blue"
    info "文件夹配色: $color"
    run papirus-folders -C "$color" --theme Papirus-Dark
  else
    warn "未找到 papirus-folders，跳过文件夹配色（可稍后手动执行）"
  fi

  if [ "$WITH_SHELL_THEME" = 1 ]; then
    say "启用 Shell 主题（Colloid-Dark）"
    if gsettings get org.gnome.shell.extensions.user-theme name >/dev/null 2>&1; then
      info "User Themes 已随 gnome-shell-extensions 安装，跳过下载"
    else
      install_ego "$SHELL_THEME_EXT" "User Themes" || warn "User Themes 安装失败，跳过 Shell 主题"
    fi
    enable_ext "$SHELL_THEME_EXT"
    if ! have_theme "Colloid-Dark"; then
      warn "未找到 Colloid-Dark 主题，Shell 主题可能不生效（检查 AUR 构建是否成功）"
    fi
    gset org.gnome.shell.extensions.user-theme name "Colloid-Dark"
    gset org.gnome.desktop.interface gtk-theme "Colloid-Dark"
  fi
  ok "theme 完成"
}

# ---------------------------------------------------------------------------
# extensions：从 extensions.gnome.org 安装
# ---------------------------------------------------------------------------
install_ego() {
  local uuid=$1 name=${2:-$1} info_json url tmpzip
  [ "$DRY_RUN" = 1 ] && { printf '  %s[dry] 从 extensions.gnome.org 安装 %s%s\n' "$c_d" "$uuid" "$c_off"; return 0; }

  local ver; ver=$(gnome-shell --version 2>/dev/null | awk '{print $3}' | cut -d. -f1)
  info "查询 $name（GNOME $ver）..."
  info_json=$(curl -fsSL --max-time 20 \
      "https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${ver}" 2>/dev/null) || {
        warn "$name：无法访问 extensions.gnome.org"; return 1; }

  url=$(printf '%s' "$info_json" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get("download_url", ""))
except Exception:
    print("")
' 2>/dev/null)

  if [ -z "$url" ]; then
    warn "$name：扩展不提供当前 GNOME 版本（$ver）的下载"; return 1
  fi

  tmpzip=$(mktemp --suffix=.zip)
  if ! curl -fsSL --max-time 60 "https://extensions.gnome.org${url}" -o "$tmpzip"; then
    warn "$name：下载失败"; rm -f "$tmpzip"; return 1
  fi
  run mkdir -p "$EXT_DIR"
  gnome-extensions install --force "$tmpzip" >/dev/null 2>&1 || { warn "$name：安装失败"; rm -f "$tmpzip"; return 1; }
  rm -f "$tmpzip"
  ok "$name 已安装"
  mkdir -p "$STATE"
  grep -qxF "$uuid" "$STATE/installed-extensions.txt" 2>/dev/null || echo "$uuid" >> "$STATE/installed-extensions.txt"
}

enable_ext() {
  local uuid=$1
  if [ "$DRY_RUN" = 1 ]; then printf '  %s[dry] gnome-extensions enable %s%s\n' "$c_d" "$uuid" "$c_off"; return 0; fi
  gsettings set org.gnome.shell disable-user-extensions false 2>/dev/null || true
  if gnome-extensions enable "$uuid" 2>/dev/null; then
    ok "已启用 $uuid"
  else
    # Shell 尚未感知新安装的扩展：手动写入 enabled-extensions
    local cur; cur=$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null)
    if [ "$cur" = "@as []" ]; then
      gsettings set org.gnome.shell enabled-extensions "['$uuid']"
    elif ! printf '%s' "$cur" | grep -qF "$uuid"; then
      gsettings set org.gnome.shell enabled-extensions "$(printf '%s' "$cur" | sed "s/\]$/, '$uuid']/")"
    fi
    warn "$uuid 已写入启用列表，需要重新登录后生效"
  fi
}

cmd_extensions() {
  need_gnome
  [ "$WITH_EXT" = 1 ] || { info "已按 --no-extensions 跳过"; return 0; }

  say "安装 GNOME 扩展"
  for entry in "${EGO_EXTENSIONS[@]}"; do
    local uuid="${entry%%|*}" desc="${entry##*|}"
    info "$desc"
    if install_ego "$uuid"; then
      enable_ext "$uuid"
    fi
  done

  for entry in "${REPO_EXTENSIONS[@]}"; do
    local uuid="${entry%%|*}" desc="${entry##*|}"
    info "$desc"
    enable_ext "$uuid"
  done

  # 扩展偏好设置（键不存在时自动跳过）
  gset_soft org.gnome.shell.extensions.dash-to-dock dock-position "'BOTTOM'"
  gset_soft org.gnome.shell.extensions.dash-to-dock autohide true
  gset_soft org.gnome.shell.extensions.dash-to-dock intellihide true
  gset_soft org.gnome.shell.extensions.dash-to-dock icon-size 40
  gset_soft org.gnome.shell.extensions.dash-to-dock extend-height false
  gset_soft org.gnome.shell.extensions.blur-my-shell.panel blur true
  gset_soft org.gnome.shell.extensions.blur-my-shell.panel static-blur true
  gset_soft org.gnome.shell.extensions.blur-my-shell.panel sigma 30
  gset_soft org.gnome.shell.extensions.just-perfection animation 2
  ok "extensions 完成（部分扩展需重新登录后才显示）"
}

# ---------------------------------------------------------------------------
# apply：写入外观设置
# ---------------------------------------------------------------------------
cmd_apply() {
  need_gnome
  backup_once

  say "配色与主题"
  gset org.gnome.desktop.interface color-scheme "prefer-dark"
  gset org.gnome.desktop.interface accent-color "teal"
  if [ "$WITH_SHELL_THEME" = 1 ]; then
    [ "$DRY_RUN" = 1 ] || have_theme "Colloid-Dark" || warn "未找到 Colloid-Dark（先执行 ./install.sh all --with-shell-theme）"
    gset org.gnome.desktop.interface gtk-theme "Colloid-Dark"
  else
    gset org.gnome.desktop.interface gtk-theme "adw-gtk3-dark"
  fi
  [ "$DRY_RUN" = 1 ] || have_theme "adw-gtk3-dark" || warn "未找到 adw-gtk3-dark 主题（GTK3 应用会退回 Adwaita），请先执行 ./install.sh base"
  gset org.gnome.desktop.interface icon-theme "Papirus-Dark"
  [ "$DRY_RUN" = 1 ] || have_icon "Papirus-Dark" || warn "未找到 Papirus-Dark 图标主题，请先执行 ./install.sh base"
  gset org.gnome.desktop.interface cursor-theme "Bibata-Modern-Ice"
  [ "$DRY_RUN" = 1 ] || have_icon "Bibata-Modern-Ice" || warn "未找到 Bibata-Modern-Ice 光标，请先执行 ./install.sh base"
  gset org.gnome.desktop.interface cursor-size 24

  say "字体"
  gset org.gnome.desktop.interface font-name "Inter 11"
  gset org.gnome.desktop.interface document-font-name "Inter 11"
  gset org.gnome.desktop.interface monospace-font-name "Maple Mono CN 11"
  gset org.gnome.desktop.wm.preferences titlebar-font "Inter Bold 11"
  gset org.gnome.desktop.interface font-antialiasing "grayscale"
  gset org.gnome.desktop.interface font-hinting "slight"

  say "窗口与桌面"
  gset org.gnome.desktop.wm.preferences button-layout "appmenu:minimize,maximize,close"
  gset org.gnome.desktop.interface clock-format "24h"
  gset org.gnome.desktop.interface clock-show-seconds false
  gset org.gnome.desktop.interface enable-hot-corners false
  gset org.gnome.desktop.interface enable-animations true

  say "壁纸"
  local ink="$WALLPAPER_DIR/arctic-ink-2560x1440.png"
  local mist="$WALLPAPER_DIR/arctic-mist-2560x1440.png"
  gset org.gnome.desktop.background picture-uri "file://$ink"
  gset org.gnome.desktop.background picture-uri-dark "file://$ink"
  gset org.gnome.desktop.background picture-options "zoom"
  gset org.gnome.desktop.background primary-color "#0e1a24"
  gset org.gnome.desktop.background color-shading-type "solid"
  info "浅色版壁纸: $mist"

  ok "apply 完成 —— 若部分项目未即时生效，注销重新登录一次"
}

# ---------------------------------------------------------------------------
# rollback
# ---------------------------------------------------------------------------
cmd_rollback() {
  need_gnome
  local bk="$STATE/latest.dconf"
  [ -f "$bk" ] || die "没有找到备份（$bk）。未执行过安装，或备份被删除"

  say "停用并移除本方案安装的扩展"
  if [ -f "$STATE/installed-extensions.txt" ]; then
    while read -r uuid; do
      [ -n "$uuid" ] || continue
      run gnome-extensions disable "$uuid" 2>/dev/null || true
      run gnome-extensions uninstall "$uuid" 2>/dev/null || warn "无法卸载 $uuid（可手动删除 $EXT_DIR/$uuid）"
    done < "$STATE/installed-extensions.txt"
  fi

  say "恢复安装前的 GNOME 设置"
  runsh "dconf load /org/gnome/ < '$bk'"
  ok "设置已恢复"

  say "剩余需要手动处理的内容"
  cat <<EOF
  • 软件包（如需彻底移除）：
      ${SUDO:+$SUDO }pacman -Rns ${REPO_PKGS[*]}
      yay -Rns ${AUR_PKGS[*]}
  • 壁纸文件：$WALLPAPER_DIR/arctic-*.png
  • 备份文件保留在：$STATE/
EOF
}

cmd_status() {
  need_gnome
  say "当前外观设置"
  gsettings list-recursively org.gnome.desktop.interface 2>/dev/null \
    | grep -E '^(org.gnome.desktop.interface) (gtk-theme|icon-theme|cursor-theme|cursor-size|font-name|document-font-name|monospace-font-name|color-scheme|accent-color) ' \
    | sed 's/^/  /'
  gsettings list-recursively org.gnome.desktop.wm.preferences 2>/dev/null \
    | grep -E ' (button-layout|titlebar-font) ' | sed 's/^/  /'
  printf '  Shell 主题: %s\n' \
    "$(gsettings get org.gnome.shell.extensions.user-theme name 2>/dev/null || echo '未安装 User Themes')"
  printf '  壁纸:       %s\n' "$(gsettings get org.gnome.desktop.background picture-uri 2>/dev/null)"
  say "已启用扩展"
  gnome-extensions list --enabled 2>/dev/null | sed 's/^/  • /' || echo "  （无）"
}

# ---------------------------------------------------------------------------
case "$CMD" in
  doctor)     exec "$ROOT/scripts/doctor.sh" ;;
  base)       cmd_base ;;
  theme)      cmd_theme ;;
  extensions) cmd_extensions ;;
  apply)      cmd_apply ;;
  all)        cmd_base; cmd_theme; [ "$WITH_EXT" = 1 ] && cmd_extensions; cmd_apply ;;
  rollback)   cmd_rollback ;;
  status)     cmd_status ;;
  *)          die "未知子命令: $CMD" ;;
esac
