#!/bin/sh

# =================================================================
# 脚本名称: auto_docker.sh
# 功能: 自动化安装 Docker 引擎、配置镜像加速、安装 Docker Compose
# 支持系统: Ubuntu/Debian / Fedora/CentOS/RHEL/AlmaLinux
# 兼容: POSIX sh (dash/bash/zsh/ksh)
# =================================================================

set -e

# 颜色定义 (仅在终端输出时启用颜色)
if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "$TERM" != "dumb" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    CYAN=''
    NC=''
fi

# 检测是否为交互环境
is_interactive() {
    [ -t 0 ] && [ -t 1 ]
}

# 交互函数 (POSIX 兼容)
ask_user() {
    ask_prompt=$1
    ask_default=$2
    if [ "${AUTO_SCRIPTS_NONINTERACTIVE:-0}" = "1" ] || ! is_interactive; then
        case "$ask_default" in [Yy]) return 0 ;; *) return 1 ;; esac
    fi
    while :; do
        printf '%b' "${YELLOW}${ask_prompt} (y/n, 默认 ${ask_default}): ${NC}"
        IFS= read -r ask_result || ask_result=$ask_default
        ask_result=${ask_result:-$ask_default}
        case "$ask_result" in
            [Yy]) return 0 ;;
            [Nn]) return 1 ;;
            *) printf '%b\n' "${YELLOW}请输入 y 或 n。${NC}" ;;
        esac
    done
}

info() {
    printf '%b\n' "${GREEN}$*${NC}"
}

warn() {
    printf '%b\n' "${YELLOW}$*${NC}" >&2
}

die() {
    printf '%b\n' "${RED}$*${NC}" >&2
    exit 1
}

# 将常见 CPU 名称映射为 Docker Compose 发布资产使用的名称。
normalize_arch() {
    case "$1" in
        x86_64 | amd64) printf '%s\n' "x86_64" ;;
        aarch64 | arm64) printf '%s\n' "aarch64" ;;
        armv7l | armv7) printf '%s\n' "armv7" ;;
        armv6l | armv6) printf '%s\n' "armv6" ;;
        ppc64le | riscv64 | s390x) printf '%s\n' "$1" ;;
        *) return 1 ;;
    esac
}

# 输出指定版本、下载源和平台对应的 Compose 二进制地址。
compose_asset_url() {
    compose_url_version=$1
    compose_url_source=$2
    compose_url_os=$3
    compose_url_arch=$4

    if [ "$compose_url_version" = "latest" ]; then
        compose_url_path="releases/latest/download"
    else
        compose_numeric_version=${compose_url_version#v}
        [ "$compose_numeric_version" != "$compose_url_version" ] || return 1
        compose_old_ifs=$IFS
        IFS=.
        set -- $compose_numeric_version
        IFS=$compose_old_ifs
        [ "$#" -eq 3 ] || return 1
        for compose_version_part in "$@"; do
            case "$compose_version_part" in
                '' | *[!0-9]*) return 1 ;;
            esac
        done
        compose_url_path="releases/download/$compose_url_version"
    fi

    compose_url="https://github.com/docker/compose/$compose_url_path/docker-compose-$compose_url_os-$compose_url_arch"
    case "$compose_url_source" in
        official) printf '%s\n' "$compose_url" ;;
        gh-proxy) printf '%s\n' "https://gh-proxy.org/$compose_url" ;;
        *) return 1 ;;
    esac
}

run_privileged() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        printf '%s\n' "需要 root 或 sudo 权限: $*" >&2
        return 1
    fi
}

download_file() {
    download_url=$1
    download_output=$2
    curl --fail --location --silent --show-error \
        --retry 3 --connect-timeout 10 \
        -o "$download_output" "$download_url"
}

verify_sha256() {
    verify_file=$1
    verify_checksum_file=$2
    verify_expected=$(awk 'NR == 1 {print $1}' "$verify_checksum_file")
    [ -n "$verify_expected" ] || return 1

    if command -v sha256sum >/dev/null 2>&1; then
        verify_actual=$(sha256sum "$verify_file" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        verify_actual=$(shasum -a 256 "$verify_file" | awk '{print $1}')
    else
        printf '%s\n' "缺少 sha256sum 或 shasum，无法校验下载文件。" >&2
        return 1
    fi

    [ "$verify_actual" = "$verify_expected" ]
}

install_compose() {
    install_compose_version=$1
    install_compose_source=$2
    install_compose_os=$3
    install_compose_arch=$4
    install_compose_plugin_dir=${COMPOSE_PLUGIN_DIR:-/usr/local/lib/docker/cli-plugins}
    install_compose_compat_dir=${COMPOSE_COMPAT_DIR:-/usr/local/bin}

    install_compose_url=$(compose_asset_url \
        "$install_compose_version" "$install_compose_source" \
        "$install_compose_os" "$install_compose_arch") || return 1
    install_compose_tmp=$(mktemp -d) || return 1
    install_compose_binary="$install_compose_tmp/docker-compose"
    install_compose_checksum="$install_compose_tmp/docker-compose.sha256"

    if ! download_file "$install_compose_url" "$install_compose_binary"; then
        rm -rf "$install_compose_tmp"
        return 1
    fi
    if ! download_file "${install_compose_url}.sha256" "$install_compose_checksum"; then
        rm -rf "$install_compose_tmp"
        return 1
    fi
    if ! verify_sha256 "$install_compose_binary" "$install_compose_checksum"; then
        printf '%s\n' "Docker Compose SHA256 校验失败。" >&2
        rm -rf "$install_compose_tmp"
        return 1
    fi

    if ! run_privileged mkdir -p "$install_compose_plugin_dir" "$install_compose_compat_dir" || \
       ! run_privileged install -m 0755 "$install_compose_binary" "$install_compose_plugin_dir/docker-compose" || \
       ! run_privileged ln -sfn "$install_compose_plugin_dir/docker-compose" "$install_compose_compat_dir/docker-compose"; then
        rm -rf "$install_compose_tmp"
        return 1
    fi

    rm -rf "$install_compose_tmp"
    "$install_compose_plugin_dir/docker-compose" version
}

choose_docker_source() {
    choose_source=${DOCKER_SOURCE:-}
    case "$choose_source" in
        1) choose_source=aliyun ;;
        2) choose_source=tsinghua ;;
        3) choose_source=official ;;
        4) choose_source=skip ;;
    esac

    if [ -n "$choose_source" ]; then
        case "$choose_source" in
            aliyun | tsinghua | official | skip) printf '%s\n' "$choose_source"; return 0 ;;
            *) return 1 ;;
        esac
    fi

    if [ "${AUTO_SCRIPTS_NONINTERACTIVE:-0}" = "1" ]; then
        return 1
    fi
    if ! is_interactive && [ ! -r /dev/tty ]; then
        return 1
    fi

    while :; do
        printf '%b\n' "${CYAN}-------------------------------------------------------${NC}" >&2
        printf '%s\n' "请选择 Docker 安装源:" >&2
        printf '%s\n' "1) 官方脚本 + 阿里云镜像" >&2
        printf '%s\n' "2) 官方脚本 + 清华大学镜像" >&2
        printf '%s\n' "3) Docker 官方源" >&2
        printf '%s\n' "4) 跳过 Docker 引擎安装" >&2
        printf '%s' "请输入数字 [1-4]: " >&2
        if is_interactive; then
            IFS= read -r choose_source || return 1
        else
            IFS= read -r choose_source < /dev/tty || return 1
        fi
        case "$choose_source" in
            1) printf '%s\n' "aliyun"; return 0 ;;
            2) printf '%s\n' "tsinghua"; return 0 ;;
            3) printf '%s\n' "official"; return 0 ;;
            4) printf '%s\n' "skip"; return 0 ;;
            *) warn "无效选项，请输入 1-4。" ;;
        esac
    done
}

target_user() {
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        printf '%s\n' "$SUDO_USER"
    elif [ -n "${USER:-}" ] && [ "$USER" != "root" ]; then
        printf '%s\n' "$USER"
    else
        id -un
    fi
}

install_docker_engine() {
    docker_install_source=$1
    [ "$docker_install_source" != "skip" ] || return 0

    if command -v docker >/dev/null 2>&1 && \
       [ "${DOCKER_REINSTALL:-0}" != "1" ] && \
       ! ask_user "检测到 Docker，是否重新运行官方安装脚本?" "n"; then
        info ">>> 保留现有 Docker，跳过引擎安装。"
        return 0
    fi

    command -v curl >/dev/null 2>&1 || die "缺少 curl，无法下载 Docker 安装脚本。"
    docker_install_tmp=$(mktemp -d) || die "无法创建临时目录。"
    docker_install_script="$docker_install_tmp/get-docker.sh"
    if ! download_file "https://get.docker.com" "$docker_install_script"; then
        rm -rf "$docker_install_tmp"
        die "Docker 安装脚本下载失败。"
    fi

    info ">>> 正在安装 Docker（来源: $docker_install_source）..."
    case "$docker_install_source" in
        aliyun)
            run_privileged sh "$docker_install_script" --mirror Aliyun || {
                rm -rf "$docker_install_tmp"; die "Docker 安装失败。";
            }
            ;;
        tsinghua)
            DOWNLOAD_URL="https://mirrors.tuna.tsinghua.edu.cn/docker-ce"
            export DOWNLOAD_URL
            run_privileged sh "$docker_install_script" || {
                rm -rf "$docker_install_tmp"; die "Docker 安装失败。";
            }
            unset DOWNLOAD_URL
            ;;
        official)
            run_privileged sh "$docker_install_script" || {
                rm -rf "$docker_install_tmp"; die "Docker 安装失败。";
            }
            ;;
        *) rm -rf "$docker_install_tmp"; die "不支持的 Docker 安装源: $docker_install_source" ;;
    esac
    rm -rf "$docker_install_tmp"
    command -v docker >/dev/null 2>&1 || die "安装脚本执行完成，但未找到 docker 命令。"
}

uninstall_docker() {
    uninstall_plugin_dir=${COMPOSE_PLUGIN_DIR:-/usr/local/lib/docker/cli-plugins}
    uninstall_compat_dir=${COMPOSE_COMPAT_DIR:-/usr/local/bin}

    info ">>> 开始卸载 Docker 软件包和 Compose 组件。"
    warn ">>> 保留 /var/lib/docker、/var/lib/containerd、/etc/docker 及容器数据。"

    if command -v systemctl >/dev/null 2>&1; then
        run_privileged systemctl stop docker.socket docker containerd 2>/dev/null || true
        run_privileged systemctl disable docker.socket docker containerd 2>/dev/null || true
    fi

    run_privileged rm -f \
        "$uninstall_plugin_dir/docker-compose" \
        "$uninstall_compat_dir/docker-compose" || \
        warn "Compose 文件卸载失败，请检查权限。"

    uninstall_packages="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras docker-scan-plugin docker.io docker-compose docker-compose-v2"
    if command -v apt-get >/dev/null 2>&1; then
        run_privileged apt-get remove -y $uninstall_packages || \
            warn "部分 Docker Debian 软件包未能卸载。"
    elif command -v dnf >/dev/null 2>&1; then
        run_privileged dnf remove -y $uninstall_packages || \
            warn "部分 Docker RPM 软件包未能卸载。"
    elif command -v yum >/dev/null 2>&1; then
        run_privileged yum remove -y $uninstall_packages || \
            warn "部分 Docker RPM 软件包未能卸载。"
    else
        warn "未找到 apt-get、dnf 或 yum；跳过 Docker 软件包卸载。"
    fi

    info ">>> Docker 软件包和 Compose 组件卸载流程完成。"
    info ">>> 数据目录未删除；如需清理数据，请先单独备份后手工处理。"
}

merge_daemon_json() {
    merge_existing=$1
    merge_desired=$2
    merge_output=$3
    jq -s '.[0] * .[1]' "$merge_existing" "$merge_desired" > "$merge_output"
}

configure_daemon_json() {
    daemon_tmp=$(mktemp -d) || return 1
    daemon_desired="$daemon_tmp/desired.json"
    daemon_merged="$daemon_tmp/daemon.json"
    daemon_existing="$daemon_tmp/existing.json"
    daemon_mirror=${DOCKER_REGISTRY_MIRROR:-https://docker.m.daocloud.io}

    case "$daemon_mirror" in
        https://*) ;;
        *) rm -rf "$daemon_tmp"; warn "镜像地址必须使用 https://，跳过 daemon 配置。"; return 0 ;;
    esac

    cat > "$daemon_desired" <<EOF
{
  "registry-mirrors": ["$daemon_mirror"],
  "log-driver": "json-file",
  "log-opts": {"max-size": "50m", "max-file": "3"}
}
EOF

    daemon_had_existing=0
    if run_privileged test -f /etc/docker/daemon.json; then
        daemon_had_existing=1
        if ! command -v jq >/dev/null 2>&1; then
            warn "已有 /etc/docker/daemon.json，但缺少 jq；为避免覆盖，跳过自动合并。"
            rm -rf "$daemon_tmp"
            return 0
        fi
        run_privileged cp /etc/docker/daemon.json "$daemon_existing" || {
            rm -rf "$daemon_tmp"; return 1;
        }
        merge_daemon_json "$daemon_existing" "$daemon_desired" "$daemon_merged" || {
            rm -rf "$daemon_tmp"; return 1;
        }
    else
        cp "$daemon_desired" "$daemon_merged"
    fi

    if command -v jq >/dev/null 2>&1; then
        jq empty "$daemon_merged" || { rm -rf "$daemon_tmp"; return 1; }
    fi
    if command -v dockerd >/dev/null 2>&1; then
        dockerd --validate --config-file "$daemon_merged" >/dev/null || {
            rm -rf "$daemon_tmp"; return 1;
        }
    fi

    if [ "$daemon_had_existing" -eq 1 ]; then
        daemon_backup="/etc/docker/daemon.json.backup.$(date +%Y%m%d%H%M%S)"
        run_privileged cp /etc/docker/daemon.json "$daemon_backup" || {
            rm -rf "$daemon_tmp"; return 1;
        }
        info ">>> 已备份 Docker 配置到 $daemon_backup"
    fi
    run_privileged mkdir -p /etc/docker || { rm -rf "$daemon_tmp"; return 1; }
    run_privileged install -m 0644 "$daemon_merged" /etc/docker/daemon.json || {
        rm -rf "$daemon_tmp"; return 1;
    }
    rm -rf "$daemon_tmp"
}

configure_docker() {
    if command -v systemctl >/dev/null 2>&1; then
        run_privileged systemctl enable docker >/dev/null
        run_privileged systemctl start docker
    else
        warn "未检测到 systemctl，请手动启动 Docker Daemon。"
    fi

    docker_target_user=$(target_user)
    if [ "$docker_target_user" != "root" ] && \
       command -v groupadd >/dev/null 2>&1 && command -v usermod >/dev/null 2>&1; then
        run_privileged groupadd -f docker
        run_privileged usermod -aG docker "$docker_target_user"
        warn "用户 $docker_target_user 已加入 docker 组；请重新登录后生效。"
    fi

    docker_configure=${DOCKER_CONFIGURE_DAEMON:-}
    if [ -z "$docker_configure" ]; then
        if [ "${AUTO_SCRIPTS_NONINTERACTIVE:-0}" = "1" ] || ! is_interactive; then
            docker_configure=0
        elif ask_user "是否安全合并镜像与日志配置?" "y"; then
            docker_configure=1
        else
            docker_configure=0
        fi
    fi
    case "$docker_configure" in
        1)
            configure_daemon_json || die "Docker daemon 配置失败，原配置未被覆盖。"
            if command -v systemctl >/dev/null 2>&1; then
                run_privileged systemctl restart docker || die "Docker 配置已写入，但服务重启失败。"
            fi
            ;;
        0) ;;
        *) die "DOCKER_CONFIGURE_DAEMON 只能是 0 或 1。" ;;
    esac
}

installed_compose_version() {
    if docker compose version --short >/dev/null 2>&1; then
        docker compose version --short 2>/dev/null | sed -n '1{s/^v//;s/[^0-9.].*$//;p;}'
    else
        return 1
    fi
}

latest_compose_version() {
    curl --fail --location --silent --show-error --connect-timeout 10 \
        -H 'Accept: application/vnd.github+json' \
        https://api.github.com/repos/docker/compose/releases/latest 2>/dev/null |
        sed -n 's/.*"tag_name": "v\([0-9.]*\)".*/\1/p' | sed -n '1p'
}

manage_compose() {
    compose_update=${COMPOSE_UPDATE:-auto}
    case "$compose_update" in
        0) return 0 ;;
        1 | auto) ;;
        *) die "COMPOSE_UPDATE 只能是 0、1 或 auto。" ;;
    esac

    command -v docker >/dev/null 2>&1 || die "未找到 Docker CLI，无法安装 Compose 插件。"
    command -v curl >/dev/null 2>&1 || die "缺少 curl，无法下载 Compose。"

    compose_version=${COMPOSE_VERSION:-latest}
    compose_source=${COMPOSE_DOWNLOAD_SOURCE:-official}
    compose_os=linux
    compose_arch=$(normalize_arch "$(uname -m)") || die "不支持的 CPU 架构: $(uname -m)"
    compose_asset_url "$compose_version" "$compose_source" "$compose_os" "$compose_arch" >/dev/null || \
        die "Compose 版本或下载源无效。"

    compose_current=$(installed_compose_version 2>/dev/null || true)
    compose_target=${compose_version#v}
    if [ "$compose_version" = "latest" ]; then
        compose_target=$(latest_compose_version 2>/dev/null || true)
    fi

    if [ -n "$compose_current" ] && [ -n "$compose_target" ] && \
       [ "$compose_current" = "$compose_target" ]; then
        info ">>> Docker Compose 已是目标版本 v$compose_current。"
        return 0
    fi

    if [ "$compose_update" = "auto" ] && is_interactive && \
       ! ask_user "是否安装或更新 Docker Compose ${compose_version}?" "y"; then
        return 0
    fi

    info ">>> 正在安装 Docker Compose ${compose_version}..."
    install_compose "$compose_version" "$compose_source" "$compose_os" "$compose_arch" || \
        die "Docker Compose 下载、校验或安装失败。"
}

main() {
    info ">>> 正在启动 Docker 自动化安装程序..."
    [ "$(uname -s)" = "Linux" ] || die "Docker 自动安装仅支持 Linux。"

    case "${1:-}" in
        uninstall | --uninstall) DOCKER_UNINSTALL=1 ;;
    esac
    if [ "${DOCKER_UNINSTALL:-0}" = "1" ] || [ "${ACTION:-}" = "uninstall" ]; then
        uninstall_docker
        return 0
    fi

    docker_source=$(choose_docker_source) || \
        die "无法读取 Docker 安装源；请设置 DOCKER_SOURCE=official|aliyun|tsinghua|skip，或在可用终端输入 1-4。"
    install_docker_engine "$docker_source"

    if [ "$docker_source" != "skip" ]; then
        configure_docker
    else
        warn ">>> 已跳过 Docker 引擎安装与 daemon 配置。"
    fi

    manage_compose

    command -v docker >/dev/null 2>&1 || die "未找到 docker 命令。"
    printf '\n%b\n' "${GREEN}===========================================${NC}"
    docker --version
    if ! docker compose version; then
        docker-compose version || die "Docker Compose 验证失败。"
    fi
    info ">>> Docker/Compose 检查完成。"
    warn ">>> 若刚加入 docker 组，请重新登录或手动执行 newgrp docker。"
    printf '%b\n' "${GREEN}===========================================${NC}"
}

# 测试只加载函数，不执行安装流程。
if [ "${AUTO_SCRIPTS_LIBRARY:-0}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi

main "$@"
