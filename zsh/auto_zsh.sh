#!/bin/bash

# =================================================================
# 脚本名称: auto_zsh.sh
# 功能: 自动化源码编译安装 Zsh 5.9, Oh My Zsh, 插件及 Autojump
# 支持系统: Ubuntu (apt) / CentOS (yum/dnf)
# =================================================================

# 基础配置
ZSH_VERSION="5.9"
ZSH_TAR="zsh-$ZSH_VERSION.tar.xz"
ZSH_URL="https://sourceforge.net/projects/zsh/files/zsh/$ZSH_VERSION/$ZSH_TAR/download"
ZSH_SRC_DIR="zsh-$ZSH_VERSION"
INSTALL_PATH="/usr/local/bin/zsh"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 解决 Ubuntu 交互弹窗卡顿
export NEEDRESTART_MODE=a

# 交互函数
ask_user() {
    local prompt="$1"
    local default="$2"
    read -t 15 -p "$(echo -e "${YELLOW}$prompt (y/n, 默认 $default): ${NC}")" res
    res=${res:-$default}
    [[ "$res" =~ ^[Yy]$ ]] && return 0 || return 1
}

echo -e "${GREEN}>>> 环境检测启动...${NC}"

# --- 1. Zsh 源码安装/清理逻辑 ---
ZSH_INSTALLED=false
if [[ -x "$INSTALL_PATH" ]]; then
    CURRENT_V=$($INSTALL_PATH --version | awk '{print $2}')
    echo -e "${YELLOW}检测到 Zsh 已安装在 $INSTALL_PATH (版本 $CURRENT_V)${NC}"
    
    if ask_user "是否先卸载清理并重新安装 Zsh $ZSH_VERSION?" "n"; then
        echo -e "${RED}>>> 正在执行深度清理...${NC}"
        # 尝试通过源码卸载
        if [ -d "$ZSH_SRC_DIR" ]; then
            (cd "$ZSH_SRC_DIR" && sudo make uninstall &>/dev/null)
        fi
        # 暴力清理残留
        sudo rm -f /usr/local/bin/zsh*
        sudo rm -rf /usr/local/share/zsh
        # 从 /etc/shells 中安全删除
        sudo sed -i "\|${INSTALL_PATH}|d" /etc/shells
    else
        ZSH_INSTALLED=true
    fi
fi

if [ "$ZSH_INSTALLED" = false ]; then
    echo -e "${GREEN}>>> 正在安装编译依赖及工具...${NC}"
    if command -v dnf &> /dev/null; then
        sudo dnf install -y epel-release
        sudo dnf install -y gcc perl-ExtUtils-MakeMaker ncurses-devel wget xz make git autojump util-linux-user
    elif command -v yum &> /dev/null; then
        sudo yum install -y epel-release
        sudo yum install -y gcc perl-ExtUtils-MakeMaker ncurses-devel wget xz make git autojump autojump-zsh
    elif command -v apt &> /dev/null; then
        sudo apt update
        sudo apt install -y gcc libncurses-dev make wget xz-utils curl git autojump
    fi

    # 源码下载
    echo -e "${GREEN}>>> 正在下载 Zsh $ZSH_VERSION 源码...${NC}"
    [ -f "$ZSH_TAR" ] && rm "$ZSH_TAR"
    wget -O "$ZSH_TAR" "$ZSH_URL"
    
    [ -d "$ZSH_SRC_DIR" ] && rm -rf "$ZSH_SRC_DIR"
    tar -xvf "$ZSH_TAR"
    
    # 编译与安装
    echo -e "${GREEN}>>> 开始配置与并行编译...${NC}"
    cd "$ZSH_SRC_DIR" || exit
    ./configure
    make -j$(nproc)
    sudo make install
    
    # 注册 Shell
    if ! grep -q "$INSTALL_PATH" /etc/shells; then
        echo "$INSTALL_PATH" | sudo tee -a /etc/shells
    fi
    
    echo -e "${GREEN}>>> 正在切换默认 Shell...${NC}"
    sudo chsh -s "$INSTALL_PATH" "$USER"
    cd ..
    
    if ask_user "是否清理临时下载的源码文件?" "y"; then
        rm -rf "$ZSH_SRC_DIR" "$ZSH_TAR"
    fi
else
    echo -e "${GREEN}跳过 Zsh 源码安装阶段。${NC}"
fi

# --- 2. Oh My Zsh 安装/清理逻辑 ---
OMZ_DIR="$HOME/.oh-my-zsh"
INSTALL_OMZ=true

if [ -d "$OMZ_DIR" ]; then
    echo -e "${YELLOW}检测到 Oh My Zsh 目录已存在。${NC}"
    if ask_user "是否彻底重置并重新安装 Oh My Zsh (会备份旧的 .zshrc)?" "n"; then
        echo -e "${RED}>>> 正在清理旧环境...${NC}"
        rm -rf "$OMZ_DIR"
        [ -f "$HOME/.zshrc" ] && mv "$HOME/.zshrc" "$HOME/.zshrc.bak_$(date +%s)"
    else
        INSTALL_OMZ=false
    fi
fi

if [ "$INSTALL_OMZ" = true ]; then
    echo -e "${GREEN}请选择源 (1: GitHub [默认], 2: Gitee): ${NC}"
    read -t 15 -p "请输入数字 [1/2]: " SOURCE_CHOICE
    SOURCE_CHOICE=${SOURCE_CHOICE:-1}

    if [ "$SOURCE_CHOICE" == "2" ]; then
        echo -e "${GREEN}>>> 正在通过 Gitee 源安装...${NC}"
        export REMOTE="https://gitee.com/pocmon/ohmyzsh.git"
        sh -c "$(curl -fsSL https://gitee.com/pocmon/ohmyzsh/raw/master/tools/install.sh)" "" --unattended
        git clone https://gitee.com/mirrors/zsh-syntax-highlighting.git ${OMZ_DIR}/custom/plugins/zsh-syntax-highlighting
        git clone https://gitee.com/mirrors/zsh-autosuggestions.git ${OMZ_DIR}/custom/plugins/zsh-autosuggestions
    else
        echo -e "${GREEN}>>> 正在通过 GitHub 源安装...${NC}"
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${OMZ_DIR}/custom/plugins/zsh-syntax-highlighting
        git clone https://github.com/zsh-users/zsh-autosuggestions ${OMZ_DIR}/custom/plugins/zsh-autosuggestions
    fi

    # 写入配置
    if [ -f "$HOME/.zshrc" ]; then
        # 替换插件列表
        sed -i 's/plugins=(git)/plugins=(git autojump zsh-syntax-highlighting zsh-autosuggestions)/' "$HOME/.zshrc"
        
        # 写入 Autojump 加载脚本 (防重复写入)
        if ! grep -q "autojump.sh" "$HOME/.zshrc"; then
            cat >> "$HOME/.zshrc" << 'EOF'

# Autojump setup
[[ -s /usr/share/autojump/autojump.sh ]] && . /usr/share/autojump/autojump.sh
[[ -s /etc/profile.d/autojump.sh ]] && . /etc/profile.d/autojump.sh
EOF
        fi
    fi
else
    echo -e "${GREEN}跳过 Oh My Zsh 流程。${NC}"
fi

echo -e "\n${GREEN}===========================================${NC}"
echo -e "${GREEN}>>> 安装/配置流程全部结束！${NC}"
echo -e "${YELLOW}请运行以下命令激活环境('可选'):${NC}"
echo -e "${CYAN}exec $INSTALL_PATH -l${NC}"
echo -e "${GREEN}===========================================${NC}"