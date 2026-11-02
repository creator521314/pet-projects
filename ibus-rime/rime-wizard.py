#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ibus-rime 配置向导 —— 零依赖（只用 Python 标准库）

覆盖常用配置：
  · 启用哪些输入方案（简体/繁体/语句流/全拼/注音/仓颉/笔画）
  · 每页候选数
  · 候选横排 / 竖排
  · 模糊音（zh-z/ch-c/sh-s、n-l、en-eng/in-ing、an-ang、f-h）
  · 候选翻页键
  · 用户词库开关
  · 一键部署

用法：
    python3 rime-wizard.py              # 交互式
    python3 rime-wizard.py --defaults   # 全部用默认值，不问
    python3 rime-wizard.py --dry-run    # 只打印将写入的内容
    python3 rime-wizard.py --no-deploy  # 写完不部署

设计原则：
  · 不依赖 PyYAML；YAML 由模板生成
  · 写文件前一律备份为 *.bak.<时间戳>
  · 只接管自己管理的键，其他自定义键尽量原样保留
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

RIME_DIR = Path.home() / ".config" / "ibus" / "rime"
SHARED_DIR = Path("/usr/share/rime-data")
BUILD_DIR = RIME_DIR / "build"

# 方案 id -> 说明
SCHEMAS = [
    ("luna_pinyin_simp", "朙月拼音·简化字（简体，推荐）"),
    ("luna_pinyin", "朙月拼音（繁体）"),
    ("luna_pinyin_fluency", "朙月拼音·语句流"),
    ("luna_quanpin", "全拼（不做简拼）"),
    ("terra_pinyin", "地球拼音（带声调）"),
    ("bopomofo", "注音（繁体）"),
    ("cangjie5", "仓颉五代"),
    ("stroke", "五笔画"),
]

# 模糊音分组：名称 -> 代数规则
FUZZY = [
    ("zh-z / ch-c / sh-s", ["derive/^([zcs])h/$1/", "derive/^([zcs])([^h])/$1h$2/"]),
    ("n-l",                ["derive/^n/l/", "derive/^l/n/"]),
    ("en-eng / in-ing",    ["derive/([ei])n$/$1ng/", "derive/([ei])ng$/$1n/"]),
    ("an-ang",             ["derive/([a])n$/$1ng/", "derive/([a])ng$/$1n/"]),
    ("f-h",                ["derive/^f/h/", "derive/^h/f/"]),
]

MANAGED_DEFAULT = {"schema_list", "menu/page_size", "style/horizontal",
                   "key_binder/bindings/+", "translator/enable_user_dict"}
MANAGED_SCHEMA = {"speller/algebra", "translator/enable_user_dict"}


# ---------------------------------------------------------------- 交互工具
def ask(prompt: str, default: str) -> str:
    try:
        raw = input(f"{prompt} [{default}]: ").strip()
    except EOFError:
        print()
        return default
    return raw or default


def ask_yes(prompt: str, default: bool = True) -> bool:
    d = "Y/n" if default else "y/N"
    try:
        raw = input(f"{prompt} [{d}]: ").strip().lower()
    except EOFError:
        print()
        return default
    if not raw:
        return default
    return raw in ("y", "yes", "是", "1")


def ask_int(prompt: str, default: int, lo: int, hi: int) -> int:
    while True:
        raw = ask(prompt, str(default))
        if raw.isdigit() and lo <= int(raw) <= hi:
            return int(raw)
        print(f"  请输入 {lo}-{hi} 之间的数字")


def ask_multi(title: str, items: list[tuple[str, str]], defaults: set[str]) -> list[str]:
    print(f"\n{title}")
    for i, (key, desc) in enumerate(items, 1):
        mark = "*" if key in defaults else " "
        print(f"  [{mark}] {i}. {desc}  ({key})")
    print("  输入编号（空格或逗号分隔），回车使用 * 标记的项")
    try:
        raw = input("  选择: ").strip()
    except EOFError:
        print()
        raw = ""
    if not raw:
        return [k for k, _ in items if k in defaults]
    picked: list[str] = []
    for tok in raw.replace(",", " ").split():
        if tok.isdigit() and 1 <= int(tok) <= len(items):
            key = items[int(tok) - 1][0]
            if key not in picked:
                picked.append(key)
    return picked


# ---------------------------------------------------------------- YAML 辅助
def read_blocks(path: Path, managed: set[str]) -> list[str]:
    """保留用户自己写的、不在 managed 里的 patch 子块（原样返回行）。"""
    if not path.exists():
        return []
    lines = path.read_text(encoding="utf-8").splitlines()
    out: list[str] = []
    current_key = None
    keep = False
    in_patch = False
    for line in lines:
        stripped = line.strip()
        if not in_patch:
            if stripped == "patch:":
                in_patch = True
            continue
        # 顶层键：恰好两个空格缩进
        if line.startswith("  ") and not line.startswith("   ") and stripped and not stripped.startswith("#"):
            current_key = stripped.split(":", 1)[0].strip('"').strip("'")
            keep = current_key not in managed
        if keep:
            out.append(line)
    # 去掉尾部空行
    while out and not out[-1].strip():
        out.pop()
    return out


def write_file(path: Path, content: str, dry: bool) -> None:
    if dry:
        rel = path.relative_to(Path.home())
        print(f"\n--- 将写入 ~/{rel} ---")
        print(content.rstrip())
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        bak = path.with_suffix(path.suffix + f".bak.{int(time.time())}")
        shutil.copy2(path, bak)
        print(f"  已备份 -> {bak.name}")
    path.write_text(content, encoding="utf-8")
    print(f"  已写入 ~/{path.relative_to(Path.home())}")


# ---------------------------------------------------------------- 生成配置
def build_default_yaml(schemas: list[str], page_size: int, horizontal: bool,
                       comma_paging: bool, extra: list[str]) -> str:
    lines = [
        "# 由 rime-wizard.py 生成，改完记得部署（rime_deployer / 右键「部署」）",
        f"# 生成时间: {time.strftime('%Y-%m-%d %H:%M:%S')}",
        "patch:",
        "  schema_list:",
    ]
    for s in schemas:
        lines.append(f"    - schema: {s}")
    lines.append(f"  menu/page_size: {page_size}")
    lines.append(f"  style/horizontal: {'true' if horizontal else 'false'}")
    if comma_paging:
        lines += [
            '  "key_binder/bindings/+":',
            "    - { when: paging, accept: comma, send: Page_Up }",
            "    - { when: has_menu, accept: period, send: Page_Down }",
        ]
    if extra:
        lines.append("")
        lines += extra
    return "\n".join(lines) + "\n"


def build_schema_yaml(schema_id: str, fuzzy_keys: list[str], user_dict: bool,
                      extra: list[str]) -> str | None:
    rules: list[str] = []
    for key, group_rules in FUZZY:
        if key in fuzzy_keys:
            rules.extend(group_rules)
    if not rules and not user_dict:
        return None

    lines = [
        f"# {schema_id}.custom.yaml —— 由 rime-wizard.py 生成",
        f"# 生成时间: {time.strftime('%Y-%m-%d %H:%M:%S')}",
        "patch:",
    ]
    if rules:
        # 用 /+ 追加，保留方案自带的预设（简拼、拼写纠错、按键纠错）
        lines.append('  "speller/algebra/+":')
        for r in rules:
            lines.append(f"    - {r}")
    if user_dict:
        lines.append('  "translator/enable_user_dict": true')
    if extra:
        lines.append("")
        lines += extra
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------- 部署
def deploy(dry: bool) -> bool:
    cmd = ["rime_deployer", "--build", str(RIME_DIR), str(SHARED_DIR), str(BUILD_DIR)]
    print("\n" + " ".join(cmd))
    if dry:
        print("  [dry-run] 跳过实际执行")
        return True
    if not shutil.which("rime_deployer"):
        print("  找不到 rime_deployer，改用 ibus restart")
        return subprocess.call(["ibus", "restart"]) == 0
    rc = subprocess.call(cmd)
    if rc == 0:
        print("  部署成功")
    else:
        print(f"  部署失败（退出码 {rc}），查看 ~/.config/ibus/rime/*.log")
    return rc == 0


# ---------------------------------------------------------------- 主流程
def main() -> int:
    ap = argparse.ArgumentParser(description="ibus-rime 配置向导")
    ap.add_argument("--defaults", action="store_true", help="全部使用默认值")
    ap.add_argument("--dry-run", action="store_true", help="只打印，不写文件")
    ap.add_argument("--no-deploy", action="store_true", help="写完后不部署")
    args = ap.parse_args()

    print("=" * 56)
    print(" ibus-rime 配置向导")
    print("=" * 56)

    # ---- 环境检查
    if not RIME_DIR.exists():
        print(f"\n! {RIME_DIR} 不存在")
        print("  先用过一次 Rime 并部署，或运行: ibus restart")
        return 1
    if not SHARED_DIR.exists():
        print(f"\n! {SHARED_DIR} 不存在，没装 librime-data？")
        return 1
    print(f"\n用户目录: {RIME_DIR}")
    print(f"共享方案: {SHARED_DIR}")

    available = {p.name.replace(".schema.yaml", "")
                 for p in SHARED_DIR.glob("*.schema.yaml")}
    usable = [(sid, name) for sid, name in SCHEMAS if sid in available]
    if not usable:
        print("! 共享目录里没找到可用方案")
        return 1

    # ---- 交互
    if args.defaults:
        schemas = ["luna_pinyin_simp"]
        page_size = 7
        horizontal = True
        comma_paging = False
        fuzzy: list[str] = []
        user_dict = True
    else:
        print("\n提示：方括号里是默认值，直接回车即采用\n")

        schemas = ask_multi("启用哪些输入方案？", usable, {"luna_pinyin_simp"})
        if not schemas:
            schemas = ["luna_pinyin_simp"]

        page_size = ask_int("\n每页候选词个数", 7, 3, 10)
        horizontal = ask_yes("候选框横排显示", True)

        fuzzy = ask_multi(
            "需要哪些模糊音？（不选则保持标准拼音）",
            [(k, k) for k, _ in FUZZY],
            set(),
        )
        comma_paging = ask_yes("用「, .」翻页（默认用「- =」）", False)
        user_dict = ask_yes("启用用户词库（记录词频，强烈建议开）", True)

    # ---- 生成
    default_extra = read_blocks(RIME_DIR / "default.custom.yaml", MANAGED_DEFAULT)
    default_yaml = build_default_yaml(schemas, page_size, horizontal, comma_paging, default_extra)

    write_file(RIME_DIR / "default.custom.yaml", default_yaml, args.dry_run)

    written_schema_files = []
    for sid in schemas:
        if sid not in ("luna_pinyin", "luna_pinyin_simp", "luna_pinyin_fluency",
                       "luna_quanpin", "terra_pinyin"):
            continue  # 形码/注音不做代数补丁
        path = RIME_DIR / f"{sid}.custom.yaml"
        extra = read_blocks(path, MANAGED_SCHEMA)
        content = build_schema_yaml(sid, fuzzy, user_dict, extra)
        if content:
            write_file(path, content, args.dry_run)
            written_schema_files.append(path.name)

    # ---- 汇总
    print("\n" + "-" * 56)
    print("配置摘要")
    print(f"  方案      : {', '.join(schemas)}")
    print(f"  候选数    : {page_size}")
    print(f"  候选方向  : {'横排' if horizontal else '竖排'}")
    print(f"  模糊音    : {', '.join(fuzzy) if fuzzy else '无（标准拼音）'}")
    print(f"  翻页键    : {', .' if comma_paging else '- ='}")
    print(f"  用户词库  : {'开' if user_dict else '关'}")
    if written_schema_files:
        print(f"  方案补丁  : {', '.join(written_schema_files)}")

    if args.no_deploy:
        print("\n跳过部署。手动部署：")
        print("  rime_deployer --build ~/.config/ibus/rime /usr/share/rime-data ~/.config/ibus/rime/build")
        return 0

    if not args.dry_run and not ask_yes("\n现在部署吗", True):
        print("已跳过部署。改完随时可重新运行本脚本。")
        return 0

    ok = deploy(args.dry_run)
    if ok and not args.dry_run:
        print("\n下一步：Super+Space 切到「中文 (Rime)」，首次会让你选方案。")
        print("词频写在 ~/.config/ibus/rime/<方案>.userdb/，每上屏一次即更新。")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
