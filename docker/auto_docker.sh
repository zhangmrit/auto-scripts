#!/bin/sh

# =================================================================
# 脚本名称: auto_docker.sh
# 功能: 自动化安装 Docker 引擎、配置镜像加速、安装独立 docker-compose
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

has_prompt_terminal() {
    is_interactive || { [ -r /dev/tty ] && [ -w /dev/tty ]; }
}

# 交互函数 (POSIX 兼容)
ask_user() {
    ask_prompt=$1
    ask_default=$2
    if [ "${AUTO_SCRIPTS_NONINTERACTIVE:-0}" = "1" ] || ! has_prompt_terminal; then
        case "$ask_default" in [Yy]) return 0 ;; *) return 1 ;; esac
    fi
    while :; do
        printf '%b' "${YELLOW}${ask_prompt} (y/n, 默认 ${ask_default}): ${NC}" >&2
        if is_interactive; then
            IFS= read -r ask_result || ask_result=$ask_default
        else
            IFS= read -r ask_result < /dev/tty || ask_result=$ask_default
        fi
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

usage() {
    cat <<'EOF'
用法: sh auto_docker.sh [选项]

默认模式：交互检测/选择 Docker 引擎，再独立处理 Compose。
无人值守模式按 auto 规则执行：Docker CE 默认腾讯云源，已安装组件默认跳过。
一键安装示例：sh auto_docker.sh --yes --source aliyun

选项：
  --yes, -y                    无人值守 auto 模式：Docker CE 默认腾讯云源，已安装组件默认跳过
  --source SOURCE              Docker 源: official|aliyun|tencent|skip（auto 默认 tencent）
  --reinstall                  已安装 Docker 时重新运行安装脚本
  --configure-daemon           安全合并镜像与日志配置
  --no-configure-daemon        跳过 daemon 配置
  --compose-version VERSION    Compose 版本，例如 latest 或 v5.6.0
  --compose-source SOURCE      Compose 下载源: auto|official|gh-proxy（默认 auto）
  --compose-compat             强制安装/更新独立 docker-compose 命令
  --no-compose-compat          跳过独立 docker-compose 管理
  --uninstall                  纯卸载 Docker 和 Compose
  --cleanup                    卸载时清理 Docker 数据与配置（危险，删除不可恢复）
  --no-cleanup                 卸载时保留 Docker 数据与配置
  --help, -h                   显示帮助

环境变量仍然兼容，命令行选项优先于同名环境变量。
EOF
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --yes | -y)
                AUTO_SCRIPTS_NONINTERACTIVE=1
                ;;
            --source | --docker-source)
                [ "$#" -ge 2 ] || die "--source 需要 official、aliyun、tencent 或 skip。"
                case "$2" in
                    official | aliyun | tencent | tsinghua | skip | 1 | 2 | 3 | 4) ;;
                    *) die "--source 只能是 official、aliyun、tencent 或 skip。" ;;
                esac
                DOCKER_SOURCE=$2
                shift
                ;;
            --reinstall)
                DOCKER_REINSTALL=1
                ;;
            --configure-daemon)
                DOCKER_CONFIGURE_DAEMON=1
                ;;
            --no-configure-daemon)
                DOCKER_CONFIGURE_DAEMON=0
                ;;
            --compose-version)
                [ "$#" -ge 2 ] || die "--compose-version 需要 latest 或 vN.N.N。"
                COMPOSE_VERSION=$2
                shift
                ;;
            --compose-source)
                [ "$#" -ge 2 ] || die "--compose-source 需要 auto、official 或 gh-proxy。"
                COMPOSE_DOWNLOAD_SOURCE=$2
                shift
                ;;
            --compose-compat)
                COMPOSE_COMPAT_INSTALL=1
                ;;
            --no-compose-compat)
                COMPOSE_COMPAT_INSTALL=0
                ;;
            --uninstall | uninstall | --remove)
                DOCKER_UNINSTALL=1
                ;;
            --cleanup)
                DOCKER_CLEANUP=1
                ;;
            --no-cleanup)
                DOCKER_CLEANUP=0
                ;;
            --help | -h)
                usage
                exit 0
                ;;
            --install)
                :
                ;;
            *)
                die "未知选项: $1；使用 --help 查看用法。"
                ;;
        esac
        shift
    done
    if [ "${AUTO_SCRIPTS_NONINTERACTIVE:-0}" = "1" ]; then
        DOCKER_SOURCE=${DOCKER_SOURCE:-tencent}
    fi
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
        case "$compose_numeric_version" in
            *.*.*) ;;
            *) return 1 ;;
        esac
        compose_version_major=${compose_numeric_version%%.*}
        compose_version_rest=${compose_numeric_version#*.}
        compose_version_minor=${compose_version_rest%%.*}
        compose_version_patch=${compose_version_rest#*.}
        [ -n "$compose_version_major" ] &&
            [ -n "$compose_version_minor" ] &&
            [ -n "$compose_version_patch" ] || return 1
        for compose_version_part in \
            "$compose_version_major" "$compose_version_minor" "$compose_version_patch"; do
            case "$compose_version_part" in
                *[!0-9]*) return 1 ;;
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
    download_max_time=${3:-120}
    curl --fail --location --silent --show-error \
        --connect-timeout 10 --max-time "$download_max_time" \
        --speed-limit 10240 --speed-time 30 \
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

download_compose_from_source() {
    download_one_version=$1
    download_one_source=$2
    download_one_os=$3
    download_one_arch=$4
    download_one_binary=$5
    download_one_checksum=$6

    download_one_url=$(compose_asset_url \
        "$download_one_version" "$download_one_source" \
        "$download_one_os" "$download_one_arch") || return 1
    rm -f "$download_one_binary" "$download_one_checksum"
    if ! download_file "$download_one_url" "$download_one_binary" 300 || \
       ! download_file "${download_one_url}.sha256" "$download_one_checksum"; then
        return 1
    fi
    verify_sha256 "$download_one_binary" "$download_one_checksum"
}

# auto/official 按官方 GitHub → gh-proxy 顺序尝试；显式 gh-proxy 时反过来。
# 二进制和 SHA256 文件必须来自同一个候选源并同时下载成功。
download_compose_assets() {
    download_compose_version=$1
    download_compose_source=$2
    download_compose_os=$3
    download_compose_arch=$4
    download_compose_binary=$5
    download_compose_checksum=$6

    case "$download_compose_source" in
        auto | official)
            download_compose_first_source=official
            download_compose_second_source=gh-proxy
            ;;
        gh-proxy)
            download_compose_first_source=gh-proxy
            download_compose_second_source=official
            ;;
        *)
            return 1
            ;;
    esac

    if download_compose_from_source \
        "$download_compose_version" "$download_compose_first_source" \
        "$download_compose_os" "$download_compose_arch" \
        "$download_compose_binary" "$download_compose_checksum"; then
        info ">>> Compose 使用下载源: $download_compose_first_source"
        return 0
    fi
    warn ">>> Compose 下载或 SHA256 校验失败: ${download_compose_first_source}，尝试下一个源。"

    if download_compose_from_source \
        "$download_compose_version" "$download_compose_second_source" \
        "$download_compose_os" "$download_compose_arch" \
        "$download_compose_binary" "$download_compose_checksum"; then
        info ">>> Compose 使用下载源: $download_compose_second_source"
        return 0
    fi
    warn ">>> Compose 下载或 SHA256 校验失败: ${download_compose_second_source}。"
    return 1
}

install_compose() {
    install_compose_version=$1
    install_compose_source=$2
    install_compose_os=$3
    install_compose_arch=$4
    install_compose_compat_dir=${COMPOSE_COMPAT_DIR:-/usr/local/bin}

    install_compose_tmp=$(mktemp -d) || return 1
    install_compose_binary="$install_compose_tmp/docker-compose"
    install_compose_checksum="$install_compose_tmp/docker-compose.sha256"

    if ! download_compose_assets \
        "$install_compose_version" "$install_compose_source" \
        "$install_compose_os" "$install_compose_arch" \
        "$install_compose_binary" "$install_compose_checksum"; then
        rm -rf "$install_compose_tmp"
        return 1
    fi

    if ! run_privileged mkdir -p "$install_compose_compat_dir" || \
       ! run_privileged install -m 0755 "$install_compose_binary" "$install_compose_compat_dir/docker-compose"; then
        rm -rf "$install_compose_tmp"
        return 1
    fi

    rm -rf "$install_compose_tmp"
    info ">>> 独立 docker-compose 命令已安装到 $install_compose_compat_dir/docker-compose"
    "$install_compose_compat_dir/docker-compose" version
    compose_resolved_path=$(command -v docker-compose 2>/dev/null || true)
    if [ -n "$compose_resolved_path" ] && [ "$compose_resolved_path" != "$install_compose_compat_dir/docker-compose" ]; then
        warn ">>> 当前 shell 仍解析到旧的 docker-compose: $compose_resolved_path"
        warn ">>> 请执行 rehash（zsh）或 hash -r（bash），或重新登录后再检查版本。"
    fi
}

choose_docker_source() {
    choose_source=${DOCKER_SOURCE:-}
    case "$choose_source" in
        1) choose_source=aliyun ;;
        2) choose_source=tencent ;;
        3) choose_source=official ;;
        4) choose_source=skip ;;
    esac

    if [ -n "$choose_source" ]; then
        case "$choose_source" in
            aliyun | tencent | tsinghua | official | skip) printf '%s\n' "$choose_source"; return 0 ;;
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
        printf '%s\n' "1) 阿里云 Docker CE 镜像源" >&2
        printf '%s\n' "2) 腾讯云 Docker CE 镜像源" >&2
        printf '%s\n' "3) Docker 官方源" >&2
        printf '%s\n' "4) 跳过 Docker 引擎安装" >&2
        printf '%s' "请输入数字 [1-4]（默认 2）: " >&2
        if is_interactive; then
            IFS= read -r choose_source || return 1
        else
            IFS= read -r choose_source < /dev/tty || return 1
        fi
        choose_source=${choose_source:-2}
        case "$choose_source" in
            1) printf '%s\n' "aliyun"; return 0 ;;
            2) printf '%s\n' "tencent"; return 0 ;;
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

download_docker_installer() {
    docker_installer_output=$1
    docker_installer_url="https://get.docker.com"
    if download_file "$docker_installer_url" "$docker_installer_output"; then
        return 0
    fi
    warn "无法直连 get.docker.com，尝试 GitHub 源码地址。"

    docker_installer_url="https://raw.githubusercontent.com/docker/docker-install/master/install.sh"
    if download_file "$docker_installer_url" "$docker_installer_output"; then
        return 0
    fi
    warn "无法直连 GitHub，尝试 gh-proxy 下载官方一键脚本。"

    docker_installer_url="https://gh-proxy.org/https://raw.githubusercontent.com/docker/docker-install/master/install.sh"
    download_file "$docker_installer_url" "$docker_installer_output"
}

install_docker_engine() {
    docker_install_source=$1
    [ "$docker_install_source" != "skip" ] || return 0

    command -v curl >/dev/null 2>&1 || die "缺少 curl，无法下载 Docker 安装脚本。"
    docker_install_tmp=$(mktemp -d) || die "无法创建临时目录。"
    docker_install_script="$docker_install_tmp/get-docker.sh"
    if ! download_docker_installer "$docker_install_script"; then
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
        tencent | tsinghua)
            run_privileged env DOWNLOAD_URL="https://mirrors.cloud.tencent.com/docker-ce" \
                sh "$docker_install_script" || {
                rm -rf "$docker_install_tmp"; die "Docker 安装失败。";
            }
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

should_install_docker() {
    docker_is_installed=0
    if command -v docker >/dev/null 2>&1; then
        docker_is_installed=1
    fi

    case "${DOCKER_REINSTALL:-}" in
        0 | 1 | '') ;;
        *) die "DOCKER_REINSTALL 只能是 0 或 1。" ;;
    esac

    case "${DOCKER_SOURCE:-}" in
        skip | 4)
            return 1
            ;;
    esac

    if [ "${DOCKER_REINSTALL:-}" = "1" ]; then
        return 0
    fi
    if [ "${DOCKER_REINSTALL:-}" = "0" ] && [ "$docker_is_installed" -eq 1 ]; then
        return 1
    fi

    if [ "$docker_is_installed" -eq 1 ]; then
        ask_user "检测到 Docker，是否重新安装或修复 Docker 引擎?" "n"
    else
        ask_user "未检测到 Docker，是否安装 Docker 引擎?" "y"
    fi
}

uninstall_docker() {
    uninstall_compat_dir=${COMPOSE_COMPAT_DIR:-/usr/local/bin}
    uninstall_failed=0

    info ">>> 开始卸载 Docker 软件包和 Compose 组件。"
    warn ">>> 默认保留 /var/lib/docker、/var/lib/containerd、/etc/docker 及容器数据。"

    docker_cleanup=${DOCKER_CLEANUP:-}
    if [ -z "$docker_cleanup" ]; then
        if [ "${AUTO_SCRIPTS_NONINTERACTIVE:-0}" = "1" ] || ! has_prompt_terminal; then
            docker_cleanup=0
        elif ask_user "是否清理 Docker 留存的数据与配置（/var/lib/docker、/var/lib/containerd、/etc/docker）?" "n"; then
            docker_cleanup=1
        else
            docker_cleanup=0
        fi
    fi
    case "$docker_cleanup" in
        0) info ">>> 保留 Docker 数据与配置。" ;;
        1) warn ">>> 将清理 Docker 数据与配置，此操作不可恢复。" ;;
        *) die "DOCKER_CLEANUP 只能是 0 或 1。" ;;
    esac

    if command -v systemctl >/dev/null 2>&1; then
        run_privileged systemctl stop docker.socket docker containerd 2>/dev/null || true
        run_privileged systemctl disable docker.socket docker containerd 2>/dev/null || true
    fi

    run_privileged rm -f "$uninstall_compat_dir/docker-compose" || \
        warn "Compose 文件卸载失败，请检查权限。"

    uninstall_packages="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras docker-scan-plugin docker.io docker-compose docker-compose-v2"
    if command -v apt-get >/dev/null 2>&1; then
        uninstall_installed_packages=""
        for uninstall_package in $uninstall_packages; do
            if dpkg-query -W -f='${Status}' "$uninstall_package" 2>/dev/null |
                grep -q '^install ok installed$'; then
                uninstall_installed_packages="$uninstall_installed_packages $uninstall_package"
            fi
        done
        if [ -n "$uninstall_installed_packages" ]; then
            # 只传入实际已安装的软件包，避免某个不存在的历史包名导致整组失败。
            if ! run_privileged apt-get remove -y $uninstall_installed_packages; then
                warn "部分 Docker Debian 软件包未能卸载。"
                uninstall_failed=1
            fi
        else
            info ">>> 未检测到可卸载的 Docker Debian 软件包。"
        fi
    elif command -v dnf >/dev/null 2>&1; then
        uninstall_installed_packages=""
        for uninstall_package in $uninstall_packages; do
            if command -v rpm >/dev/null 2>&1 && rpm -q "$uninstall_package" >/dev/null 2>&1; then
                uninstall_installed_packages="$uninstall_installed_packages $uninstall_package"
            fi
        done
        if [ -n "$uninstall_installed_packages" ]; then
            if ! run_privileged dnf remove -y $uninstall_installed_packages; then
                warn "部分 Docker RPM 软件包未能卸载。"
                uninstall_failed=1
            fi
        else
            info ">>> 未检测到可卸载的 Docker RPM 软件包。"
        fi
    elif command -v yum >/dev/null 2>&1; then
        uninstall_installed_packages=""
        for uninstall_package in $uninstall_packages; do
            if command -v rpm >/dev/null 2>&1 && rpm -q "$uninstall_package" >/dev/null 2>&1; then
                uninstall_installed_packages="$uninstall_installed_packages $uninstall_package"
            fi
        done
        if [ -n "$uninstall_installed_packages" ]; then
            if ! run_privileged yum remove -y $uninstall_installed_packages; then
                warn "部分 Docker RPM 软件包未能卸载。"
                uninstall_failed=1
            fi
        else
            info ">>> 未检测到可卸载的 Docker RPM 软件包。"
        fi
    else
        warn "未找到 apt-get、dnf 或 yum；跳过 Docker 软件包卸载。"
        uninstall_failed=1
    fi

    if command -v docker >/dev/null 2>&1; then
        warn ">>> 卸载后仍检测到 docker 命令: $(command -v docker)。请检查残留软件包或手动安装文件。"
        uninstall_failed=1
    fi
    if command -v docker-compose >/dev/null 2>&1; then
        warn ">>> 卸载后仍检测到 docker-compose 命令: $(command -v docker-compose)。"
        uninstall_failed=1
    fi
    if [ "$docker_cleanup" -eq 1 ]; then
        run_privileged rm -rf /var/lib/docker /var/lib/containerd /etc/docker || {
            warn ">>> Docker 留存数据或配置清理失败。"
            uninstall_failed=1
        }
    fi
    if [ "$uninstall_failed" -eq 0 ]; then
        info ">>> Docker 软件包和 Compose 组件卸载流程完成。"
    else
        warn ">>> Docker 卸载流程结束，但仍有组件未清理完成。"
    fi
    if [ "$docker_cleanup" -eq 0 ]; then
        info ">>> 数据目录未删除；如需清理数据，请先单独备份后手工处理。"
    fi
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
    daemon_mirrors=${DOCKER_REGISTRY_MIRRORS:-}
    if [ -z "$daemon_mirrors" ] && [ -n "${DOCKER_REGISTRY_MIRROR:-}" ]; then
        daemon_mirrors=$DOCKER_REGISTRY_MIRROR
    fi
    if [ -z "$daemon_mirrors" ]; then
        daemon_mirrors='https://docker.1ms.run,https://docker.1panel.live,https://docker.m.daocloud.io,https://mirror.ccs.tencentyun.com'
    fi

    daemon_mirrors_json=$(printf '%s\n' "$daemon_mirrors" | awk -F, '
        BEGIN { printf "[" }
        {
            for (i = 1; i <= NF; i++) {
                mirror = $i
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", mirror)
                if (mirror == "") continue
                if (mirror !~ /^https:\/\//) exit 1
                if (count++ > 0) printf ","
                printf "\"%s\"", mirror
            }
        }
        END { printf "]\n" }
    ') || {
        rm -rf "$daemon_tmp"
        warn "镜像地址必须使用逗号分隔的 https:// 地址，跳过 daemon 配置。"
        return 0
    }

    cat > "$daemon_desired" <<EOF
{
  "registry-mirrors": $daemon_mirrors_json,
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
        if [ "${AUTO_SCRIPTS_NONINTERACTIVE:-0}" = "1" ] || ! has_prompt_terminal; then
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

installed_compat_compose_version() {
    compat_compose_path=${COMPOSE_COMPAT_DIR:-/usr/local/bin}/docker-compose
    if [ -x "$compat_compose_path" ]; then
        "$compat_compose_path" version --short 2>/dev/null |
            sed -n '1{s/^v//;s/[^0-9.].*$//;p;}'
    else
        return 1
    fi
}

latest_compose_version() {
    latest_compose_response=$(curl --fail --location --silent --show-error \
        --connect-timeout 10 --max-time 30 \
        -H 'Accept: application/vnd.github+json' \
        https://api.github.com/repos/docker/compose/releases/latest 2>/dev/null || true)
    latest_compose_tag=$(printf '%s\n' "$latest_compose_response" |
        sed -n 's/.*"tag_name": "v\([0-9.]*\)".*/\1/p' | sed -n '1p')
    if [ -n "$latest_compose_tag" ]; then
        printf '%s\n' "$latest_compose_tag"
        return 0
    fi

    # 国内网络无法访问 GitHub API 时，通过同一 GitHub 加速入口解析 latest。
    latest_compose_response=$(curl --fail --location --silent --show-error \
        --connect-timeout 10 --max-time 30 \
        -H 'Accept: application/vnd.github+json' \
        https://gh-proxy.org/https://api.github.com/repos/docker/compose/releases/latest 2>/dev/null || true)
    printf '%s\n' "$latest_compose_response" |
        sed -n 's/.*"tag_name": "v\([0-9.]*\)".*/\1/p' | sed -n '1p'
}

manage_compose() {
    compose_update=${COMPOSE_UPDATE:-auto}
    case "$compose_update" in
        0) return 0 ;;
        1 | auto) ;;
        *) die "COMPOSE_UPDATE 只能是 0、1 或 auto。" ;;
    esac

    compose_install=${COMPOSE_COMPAT_INSTALL:-auto}
    case "$compose_install" in
        0 | 1 | auto) ;;
        *) die "COMPOSE_COMPAT_INSTALL 只能是 0、1 或 auto。" ;;
    esac
    if [ "$compose_install" = "0" ]; then
        info ">>> 按选择跳过独立 docker-compose 安装。"
        return 0
    fi

    command -v curl >/dev/null 2>&1 || die "缺少 curl，无法下载 Compose。"

    compose_version=${COMPOSE_VERSION:-latest}
    compose_source=${COMPOSE_DOWNLOAD_SOURCE:-auto}
    compose_os=linux
    compose_arch=$(normalize_arch "$(uname -m)") || die "不支持的 CPU 架构: $(uname -m)"
    case "$compose_source" in
        auto | official | gh-proxy) ;;
        *) die "Compose 下载源无效，支持 auto、official 或 gh-proxy。" ;;
    esac
    compose_asset_url "$compose_version" official "$compose_os" "$compose_arch" >/dev/null || \
        die "Compose 版本无效。"

    compose_compat_current=$(installed_compat_compose_version 2>/dev/null || true)
    compose_target=${compose_version#v}
    if [ "$compose_version" = "latest" ]; then
        compose_target=$(latest_compose_version 2>/dev/null || true)
    fi

    compose_needs_install=1
    if [ -n "$compose_compat_current" ] && [ -n "$compose_target" ] && \
       [ "$compose_compat_current" = "$compose_target" ]; then
        compose_needs_install=0
    fi

    # 无人值守模式下不得进入询问分支：ask_user 会直接采用默认值 y，
    # 导致已安装的独立 docker-compose 被强制覆盖更新（违反 auto 规则）。
    if [ "$compose_update" = "auto" ] && \
       [ "${AUTO_SCRIPTS_NONINTERACTIVE:-0}" != "1" ] && has_prompt_terminal; then
        if [ -n "$compose_compat_current" ]; then
            info ">>> 检测到独立 docker-compose: v$compose_compat_current"
            compose_prompt="是否检查并安装/更新独立 docker-compose 到 v${compose_target:-$compose_version}?"
        else
            compose_prompt="未检测到独立 docker-compose，是否安装 v${compose_target:-$compose_version}?"
        fi
        ask_user "$compose_prompt" "y" || return 0
    elif [ "$compose_update" != "1" ] && [ "$compose_install" != "1" ] && \
         [ -n "$compose_compat_current" ]; then
        info ">>> 已检测到独立 docker-compose v$compose_compat_current，auto 模式默认跳过覆盖。"
        info ">>> 如需更新，请使用 --compose-compat 或 COMPOSE_UPDATE=1。"
        return 0
    elif [ "$compose_update" != "1" ] && [ "$compose_install" != "1" ] && \
         [ "$compose_needs_install" -eq 0 ]; then
        info ">>> 独立 docker-compose 已是目标版本 v$compose_target。"
        return 0
    fi

    info ">>> 正在安装独立 docker-compose ${compose_version}..."
    install_compose "$compose_version" "$compose_source" "$compose_os" "$compose_arch" || \
        die "独立 Docker Compose 下载、校验或安装失败。"
}

main() {
    parse_args "$@"
    info ">>> 正在启动 Docker 自动化安装程序..."
    [ "$(uname -s)" = "Linux" ] || die "Docker 自动安装仅支持 Linux。"

    if [ "${DOCKER_UNINSTALL:-0}" = "1" ] || [ "${ACTION:-}" = "uninstall" ]; then
        uninstall_docker
        return 0
    fi

    if should_install_docker; then
        docker_source=$(choose_docker_source) || \
            die "无法读取 Docker 安装源；请设置 DOCKER_SOURCE=official|aliyun|tencent|skip，或在可用终端输入 1-4。"
        install_docker_engine "$docker_source"
        if [ "$docker_source" != "skip" ]; then
            configure_docker
        elif ! command -v docker >/dev/null 2>&1; then
            info ">>> 已跳过 Docker 引擎安装，继续独立处理 Docker Compose。"
        fi
    else
        docker_source=skip
        if command -v docker >/dev/null 2>&1; then
            info ">>> 保留现有 Docker，跳过引擎安装。"
        else
            info ">>> 未安装 Docker，跳过引擎安装；继续独立处理 Docker Compose。"
        fi
    fi

    if [ "$docker_source" = "skip" ]; then
        warn ">>> 已跳过 Docker 引擎安装与 daemon 配置。"
    fi

    manage_compose

    printf '\n%b\n' "${GREEN}===========================================${NC}"
    if command -v docker >/dev/null 2>&1; then
        docker --version
    else
        warn ">>> 未找到 docker CLI，仅验证独立 Compose 命令。"
    fi
    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose version || die "独立 Docker Compose 验证失败。"
    else
        warn ">>> 未找到独立 docker-compose 命令。"
    fi
    info ">>> Docker 与独立 docker-compose 检查完成。"
    warn ">>> 若刚加入 docker 组，请重新登录或手动执行 newgrp docker。"
    printf '%b\n' "${GREEN}===========================================${NC}"
}

# 测试只加载函数，不执行安装流程。
if [ "${AUTO_SCRIPTS_LIBRARY:-0}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi

main "$@"
