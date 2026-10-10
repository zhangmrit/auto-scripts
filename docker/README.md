# auto_docker.sh

一键安装 Docker CE 及 Docker Compose，支持镜像加速配置。

## 功能

- 自动安装 **Docker CE** 和官方 **Docker Compose CLI 插件**
- Compose 默认跟随 GitHub 最新稳定版，也可锁定指定版本
- `docker compose` 与兼容命令 `docker-compose` 使用同一份程序
- Compose 下载后校验官方 SHA256，再写入插件目录
- 检测已有 Docker，默认保留，也可显式重新运行安装脚本
- 合并而非覆盖现有 `/etc/docker/daemon.json`，修改前自动备份
- 可选配置 HTTPS 镜像地址与容器日志限制
- 可选将当前用户加入 `docker` 组，免 `sudo` 运行
- 支持环境变量驱动的无人值守执行

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
> sh -c "$(curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/zhangmrit/auto-scripts/master/docker/auto_docker.sh)"
> sh -c "$(curl -fsSL https://gitee.com/zhangmrit/auto-scripts/raw/master/docker/auto_docker.sh)"
> ```

**或手动下载后执行：**

```bash
# 下载脚本
wget https://raw.githubusercontent.com/zhangmrit/auto-scripts/master/docker/auto_docker.sh

# 添加执行权限并运行
chmod +x auto_docker.sh && sh auto_docker.sh
```

### 无人值守示例

```bash
# 使用官方源安装 Docker，安装最新 Compose，并安全合并 daemon 配置
AUTO_SCRIPTS_NONINTERACTIVE=1 \
DOCKER_SOURCE=official \
DOCKER_CONFIGURE_DAEMON=1 \
COMPOSE_VERSION=latest \
sh auto_docker.sh

# 保留现有 Docker，只把 Compose 固定到指定版本，并通过国内代理下载
AUTO_SCRIPTS_NONINTERACTIVE=1 \
DOCKER_SOURCE=skip \
COMPOSE_VERSION=v5.6.0 \
COMPOSE_DOWNLOAD_SOURCE=gh-proxy \
sh auto_docker.sh
```

### 纯卸载

只卸载 Docker 软件包、Compose 插件和兼容命令，不删除镜像、容器、卷或 Docker 数据目录：

```bash
AUTO_SCRIPTS_NONINTERACTIVE=1 \
DOCKER_UNINSTALL=1 \
sh auto_docker.sh
```

也可以使用参数形式：

```bash
sh auto_docker.sh --uninstall
```

| 环境变量 | 可选值 | 默认行为 |
| --- | --- | --- |
| `DOCKER_SOURCE` | `official` / `aliyun` / `tsinghua` / `skip` | 交互选择；无可用终端时必须设置 |
| `DOCKER_REINSTALL` | `0` / `1` | 已安装时保留 |
| `DOCKER_CONFIGURE_DAEMON` | `0` / `1` | 交互询问；非交互时不修改 |
| `DOCKER_REGISTRY_MIRROR` | HTTPS URL | `https://docker.m.daocloud.io` |
| `COMPOSE_VERSION` | `latest` / `vN.N.N` | `latest` |
| `COMPOSE_DOWNLOAD_SOURCE` | `official` / `gh-proxy` | `official` |
| `COMPOSE_UPDATE` | `auto` / `0` / `1` | `auto` |
| `DOCKER_UNINSTALL` | `0` / `1` | `0` |

## 执行流程

```
1. 检测平台、Docker 与 Compose 状态
2. 按选择保留或安装 Docker 引擎
3. 启动 Docker，并按需添加当前用户到 `docker` 组
4. 可选备份并合并 daemon 镜像及日志配置
5. 解析 Compose `latest` 或指定版本
6. 下载二进制和 `.sha256`，校验后安装为 CLI 插件
7. 验证 `docker`、`docker compose` 和 `docker-compose`
```

卸载模式只处理软件包和 Compose 文件，默认保留 `/var/lib/docker`、`/var/lib/containerd`、`/etc/docker` 及 Docker 数据。

## 注意事项

- 安装引擎、插件及系统配置时需要 root 或 `sudo` 权限
- 将用户加入 `docker` 组相当于授予接近 root 的系统权限，请仅对可信用户操作
- 将用户加入 `docker` 组后需**重新登录**或执行 `newgrp docker` 才能免 sudo
- 脚本不会自动执行 `newgrp`，避免创建额外 Shell 或阻塞自动任务
- 已有 `daemon.json` 但系统缺少 `jq` 时，脚本会跳过合并，绝不会直接覆盖
- 公共镜像的可用性可能变化，可通过 `DOCKER_REGISTRY_MIRROR` 自定义
