# ibus-rime

Arch Linux + GNOME 51（Wayland）下，把中文输入从 `ibus-libpinyin` 换成 `ibus-rime` 的配置记录与工具。

- 框架仍是 **IBus**，输入源 `[('xkb','us'), ('ibus','rime')]`
- 方案：朙月拼音·简化字（`luna_pinyin_simp`）
- 7 个候选/页，横排，开常用模糊音，用户词库开启

## 为什么换掉 libpinyin

选过的字下次还是排在后面，甚至一分钟内重复输入也不调整。查 `~/.cache/ibus/libpinyin/`：

- `user.bin` 只有文件头，`user_bigram.db` 只有签名、零词条
- 所有文件时间戳集中在几分钟内，是反复重建而不是累积

根因是 libpinyin 的用户数据**延迟落盘**：内存里训练，进程优雅退出时才写文件。GNOME Wayland 下
IBus 引擎跟着 gnome-shell 生死，注销/重启常被 `SIGKILL`，保存函数没机会执行；一旦写出的库版本
对不上，下次启动会被判定无效并丢弃重建，形成循环。

所以不是配置问题，是持久化机制不适配 Wayland 的会话生命周期。

## 为什么留在 IBus

- `ibus` 是 gnome-shell 的硬依赖，`pacman -R ibus` 会连带删掉整个 GNOME——只能换引擎，不能拆框架。
- `fcitx5` 也能配 Rime，但 GNOME 不支持 Wayland 的 *input-method* 协议，候选框定位要靠 kimpanel
  扩展；还要改 `GTK_IM_MODULE` / `QT_IM_MODULE` / `XMODIFIERS`。

留在 IBus 里换引擎，是改动最小、故障点最少的路径。

## 快速开始

```bash
# 1. 装 Rime（meta 含朙月拼音、注音、仓颉、笔画、地球拼音）
sudo pacman -S --needed ibus-rime librime-data

# 2. 注册输入源、备份旧词库、重启 IBus
bash switch-ime-rime.sh
#    需要中文维基词库（约 30 MB）：bash switch-ime-rime.sh --dict

# 3. 按需配置：方案 / 候选数 / 横排 / 模糊音 / 翻页键 / 词库
python3 rime-wizard.py

# 4. 没有自动部署时手动重启
ibus restart
```

首次使用：`Super+Space` 切到「中文 (Rime)」→ 选 **朙月拼音** → 右键托盘 Rime 图标 →
**部署**（约 10 秒）。

脚本和向导都以普通用户运行（需要 sudo 的地方脚本自己调用），不要用 root。

## 文件

| 文件 | 说明 |
| --- | --- |
| [`switch-ime-rime.sh`](switch-ime-rime.sh) | 一键切换：装包、备份 libpinyin 旧词库、注册输入源、重启 IBus。`--dry` 只看动作，`--dict` 附带维基词库 |
| [`rime-wizard.py`](rime-wizard.py) | 零依赖配置向导：方案、候选数、横排、模糊音、翻页键、词库，写完自动部署。`--defaults` 全默认，`--dry-run` 只看生成内容，`--no-deploy` 不部署 |
| [`config/`](config/) | 当前在用的两份配置快照，可直接拷进 `~/.config/ibus/rime/` 后部署 |

## 配置

Rime 没有图形设置界面：`/usr/share/ibus/component/rime.xml` 里没有 `<setup>` 字段，所以 GNOME
「偏好设置」的齿轮点了没反应，这是设计如此。所有配置都在 YAML 里。

`~/.config/ibus/rime/default.custom.yaml`：

```yaml
patch:
  schema_list:
    - schema: luna_pinyin_simp     # 简体全拼
  menu/page_size: 7                # 每页候选数
  style/horizontal: true           # 横排候选
```

`luna_pinyin_simp.custom.yaml`（模糊音 + 用户词库）：

```yaml
patch:
  "speller/algebra/+":             # 关键是 /+ ，追加而非替换
    - derive/^([zcs])h/$1/         # zh/ch/sh → z/c/s
    - derive/^([zcs])([^h])/$1h$2/ # z/c/s → zh/ch/sh
    - derive/([ei])n$/$1ng/        # en/in → eng/ing
    - derive/([ei])ng$/$1n/        # eng/ing → en/in
  "translator/enable_user_dict": true
```

⚠️ 必须用 `/+` 追加。`luna_pinyin` 的 `algebra` 是 `__patch:` 地图而不是列表，直接写
`"speller/algebra": [...]` 会让 YAML 解析失败（`end of map not found`），替换式写法还会丢掉方案
自带的简拼、拼写纠错和按键纠错。

想直接用这套配置：

```bash
cp config/*.custom.yaml ~/.config/ibus/rime/
rime_deployer --build ~/.config/ibus/rime /usr/share/rime-data ~/.config/ibus/rime/build
```

## 部署

配置改完不会自动生效，三种方式任选：

```bash
# 1. 命令行（最快）
rime_deployer --build ~/.config/ibus/rime /usr/share/rime-data ~/.config/ibus/rime/build

# 2. 右键托盘 Rime 图标 → 部署
# 3. 重启 IBus
ibus restart
```

## 目录与概念

| 概念 | 含义 | 位置 |
| --- | --- | --- |
| 方案 schema | 一套输入规则，如朙月拼音、仓颉 | `/usr/share/rime-data/*.schema.yaml` |
| 部署 deploy | YAML 编译成二进制，Rime 只读产物 | `rime_deployer --build` |
| 用户词库 userdb | 选过的词与词频，LevelDB 格式 | `~/.config/ibus/rime/<dict>.userdb/` |
| 补丁 custom | 不改上游文件，只写差异覆盖 | `*.custom.yaml` |

```
~/.config/ibus/rime/
├── default.custom.yaml           # 全局：方案列表、候选数、横排
├── luna_pinyin_simp.custom.yaml  # 方案级：模糊音、词库开关
├── build/                        # 编译产物，不要手改
├── luna_pinyin.userdb/           # 用户词频
└── sync/                         # 多设备同步目录
```

> `luna_pinyin_simp` 与 `luna_pinyin` 共用 `luna_pinyin.userdb`：词典名相同，区别只在简繁开关。

## 验证

```bash
# 词频是否真的在记：上屏几个词后看 userdb 文件时间戳
ls -l ~/.config/ibus/rime/luna_pinyin.userdb/

# 部署内容是否生效
grep page_size ~/.config/ibus/rime/build/default.yaml
grep -c derive ~/.config/ibus/rime/build/luna_pinyin_simp.schema.yaml
```

## 排错

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 设置里的齿轮点了没反应 | 组件无 `<setup>` | 正常，改 YAML 后部署 |
| 候选全是繁体 | `luna_pinyin` 默认繁体 | 改用 `luna_pinyin_simp` |
| 部署报 `end of map not found` | algebra 结构写错 | 用 `"speller/algebra/+":` 追加 |
| 部署报 `yaml-cpp: error at line N` | YAML 缩进混用 | 只用空格，检查第 N 行 |
| 切不过去 | 引擎未注册 | `ibus list-engine \| grep -i rime` |
| 没有任何候选 | 没部署 | 托盘「部署」或跑 `rime_deployer` |
| 方案列表一堆用不上的 | `librime-data` 带全部方案 | `schema_list` 里只留需要的 |

## 回退

```bash
sudo pacman -S --needed ibus-libpinyin
gsettings set org.gnome.desktop.input-sources sources "[('xkb','us'),('ibus','libpinyin')]"
ibus restart
```

旧词库备份在 `~/.cache/ibus/libpinyin.bak.*`（跑过 `switch-ime-rime.sh` 才会生成）。回退只是回到
「词频不记忆」的状态，根因没有解决。

## 注意

- 不要提交 `~/.config/ibus/rime/` 下的 `build/`、`*.userdb/`、`sync/`、`installation.yaml`：
  都是本机生成物或个人数据。
- 脚本和向导在写文件前都会备份成 `*.bak.<时间戳>`。
- 仓库里的 `config/` 只是配置快照，不是运行时目录。
