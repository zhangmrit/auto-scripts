# auto_zsh.sh

自动化完成 Zsh 环境的全套配置，无需手动逐步操作。

## 功能

- 从源码编译安装 **Zsh 5.9**，不依赖系统包管理器版本
- 自动安装 **Oh My Zsh**（支持 GitHub / Gitee 双源切换）
- 自动克隆并启用插件：
  - `zsh-syntax-highlighting` — 命令语法高亮
  - `zsh-autosuggestions` — 历史命令自动补全建议
  - `autojump` — 目录快速跳转
- 检测已有安装，支持**跳过或重装**，不会盲目覆盖
- 交互超时自动采用默认值，适合无人值守场景

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
sh -c "$(curl -fsSL https://raw.githubusercontent.com/zhangmrit/auto-scripts/main/zsh/auto_zsh.sh)"
```

> 国内服务器推荐使用 Gitee 源：
>
> ```bash
> sh -c "$(curl -fsSL https://gitee.com/zhangmrit/auto-scripts/raw/main/zsh/auto_zsh.sh)"
> ```

**或手动下载后执行：**

```bash
# 下载脚本
wget https://raw.githubusercontent.com/zhangmrit/auto-scripts/main/zsh/auto_zsh.sh

# 添加执行权限并运行
chmod +x auto_zsh.sh && bash auto_zsh.sh
```

## 执行流程

```
1. 检测 Zsh 是否已安装
   ├── 已安装 → 询问是否卸载重装
   └── 未安装 → 安装编译依赖 → 下载源码 → 编译安装 → 注册 Shell
2. 检测 Oh My Zsh 是否已存在
   ├── 已存在 → 询问是否重置（自动备份 .zshrc）
   └── 未安装 → 选择 GitHub / Gitee 源 → 安装
3. 克隆插件并写入 .zshrc 配置
4. 完成，提示执行 exec $SHELL -l 激活环境
```

## 注意事项

- 脚本需要 `sudo` 权限（编译安装、修改 `/etc/shells`、切换默认 Shell）
- 安装完成后需执行 `exec /usr/local/bin/zsh -l` 或重新登录以激活 Zsh
- 若服务器在国内且访问 GitHub 受限，安装 Oh My Zsh 时选择 **Gitee 源（输入 2）**
