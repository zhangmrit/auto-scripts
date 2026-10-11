# auto_docker.sh

一键安装 Docker CE 及 Docker Compose，支持镜像加速配置。

## 功能

- 自动安装 **Docker CE**；Docker 自带的 Compose 插件由 Docker 自己负责
- Docker 引擎与 Docker Compose 分为两个独立流程，仅按顺序先处理 Docker 引擎
- 先检测 Docker 是否已安装并询问是否安装/修复，确认后才选择 Docker 源
- Compose 默认跟随 GitHub 最新稳定版，也可锁定指定版本
- 只检测和管理独立的 `docker-compose` 命令；交互模式下即使已安装也会询问是否检查/更新
- Compose 下载后校验官方 SHA256，再写入独立命令目录
- 检测已有 Docker，默认保留，也可显式重新运行安装脚本
- 合并而非覆盖现有 `/etc/docker/daemon.json`，修改前自动备份
- 可选配置 HTTPS 镜像地址与容器日志限制
- 可选将当前用户加入 `docker` 组，免 `sudo` 运行
- 默认交互执行；`--yes` 按 auto 规则无人值守执行：Docker CE 默认腾讯云源，已安装组件默认跳过不覆盖

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
# 使用阿里云源一键安装 Docker；已安装 Docker 或 Compose 时默认跳过，不覆盖现有组件
sh auto_docker.sh --yes --source aliyun

# 保留现有 Docker，只更新 Compose v5.6.0，不修改 daemon 配置
sh auto_docker.sh --yes --source skip \
  --compose-version v5.6.0 --compose-source gh-proxy \
  --no-configure-daemon --compose-compat
```

不带参数时默认交互。使用 `sh auto_docker.sh --help` 查看全部参数；原有环境变量仍兼容。

Docker 引擎选择跳过后，脚本仍会继续独立检测和处理 Docker Compose；Compose 可以先安装，待 Docker 引擎之后再使用。

### 纯卸载

卸载 Docker 软件包和独立 `docker-compose` 命令时，会交互询问是否清理镜像、容器、卷及 Docker 数据目录，默认选择 `n` 保留：

```bash
AUTO_SCRIPTS_NONINTERACTIVE=1 \
DOCKER_UNINSTALL=1 \
sh auto_docker.sh
```

也可以使用参数形式：

```bash
sh auto_docker.sh --uninstall
```

仅在确认后清理 `/var/lib/docker`、`/var/lib/containerd` 和 `/etc/docker`：

```bash
sh auto_docker.sh --uninstall --cleanup
```

| 环境变量 | 可选值 | 默认行为 |
| --- | --- | --- |
| `DOCKER_SOURCE` | `official` / `aliyun` / `tencent` / `skip` | 交互选择（直接回车默认腾讯云）；auto 默认 `tencent` |
| `DOCKER_REINSTALL` | `0` / `1` | 已安装时保留 |
| `DOCKER_CONFIGURE_DAEMON` | `0` / `1` | 交互询问；非交互时不修改 |
| `DOCKER_REGISTRY_MIRRORS` | 逗号分隔的 HTTPS URL | `https://docker.1ms.run,https://docker.1panel.live,https://docker.m.daocloud.io,https://mirror.ccs.tencentyun.com` |
| `DOCKER_REGISTRY_MIRROR` | 单个 HTTPS URL（兼容旧配置） | 未设置时使用默认列表 |
| `COMPOSE_VERSION` | `latest` / `vN.N.N` | `latest` |
| `COMPOSE_DOWNLOAD_SOURCE` | `auto` / `official` / `gh-proxy` | `auto` |
| `COMPOSE_UPDATE` | `auto` / `0` / `1` | `auto` |
| `COMPOSE_COMPAT_INSTALL` | `auto` / `0` / `1` | 交互询问；非交互时仅在未安装时安装 |
| `DOCKER_CLEANUP` | `0` / `1` | 交互询问；默认 `0`，清理 Docker 数据与配置 |
| `DOCKER_UNINSTALL` | `0` / `1` | `0` |

## 执行流程

```
1. 检测平台、Docker 与 Compose 状态
2. 询问是否安装/修复 Docker；确认后再选择安装源
3. 启动 Docker，并按需添加当前用户到 `docker` 组
4. 可选备份并合并 daemon 镜像及日志配置
5. 显示独立 `docker-compose` 状态，询问是否安装/更新
6. 解析 Compose `latest` 或指定版本
7. 下载独立 Compose 二进制和 `.sha256`，校验后安装为 `docker-compose`
8. 分别验证 Docker（如存在）以及独立 `docker-compose`
```

卸载模式默认保留 `/var/lib/docker`、`/var/lib/containerd`、`/etc/docker` 及 Docker 数据；交互选择 `y` 或传入 `--cleanup`/`DOCKER_CLEANUP=1` 才会清理这些留存文件。

## 注意事项

- 安装引擎、插件及系统配置时需要 root 或 `sudo` 权限
- 将用户加入 `docker` 组相当于授予接近 root 的系统权限，请仅对可信用户操作
- 将用户加入 `docker` 组后需**重新登录**或执行 `newgrp docker` 才能免 sudo
- 脚本不会自动执行 `newgrp`，避免创建额外 Shell 或阻塞自动任务
- 已有 `daemon.json` 但系统缺少 `jq` 时，脚本会跳过合并，绝不会直接覆盖
- 公共镜像的可用性可能变化，可通过 `DOCKER_REGISTRY_MIRRORS` 自定义；`registry.dockermirror.com` 和 `dockerpull.org` 不在默认列表中
- 所有安装源都使用同一套 Docker 官方一键安装脚本；`aliyun` 传入官方 `--mirror Aliyun`，`tencent` 通过 `DOWNLOAD_URL` 使用腾讯云 Docker CE 软件源
- 一键脚本下载会依次尝试 `get.docker.com`、GitHub 原始地址和 `gh-proxy`，避免国内服务器无法直连官方域名时直接失败
- 脚本不下载、不覆盖 Docker 自带的 `docker compose` CLI 插件；只管理独立的 `docker-compose` 可执行文件，可用 `COMPOSE_COMPAT_INSTALL=1` 强制安装、`COMPOSE_COMPAT_INSTALL=0` 跳过
- 卸载时会先筛选实际已安装的软件包，不会因为历史包名（例如 `docker-scan-plugin`）不存在而使整组卸载失败；卸载后仍存在的命令会被明确提示为残留
- Compose 默认使用 `COMPOSE_DOWNLOAD_SOURCE=auto`，按官方 GitHub → `gh-proxy.org` 顺序尝试；设置为 `official` 使用同样的官方优先顺序，设置为 `gh-proxy` 才优先使用加速源。二进制和 `.sha256` 必须成对下载并校验通过。这只针对独立 `docker-compose`，不管理 Docker 自带的 `docker compose` 插件。
- 每个下载地址只尝试一次；官方地址失败后立即切换到加速地址，不会在单个地址上自动重试三次。小文件下载上限 120 秒、Compose 二进制上限 300 秒；若持续 30 秒速度低于 10KB/s 会视为停滞立即中止，随后切换下一候选源。
- Compose 默认通过 GitHub API 解析 `latest`（当前目标版本为 v5.6.0 时也可设置 `COMPOSE_VERSION=v5.6.0`）；若当前 shell 仍命中旧版本，请执行 `rehash`（zsh）或 `hash -r`（bash）
