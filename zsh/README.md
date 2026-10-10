# auto_zsh.sh

自动化完成 Zsh 环境的全套配置，无需手动逐步操作。

## 功能

- 从源码编译安装 **Zsh 5.9.2**，不依赖系统包管理器版本
- 自动安装 **Oh My Zsh**（支持 GitHub / Gitee 双源切换）
- 自动克隆并启用插件：
  - `zsh-syntax-highlighting` — 命令语法高亮
  - `zsh-autosuggestions` — 历史命令自动补全建议
  - `autojump` — 目录快速跳转
- 对 Zsh 源码归档进行固定 SHA256 校验
- 在临时目录下载、解压和编译，不污染当前工作目录
- 检测已有安装；首次安装会先交互确认，已有安装默认保留，也可显式重新编译
- Oh My Zsh 支持跳过（保留现状）、更新或备份后重装；跳过时不会询问下载源，也不会运行 Git 同步
- 每个下载地址只尝试一次；自动源失败后立即切换到下一个候选源
- 插件已存在时执行快进更新，不重复克隆
- 合并 `.zshrc` 插件列表，保留用户已有插件并避免重复
- 默认交互执行；`--yes` / `--non-interactive` 按 auto 规则无人值守执行，官方源优先、加速源后备，已安装组件默认跳过不覆盖

## 支持系统

| 系统                      | 包管理器      |
| ------------------------- | ------------- |
| Ubuntu / Debian           | `apt`         |
| Fedora                    | `dnf`         |
| CentOS / RHEL / AlmaLinux | `yum` / `dnf` |

## 使用方法

**一行命令快速执行：**

```bash
# GitHub 源
sh -c "$(curl -fsSL https://raw.githubusercontent.com/zhangmrit/auto-scripts/master/zsh/auto_zsh.sh)"
```

> 国内服务器推荐使用 Gitee 源：
>
> ```bash
> sh -c "$(curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/zhangmrit/auto-scripts/master/zsh/auto_zsh.sh)"
> sh -c "$(curl -fsSL https://gitee.com/zhangmrit/auto-scripts/raw/master/zsh/auto_zsh.sh)"
> ```

脚本在可用终端时会通过 `/dev/tty` 进行交互确认；只有设置 `AUTO_SCRIPTS_NONINTERACTIVE=1` 或确实没有终端时才使用默认值自动执行。

**或手动下载后执行：**

```bash
# 下载脚本
wget https://raw.githubusercontent.com/zhangmrit/auto-scripts/master/zsh/auto_zsh.sh

# 添加执行权限并运行
chmod +x auto_zsh.sh && sh auto_zsh.sh
```

### 无人值守示例

```bash
# 一键安装/配置：未安装时安装 Zsh 和 Oh My Zsh，已存在组件默认跳过
sh auto_zsh.sh --yes

# 无人值守但保留各项保守默认值
sh auto_zsh.sh --non-interactive

# 重新编译 Zsh、更新 Oh My Zsh，但不修改默认 Shell
sh auto_zsh.sh --reinstall --no-change-default-shell \
  --omz-action update --omz-source auto
```

不带参数时默认交互。使用 `sh auto_zsh.sh --help` 查看全部参数；原有环境变量仍兼容。

### 纯卸载

卸载脚本安装的 Zsh、运行时目录和 `/etc/shells` 注册时，会交互询问是否清理 `.zshrc`、Oh My Zsh 及插件，默认选择 `n` 保留：

```bash
AUTO_SCRIPTS_NONINTERACTIVE=1 \
ZSH_UNINSTALL=1 \
sh auto_zsh.sh
```

如需同时删除 Oh My Zsh 目录，可显式设置：

```bash
ZSH_UNINSTALL=1 ZSH_REMOVE_OMZ=1 sh auto_zsh.sh
```

也可以使用参数形式：

```bash
sh auto_zsh.sh --uninstall
```

仅在确认后清理 `.zshrc` 和 Oh My Zsh：

```bash
sh auto_zsh.sh --uninstall --cleanup
```

| 环境变量 | 可选值 | 默认行为 |
| --- | --- | --- |
| `ZSH_INSTALL_PATH` | 绝对路径 | `/usr/local/bin/zsh` |
| `ZSH_FALLBACK_SHELLS` | 空格分隔的 Shell 路径 | `/bin/bash /bin/sh /usr/bin/bash /usr/bin/sh ...` |
| `ZSH_REINSTALL` | `0` / `1` | 已安装时保留 |
| `CHANGE_DEFAULT_SHELL` | `0` / `1` | 交互询问；非交互时不修改 |
| `OMZ_ACTION` | `keep` / `update` / `reinstall` | `keep`：跳过并保留现状 |
| `OMZ_SOURCE` | `auto` / `github` / `gh-proxy` / `gitee` | `auto`（依次尝试 GitHub、gh-proxy、Gitee） |
| `SYNC_ZSH_PLUGINS` | `0` / `1` | `1` |
| `ZSH_UNINSTALL` | `0` / `1` | `0` |
| `ZSH_REMOVE_OMZ` | `0` / `1` | `0`（兼容参数；设为 `1` 仅删除 Oh My Zsh，保留 `.zshrc`） |
| `ZSH_CLEANUP` | `0` / `1` | 交互询问；默认 `0`，清理 `.zshrc` 与 Oh My Zsh |

## 执行流程

```
1. 检测 Zsh 是否已安装
   ├── 已安装 → 保留或重新编译
   └── 未安装 → 交互确认 → 安装依赖 → 下载并校验源码 → 临时目录编译 → 注册 Shell
2. 检测 Oh My Zsh 是否已存在
   ├── 已存在 → 跳过、更新或备份后重装
   └── 未安装 → 自动尝试 GitHub / gh-proxy / Gitee → 安装
3. 安装或更新插件，合并 `.zshrc` 配置
4. 验证 Zsh，提示启动新的登录 Shell
```

## 注意事项

- 编译安装、修改 `/etc/shells` 或切换默认 Shell 时需要 root 或 `sudo` 权限
- 卸载前会检查当前用户的登录 Shell、当前会话以及 `/etc/shells` 中是否存在可执行的 Bash/Sh 备用 Shell；如果当前登录 Shell 仍是 Zsh，或没有备用 Shell，脚本会拒绝卸载，避免 SSH 断连
- Zsh 固定使用已校验的 5.9.2 源码归档；SourceForge 没有适合此流程的稳定 `latest` 归档地址
- 当前支持 Linux；脚本会拒绝在未验证的平台上继续安装
- `.zshrc` 每次自动修改前都会生成带时间戳的备份
- 安装完成后需执行 `exec /usr/local/bin/zsh -l` 或重新登录以激活 Zsh
- 自动模式会在当前源连接失败时切换备用源；也可通过 `OMZ_SOURCE` 固定指定一个源
