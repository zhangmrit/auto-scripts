# auto_docker.sh

一键安装 Docker CE 及 Docker Compose，支持镜像加速配置。

## 功能

- 自动安装 **Docker CE** + **Docker Compose**（含 `docker compose` 插件）
- 支持从 Docker 官方源安装，确保版本最新
- 检测已有安装，支持**跳过或重装**，可选清理旧数据
- 可选配置**镜像加速**（阿里云 / 自定义地址 / 公共加速源）
- 可选将当前用户加入 `docker` 组，免 `sudo` 运行
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
sh -c "$(curl -fsSL https://raw.githubusercontent.com/zhangmrit/auto-scripts/master/docker/auto_docker.sh)"
```

> 国内服务器推荐使用 Gitee 源：
>
> ```bash
> sh -c "$(curl -fsSL https://gitee.com/zhangmrit/auto-scripts/raw/master/docker/auto_docker.sh)"
> ```

**或手动下载后执行：**

```bash
# 下载脚本
wget https://raw.githubusercontent.com/zhangmrit/auto-scripts/master/docker/auto_docker.sh

# 添加执行权限并运行
chmod +x auto_docker.sh && bash auto_docker.sh
```

## 执行流程

```
1. 检测 Docker 是否已安装
   ├── 已安装 → 询问是否卸载重装（可选清理数据目录）
   └── 未安装 → 添加 Docker 官方源 → 安装 Docker CE + Compose
2. 启动 Docker 并设置开机自启
3. 可选将当前用户加入 docker 组
4. 可选配置镜像加速（阿里云 / 自定义 / 公共源）
5. 验证安装，输出版本及服务状态
```

## 注意事项

- 脚本需要 `sudo` 权限
- 将用户加入 `docker` 组后需**重新登录**或执行 `newgrp docker` 才能免 sudo
- 国内服务器建议配置镜像加速以提升拉取速度
