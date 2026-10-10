#!/bin/sh

# =================================================================
# 脚本名称: auto_zsh.sh
# 功能: 自动化源码编译安装 Zsh 5.9.2, Oh My Zsh, 插件及 Autojump
# 支持系统: Ubuntu/Debian (apt) / CentOS/RHEL/Fedora (yum/dnf)
# 兼容: POSIX sh (dash/bash/zsh/ksh)
# =================================================================

set -e

# 基础配置
ZSH_VERSION="5.9.2"
ZSH_TAR="zsh-$ZSH_VERSION.tar.xz"
ZSH_URL="https://sourceforge.net/projects/zsh/files/zsh/$ZSH_VERSION/$ZSH_TAR/download"
ZSH_SRC_DIR="zsh-$ZSH_VERSION"
ZSH_SHA256="36fa734374b44783582cec09bcd67822e2f992c779ec1624ab5596df078d2f81"
INSTALL_PATH=${ZSH_INSTALL_PATH:-/usr/local/bin/zsh}

ensure_zsh_plugins() {
    plugin_file=$1
    plugin_tmp="${plugin_file}.auto-scripts.$$"
    awk '
        BEGIN {
            required_count = split("autojump zsh-syntax-highlighting zsh-autosuggestions", required, " ")
            updated = 0
        }
        !updated && /^[[:space:]]*plugins=\([^)]*\)/ {
            open_pos = index($0, "(")
            remainder = substr($0, open_pos + 1)
            close_pos = index(remainder, ")")
            body = substr(remainder, 1, close_pos - 1)
            suffix = substr(remainder, close_pos + 1)
            count = split(body, existing, /[[:space:]]+/)
            for (i = 1; i <= count; i++) {
                if (existing[i] != "") seen[existing[i]] = 1
            }
            additions = ""
            for (i = 1; i <= required_count; i++) {
                if (!seen[required[i]]) additions = additions " " required[i]
            }
            print substr($0, 1, open_pos) body additions ")" suffix
            updated = 1
            next
        }
        { print }
        END {
            if (!updated) print "plugins=(git autojump zsh-syntax-highlighting zsh-autosuggestions)"
        }
    ' "$plugin_file" > "$plugin_tmp" || { rm -f "$plugin_tmp"; return 1; }
    mv "$plugin_tmp" "$plugin_file"
}

verify_zsh_checksum() {
    checksum_file=$1
    checksum_expected=$2
    if command -v sha256sum >/dev/null 2>&1; then
        checksum_actual=$(sha256sum "$checksum_file" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        checksum_actual=$(shasum -a 256 "$checksum_file" | awk '{print $1}')
    else
        return 1
    fi
    [ "$checksum_actual" = "$checksum_expected" ]
}

zsh_install_prefix() {
    case "$1" in
        */bin/zsh)
            zsh_prefix=${1%/bin/zsh}
            [ -n "$zsh_prefix" ] || return 1
            printf '%s\n' "$zsh_prefix"
            ;;
        *) return 1 ;;
    esac
}

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

is_interactive() {
    [ -t 0 ] && [ -t 1 ]
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
            *) warn "请输入 y 或 n。" ;;
        esac
    done
}

run_privileged() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        warn "需要 root 或 sudo 权限: $*"
        return 1
    fi
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

download_file() {
    download_url=$1
    download_output=$2
    curl --fail --location --silent --show-error \
        --retry 3 --connect-timeout 10 \
        -o "$download_output" "$download_url"
}

install_build_dependencies() {
    export NEEDRESTART_MODE=a
    if command -v dnf >/dev/null 2>&1; then
        run_privileged dnf install -y gcc ncurses-devel xz make curl git autojump util-linux-user
    elif command -v yum >/dev/null 2>&1; then
        run_privileged yum install -y gcc ncurses-devel xz make curl git autojump autojump-zsh
    elif command -v apt-get >/dev/null 2>&1; then
        run_privileged apt-get update
        run_privileged apt-get install -y gcc libncurses-dev make xz-utils curl git autojump
    else
        die "未找到受支持的包管理器（apt-get/dnf/yum）。"
    fi
}

parallel_jobs() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
    else
        getconf _NPROCESSORS_ONLN 2>/dev/null || printf '%s\n' "1"
    fi
}

install_zsh_source() {
    install_build_dependencies
    command -v curl >/dev/null 2>&1 || die "缺少 curl。"
    command -v tar >/dev/null 2>&1 || die "缺少 tar。"
    command -v make >/dev/null 2>&1 || die "缺少 make。"

    zsh_workdir=$(mktemp -d) || die "无法创建临时目录。"
    zsh_archive="$zsh_workdir/$ZSH_TAR"
    zsh_prefix=$(zsh_install_prefix "$INSTALL_PATH") || {
        rm -rf "$zsh_workdir"
        die "ZSH_INSTALL_PATH 必须采用 <prefix>/bin/zsh 形式。"
    }
    info ">>> 正在下载并校验 Zsh ${ZSH_VERSION}..."
    if ! download_file "$ZSH_URL" "$zsh_archive"; then
        rm -rf "$zsh_workdir"
        die "Zsh 源码下载失败。"
    fi
    if ! verify_zsh_checksum "$zsh_archive" "$ZSH_SHA256"; then
        rm -rf "$zsh_workdir"
        die "Zsh 源码 SHA256 校验失败。"
    fi

    tar -xJf "$zsh_archive" -C "$zsh_workdir" || {
        rm -rf "$zsh_workdir"; die "Zsh 源码解压失败。";
    }
    zsh_jobs=$(parallel_jobs)
    info ">>> 正在编译 Zsh ${ZSH_VERSION}..."
    (
        cd "$zsh_workdir/$ZSH_SRC_DIR" || exit 1
        ./configure --prefix="$zsh_prefix"
        make -j"$zsh_jobs"
        run_privileged make install
    ) || { rm -rf "$zsh_workdir"; die "Zsh 编译或安装失败。"; }
    rm -rf "$zsh_workdir"
}

register_shell() {
    grep -Fxq "$INSTALL_PATH" /etc/shells 2>/dev/null && return 0
    printf '%s\n' "$INSTALL_PATH" | run_privileged tee -a /etc/shells >/dev/null
}

choose_omz_action() {
    omz_choice=${OMZ_ACTION:-}
    if [ -n "$omz_choice" ]; then
        case "$omz_choice" in keep | update | reinstall) printf '%s\n' "$omz_choice"; return 0 ;; *) return 1 ;; esac
    fi
    if [ "${AUTO_SCRIPTS_NONINTERACTIVE:-0}" = "1" ] || ! is_interactive; then
        printf '%s\n' "keep"
        return 0
    fi
    while :; do
        printf '%s\n' "Oh My Zsh 已存在: 1) 保留  2) 更新  3) 备份后重装" >&2
        printf '%s' "选择 [1-3] (默认 1): " >&2
        IFS= read -r omz_choice || omz_choice=1
        omz_choice=${omz_choice:-1}
        case "$omz_choice" in
            1) printf '%s\n' "keep"; return 0 ;;
            2) printf '%s\n' "update"; return 0 ;;
            3) printf '%s\n' "reinstall"; return 0 ;;
            *) warn "请输入 1-3。" ;;
        esac
    done
}

choose_omz_source() {
    omz_source=${OMZ_SOURCE:-}
    if [ -n "$omz_source" ]; then
        case "$omz_source" in auto | github | gh-proxy | gitee) printf '%s\n' "$omz_source"; return 0 ;; *) return 1 ;; esac
    fi
    if [ "${AUTO_SCRIPTS_NONINTERACTIVE:-0}" = "1" ] || ! is_interactive; then
        printf '%s\n' "auto"
        return 0
    fi
    printf '%s' "请选择 Oh My Zsh 源 (1: 自动切换 [默认], 2: GitHub, 3: gh-proxy, 4: Gitee): " >&2
    IFS= read -r omz_source || omz_source=1
    case "${omz_source:-1}" in
        1) printf '%s\n' "auto" ;;
        2) printf '%s\n' "github" ;;
        3) printf '%s\n' "gh-proxy" ;;
        4) printf '%s\n' "gitee" ;;
        *) return 1 ;;
    esac
}

set_omz_source() {
    case "$1" in
        github)
            OMZ_INSTALL_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
            OMZ_REMOTE_URL="https://github.com/ohmyzsh/ohmyzsh.git"
            ;;
        gh-proxy)
            OMZ_INSTALL_URL="https://gh-proxy.org/https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
            OMZ_REMOTE_URL="https://gh-proxy.org/https://github.com/ohmyzsh/ohmyzsh.git"
            ;;
        gitee)
            OMZ_INSTALL_URL="https://gitee.com/pocmon/ohmyzsh/raw/master/tools/install.sh"
            OMZ_REMOTE_URL="https://gitee.com/pocmon/ohmyzsh.git"
            ;;
        *) return 1 ;;
    esac
}

install_oh_my_zsh_from_source() {
    install_omz_source=$1
    set_omz_source "$install_omz_source" || return 1
    install_omz_tmp=$(mktemp -d) || die "无法创建临时目录。"
    install_omz_script="$install_omz_tmp/install.sh"
    info ">>> 正在通过 ${install_omz_source} 安装 Oh My Zsh..."

    if ! download_file "$OMZ_INSTALL_URL" "$install_omz_script"; then
        rm -rf "$install_omz_tmp"
        warn "Oh My Zsh 安装脚本下载失败 (${install_omz_source})。"
        return 1
    fi
    if ! ZSH="$OMZ_DIR" REMOTE="$OMZ_REMOTE_URL" \
        RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
        sh "$install_omz_script" --unattended; then
        rm -rf "$install_omz_tmp"
        warn "Oh My Zsh 安装失败 (${install_omz_source})。"
        return 1
    fi
    rm -rf "$install_omz_tmp"
    OMZ_SOURCE_USED=$install_omz_source
}

install_oh_my_zsh() {
    install_omz_requested_source=$1
    OMZ_SOURCE_USED=
    if [ "$install_omz_requested_source" = "auto" ]; then
        for install_omz_candidate in github gh-proxy gitee; do
            if install_oh_my_zsh_from_source "$install_omz_candidate"; then
                return 0
            fi
            if [ -e "$OMZ_DIR" ]; then
                die "Oh My Zsh 安装失败后留下了目录 $OMZ_DIR；为避免覆盖数据，已停止自动切换。"
            fi
            warn "正在切换 Oh My Zsh 备用源..."
        done
        die "所有 Oh My Zsh 下载源均安装失败；可设置 OMZ_SOURCE=github、gh-proxy 或 gitee 后重试。"
    fi

    install_oh_my_zsh_from_source "$install_omz_requested_source" || \
        die "Oh My Zsh 安装失败 (${install_omz_requested_source})。"
}

detect_omz_source() {
    detect_omz_remote=$(git -C "$OMZ_DIR" remote get-url origin 2>/dev/null || true)
    case "$detect_omz_remote" in
        https://gh-proxy.org/*) printf '%s\n' "gh-proxy" ;;
        *gitee.com/*) printf '%s\n' "gitee" ;;
        *) printf '%s\n' "github" ;;
    esac
}

sync_plugin() {
    sync_name=$1
    sync_url=$2
    sync_dir=$3
    if [ -d "$sync_dir/.git" ]; then
        git -C "$sync_dir" pull --ff-only || die "插件更新失败: $sync_name"
    elif [ -e "$sync_dir" ]; then
        warn "插件路径已存在但不是 Git 仓库，跳过: $sync_dir"
    else
        git clone --depth 1 "$sync_url" "$sync_dir" || die "插件安装失败: $sync_name"
    fi
}

sync_zsh_plugins() {
    [ "${SYNC_ZSH_PLUGINS:-1}" = "1" ] || return 0
    command -v git >/dev/null 2>&1 || die "缺少 git，无法安装 Zsh 插件。"
    plugin_source=$1
    plugin_root="$OMZ_DIR/custom/plugins"
    mkdir -p "$plugin_root"
    case "$plugin_source" in
        github)
            syntax_url="https://github.com/zsh-users/zsh-syntax-highlighting.git"
            suggestions_url="https://github.com/zsh-users/zsh-autosuggestions.git"
            ;;
        gh-proxy)
            syntax_url="https://gh-proxy.org/https://github.com/zsh-users/zsh-syntax-highlighting.git"
            suggestions_url="https://gh-proxy.org/https://github.com/zsh-users/zsh-autosuggestions.git"
            ;;
        gitee)
            syntax_url="https://gitee.com/mirrors/zsh-syntax-highlighting.git"
            suggestions_url="https://gitee.com/mirrors/zsh-autosuggestions.git"
            ;;
        *) die "无效的 Oh My Zsh 插件源: $plugin_source" ;;
    esac
    sync_plugin "zsh-syntax-highlighting" "$syntax_url" \
        "$plugin_root/zsh-syntax-highlighting"
    sync_plugin "zsh-autosuggestions" "$suggestions_url" \
        "$plugin_root/zsh-autosuggestions"
}

ensure_autojump_setup() {
    autojump_file=$1
    grep -Fq '# >>> auto-scripts autojump >>>' "$autojump_file" && return 0
    cat >> "$autojump_file" <<'EOF'

# >>> auto-scripts autojump >>>
[[ -s /usr/share/autojump/autojump.sh ]] && . /usr/share/autojump/autojump.sh
[[ -s /etc/profile.d/autojump.sh ]] && . /etc/profile.d/autojump.sh
# <<< auto-scripts autojump <<<
EOF
}

configure_oh_my_zsh() {
    OMZ_DIR=${ZSH_OMZ_DIR:-$HOME/.oh-my-zsh}
    zshrc_file="$HOME/.zshrc"
    omz_action=install
    if [ -d "$OMZ_DIR" ]; then
        omz_action=$(choose_omz_action) || die "OMZ_ACTION 只能是 keep、update 或 reinstall。"
    fi
    omz_source=$(choose_omz_source) || die "OMZ_SOURCE 只能是 auto、github、gh-proxy 或 gitee。"

    case "$omz_action" in
        keep) info ">>> 保留现有 Oh My Zsh。" ;;
        update)
            git -C "$OMZ_DIR" pull --ff-only || die "Oh My Zsh 更新失败。"
            ;;
        reinstall)
            omz_stamp=$(date +%Y%m%d%H%M%S)
            mv "$OMZ_DIR" "${OMZ_DIR}.backup.$omz_stamp"
            if [ -f "$zshrc_file" ]; then
                cp "$zshrc_file" "${zshrc_file}.backup.$omz_stamp"
            fi
            install_oh_my_zsh "$omz_source"
            ;;
        install) install_oh_my_zsh "$omz_source" ;;
        *) die "未知的 Oh My Zsh 操作。" ;;
    esac

    if [ -n "${OMZ_SOURCE_USED:-}" ]; then
        omz_source=$OMZ_SOURCE_USED
    elif [ "$omz_source" = "auto" ] && [ "${SYNC_ZSH_PLUGINS:-1}" = "1" ]; then
        omz_source=$(detect_omz_source)
    fi
    sync_zsh_plugins "$omz_source"
    if [ -f "$zshrc_file" ]; then
        zshrc_backup="${zshrc_file}.backup.$(date +%Y%m%d%H%M%S)"
        cp "$zshrc_file" "$zshrc_backup"
        ensure_zsh_plugins "$zshrc_file"
        ensure_autojump_setup "$zshrc_file"
    else
        warn "未找到 $zshrc_file，跳过插件列表与 Autojump 配置。"
    fi
}

uninstall_zsh() {
    zsh_prefix=$(zsh_install_prefix "$INSTALL_PATH") || \
        die "ZSH_INSTALL_PATH 必须采用 <prefix>/bin/zsh 形式。"
    zsh_shells_file=${ZSH_SHELLS_FILE:-/etc/shells}

    info ">>> 开始卸载脚本安装的 Zsh。"
    warn ">>> 保留用户的 .zshrc；Oh My Zsh 默认保留，可用 ZSH_REMOVE_OMZ=1 一并删除。"

    if [ "${SHELL:-}" = "$INSTALL_PATH" ]; then
        if [ "${ZSH_FORCE_UNINSTALL:-0}" != "1" ]; then
            die "当前 Shell 正在使用 $INSTALL_PATH；请先切换到其他 Shell，或设置 ZSH_FORCE_UNINSTALL=1。"
        fi
        warn "当前 Shell 正在使用 $INSTALL_PATH，按 ZSH_FORCE_UNINSTALL=1 继续卸载。"
    fi

    if [ -f "$zsh_shells_file" ] && [ -r "$zsh_shells_file" ]; then
        zsh_shells_tmp=$(mktemp) || die "无法创建临时文件。"
        awk -v target="$INSTALL_PATH" '$0 != target { print }' \
            "$zsh_shells_file" > "$zsh_shells_tmp" || {
            rm -f "$zsh_shells_tmp"
            die "无法更新 $zsh_shells_file。"
        }
        run_privileged install -m 0644 "$zsh_shells_tmp" "$zsh_shells_file" || {
            rm -f "$zsh_shells_tmp"
            die "无法从 $zsh_shells_file 移除 $INSTALL_PATH。"
        }
        rm -f "$zsh_shells_tmp"
    fi

    run_privileged rm -f "$INSTALL_PATH" || die "无法删除 $INSTALL_PATH。"
    run_privileged rm -rf "$zsh_prefix/lib/zsh" "$zsh_prefix/share/zsh" || \
        die "无法删除 Zsh 运行时目录。"

    for zsh_man_name in \
        zsh.1 zshall.1 zshbuiltins.1 zshcalsys.1 zshcompctl.1 \
        zshcompsys.1 zshcompwid.1 zshcontrib.1 zshexpn.1 zshmisc.1 \
        zshmodules.1 zshparam.1 zshroadmap.1 zshzle.1; do
        run_privileged rm -f "$zsh_prefix/share/man/man1/$zsh_man_name" || \
            warn "无法删除手册页: $zsh_man_name"
    done

    if [ "${ZSH_REMOVE_OMZ:-0}" = "1" ]; then
        uninstall_omz_dir=${ZSH_OMZ_DIR:-$HOME/.oh-my-zsh}
        if [ -d "$uninstall_omz_dir" ]; then
            run_privileged rm -rf "$uninstall_omz_dir" || \
                die "无法删除 Oh My Zsh: $uninstall_omz_dir"
            info ">>> 已删除 Oh My Zsh: $uninstall_omz_dir"
        fi
    fi

    info ">>> Zsh 卸载流程完成；未删除 .zshrc。"
}

main() {
    info ">>> 环境检测启动..."
    [ "$(uname -s)" = "Linux" ] || die "Zsh 自动安装当前仅支持 Linux。"

    case "${1:-}" in
        uninstall | --uninstall) ZSH_UNINSTALL=1 ;;
    esac
    if [ "${ZSH_UNINSTALL:-0}" = "1" ] || [ "${ACTION:-}" = "uninstall" ]; then
        uninstall_zsh
        return 0
    fi

    zsh_needs_install=1
    if [ -x "$INSTALL_PATH" ]; then
        current_zsh=$($INSTALL_PATH --version 2>/dev/null || printf '%s' "未知版本")
        info ">>> 检测到 $INSTALL_PATH: $current_zsh"
        zsh_reinstall=${ZSH_REINSTALL:-}
        if [ -z "$zsh_reinstall" ]; then
            if ask_user "是否重新编译安装 Zsh ${ZSH_VERSION}?" "n"; then
                zsh_reinstall=1
            else
                zsh_reinstall=0
            fi
        fi
        case "$zsh_reinstall" in
            0) zsh_needs_install=0 ;;
            1) ;;
            *) die "ZSH_REINSTALL 只能是 0 或 1。" ;;
        esac
    fi

    if [ "$zsh_needs_install" -eq 1 ]; then
        install_zsh_source
        register_shell || die "无法将 $INSTALL_PATH 写入 /etc/shells。"
    else
        info ">>> 保留现有 Zsh，跳过源码编译。"
    fi

    change_shell=${CHANGE_DEFAULT_SHELL:-}
    if [ -z "$change_shell" ]; then
        if [ "${AUTO_SCRIPTS_NONINTERACTIVE:-0}" = "1" ] || ! is_interactive; then
            change_shell=0
        elif ask_user "是否将 $INSTALL_PATH 设为默认 Shell?" "y"; then
            change_shell=1
        else
            change_shell=0
        fi
    fi
    case "$change_shell" in
        1) run_privileged chsh -s "$INSTALL_PATH" "$(target_user)" ;;
        0) ;;
        *) die "CHANGE_DEFAULT_SHELL 只能是 0 或 1。" ;;
    esac

    configure_oh_my_zsh

    printf '\n%b\n' "${GREEN}===========================================${NC}"
    "$INSTALL_PATH" --version
    info ">>> Zsh/Oh My Zsh 配置完成。"
    printf '%b\n' "${CYAN}使用以下命令启动新环境: exec ${INSTALL_PATH} -l${NC}"
    printf '%b\n' "${GREEN}===========================================${NC}"
}

# 测试只加载函数，不执行安装流程。
if [ "${AUTO_SCRIPTS_LIBRARY:-0}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi

main "$@"
