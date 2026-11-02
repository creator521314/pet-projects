#!/usr/bin/env bash
# 把中文输入从 ibus-libpinyin 切到 ibus-rime
# 保留 IBus 框架，不改任何 IM 环境变量，适合 GNOME Wayland。
#
#   bash switch-ime-rime.sh          # 只装朙月拼音（标准全拼）
#   bash switch-ime-rime.sh --dict   # 额外装中文维基词库（候选更准，约 30 MB）
#   bash switch-ime-rime.sh --dry    # 只看会做什么

set -euo pipefail

DRY=0
WITH_DICT=0
for a in "$@"; do
    case "$a" in
        --dry)  DRY=1 ;;
        --dict) WITH_DICT=1 ;;
    esac
done

PKGS=(ibus-rime librime-data)
[ "$WITH_DICT" = 1 ] && PKGS+=(rime-pinyin-zhwiki)

run() {
    if [ "$DRY" = 1 ]; then printf '  [dry] %s\n' "$*"; else "$@"; fi
}

[ "$EUID" -eq 0 ] && { echo "不要用 root 运行（需要你的会话 dconf）" >&2; exit 1; }

echo "==> 1. 安装 ibus-rime + 朙月拼音"
if [ "$DRY" = 1 ]; then
    echo "  [dry] sudo pacman -S --needed ${PKGS[*]}"
else
    sudo pacman -S --needed "${PKGS[@]}"
fi

echo "==> 2. 备份旧的 libpinyin 用户库"
if [ -d "$HOME/.cache/ibus/libpinyin" ]; then
    bak="$HOME/.cache/ibus/libpinyin.bak.$(date +%s)"
    run mv "$HOME/.cache/ibus/libpinyin" "$bak"
    echo "  已备份到 $bak"
else
    echo "  没有旧库，跳过"
fi

echo "==> 3. 注册 GNOME 输入源 ('ibus', 'rime')"
cur=$(gsettings get org.gnome.desktop.input-sources sources)
echo "  当前: $cur"
if [[ "$cur" == *"'rime'"* ]]; then
    echo "  已存在，跳过"
else
    new="${cur%]*}, ('ibus', 'rime')]"
    if [ "$DRY" = 1 ]; then
        echo "  [dry] 将改为: $new"
    else
        gsettings set org.gnome.desktop.input-sources sources "$new"
        echo "  已改为: $(gsettings get org.gnome.desktop.input-sources sources)"
    fi
fi

echo "==> 3.5 只保留朙月拼音方案（隐藏注音/仓颉/地球拼音）"
RIME_DIR="$HOME/.config/ibus/rime"
rc="$RIME_DIR/default.custom.yaml"
if [ -f "$rc" ]; then
    echo "  已存在 $rc，跳过（如需精简方案列表请手动编辑）"
else
    run mkdir -p "$RIME_DIR"
    if [ "$DRY" = 1 ]; then
        echo "  [dry] 写 $rc"
    else
        cat > "$rc" <<'YAML'
patch:
  schema_list:
    - schema: luna_pinyin
  menu/page_size: 7
YAML
        echo "  已写入（方案列表只剩朙月拼音，候选 7 个/页）"
    fi
fi

echo "==> 4. 重启 IBus"
if [ "$DRY" = 1 ]; then
    echo "  [dry] ibus restart"
else
    ibus restart 2>/dev/null || echo "  ibus restart 失败，可注销重登"
fi

cat <<'EOF'

完成。接下来手动两步：

  1. Super+Space 切到「中文 (Rime)」
     首次会弹出方案选择 → 选「朙月拼音」(Luna Pinyin)

  2. 如果没有弹窗：右键顶栏的 Rime 图标 → 「部署」(Deploy)
     部署约需 10 秒，之后即可输入

验证词频是否生效：
  ls -l ~/.config/ibus/rime/*.userdb/     # 每上屏一次，userdb 就会增长
  关闭会话再重开，输入同样的词，首选应当保留

回退到智能拼音：
  GNOME 设置 → 键盘 → 输入源 → 删除 Rime，重新添加「中文 (智能拼音)」
  旧词库在 ~/.cache/ibus/libpinyin.bak.*
EOF
