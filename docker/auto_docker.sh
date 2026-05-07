#!/bin/bash

# =================================================================
# 脚本名称: auto_docker.sh
# 功能: 自动化安装 Docker 引擎、配置镜像加速、安装 Docker Compose
# 支持系统: Ubuntu (apt) / CentOS (yum/dnf)
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

# 交互函数
ask_user() {
    local prompt="$1"
    local default="$2"
    if ! is_interactive; then
        echo -e "${YELLOW}非交互环境，默认选择: $default${NC}"
        [[ "$default" =~ ^[Yy]$ ]] && return 0 || return 1
    fi
    read -t 15 -p "$(echo -e "${YELLOW}$prompt (y/n, 默认 $default): ${NC}")" res
    res=${res:-$default}
    [[ "$res" =~ ^[Yy]$ ]] && return 0 || return 1
}

echo -e "${GREEN}>>> 正在启动 Docker 自动化安装程序...${NC}"

# 1. 选择安装方式
DOCKER_INSTALLED=false
echo -e "${CYAN}-------------------------------------------------------${NC}"
echo -e "请选择 Docker 安装源:"
echo "1) 官方脚本 + 阿里云镜像加速 (推荐)"
echo "2) 官方脚本 + 清华大学镜像加速 (Ubuntu/Debian 推荐)"
echo "3) 官方脚本 (直连下载，不使用镜像)"
echo "4) 跳过安装 Docker 引擎 (仅配置或装 Compose)"
read -t 15 -p "请输入数字 [1-4]: " DOCKER_SOURCE
echo -e "${CYAN}-------------------------------------------------------${NC}"

# 2. 安装前检测旧版本并询问清理 (仅在选择安装时)
if [ "$DOCKER_SOURCE" != "4" ]; then
    OLD_PKGS=()
    if command -v docker &> /dev/null; then
        OLD_VER=$(docker --version 2>/dev/null || echo "未知版本")
        echo -e "${YELLOW}检测到已安装 Docker: $OLD_VER${NC}"
        OLD_PKGS+=("docker")
    fi
    if command -v docker-compose &> /dev/null; then
        COMPOSE_VER=$(docker-compose --version 2>/dev/null || echo "未知版本")
        echo -e "${YELLOW}检测到已安装 docker-compose: $COMPOSE_VER${NC}"
        OLD_PKGS+=("docker-compose")
    fi

    if [ ${#OLD_PKGS[@]} -gt 0 ]; then
        echo -e "${YELLOW}将清理以下旧组件: ${OLD_PKGS[*]}${NC}"
        if ask_user "是否卸载旧版本并重新安装?" "n"; then
            echo -e "${RED}>>> 正在清理旧版本组件...${NC}"
            if command -v apt-get &> /dev/null; then
                for pkg in docker.io docker-doc docker-compose podman-docker containerd runc docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin; do
                    sudo apt-get remove -y $pkg &>/dev/null || true
                done
                sudo apt-get autoremove -y &>/dev/null || true
            elif command -v dnf &> /dev/null; then
                sudo dnf remove -y docker docker-client docker-client-latest docker-common docker-latest \
                            docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux \
                            docker-engine docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin &>/dev/null || true
            elif command -v yum &> /dev/null; then
                sudo yum remove -y docker docker-client docker-client-latest docker-common docker-latest \
                            docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux \
                            docker-engine docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin &>/dev/null || true
            fi
            echo -e "${GREEN}旧版本清理完成。${NC}"
        else
            echo -e "${GREEN}跳过卸载，保留现有版本。${NC}"
        fi
    else
        echo -e "${GREEN}未检测到已安装的 Docker 组件。${NC}"
    fi
fi

# 3. 执行安装
case $DOCKER_SOURCE in
    1)
        curl -fsSL get.docker.com -o get-docker.sh && sudo sh get-docker.sh --mirror Aliyun
        rm -f get-docker.sh
        ;;
    2)
        export DOWNLOAD_URL="https://mirrors.tuna.tsinghua.edu.cn/docker-ce"
        curl -fsSL https://get.docker.com/ | sh
        ;;
    3)
        curl -fsSL https://get.docker.com/ | sh
        ;;
    *)
        echo -e "${YELLOW}>>> 跳过 Docker 引擎安装。${NC}"
        ;;
esac

# 4. 基础配置 + Daemon.json (验证 Docker 是否真正安装成功)
if command -v docker &> /dev/null; then
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo groupadd -f docker
    sudo usermod -aG docker $USER

    echo -e "${GREEN}>>> 配置镜像加速器及日志限制...${NC}"
    sudo mkdir -p /etc/docker
    sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.1panel.live",
    "https://docker.m.daocloud.io",
    "https://mirror.ccs.tencentyun.com"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  }
}
EOF

    sudo systemctl daemon-reload
    sudo systemctl restart docker
    echo -e "${GREEN}Docker 安装及配置完成。${NC}"
else
    echo -e "${YELLOW}跳过 Docker 安装，不执行基础配置和镜像加速。${NC}"
fi

# 5. 智能检测 Docker Compose
echo -e "\n${CYAN}>>> 正在检测 Compose 状态...${NC}"
HAS_PLUGIN=false
if docker compose version &>/dev/null; then
    echo -e "${GREEN}检测到 Docker 已自带 Compose V2 插件 (命令: docker compose)${NC}"
    HAS_PLUGIN=true
fi

INSTALL_V1=false
if [ "$HAS_PLUGIN" = true ]; then
    if ask_user "是否仍需安装独立二进制版 docker-compose (兼容带横杠命令)?" "n"; then
        INSTALL_V1=true
    fi
else
    echo -e "${YELLOW}未检测到 Compose 插件，建议安装。${NC}"
    INSTALL_V1=true
fi

if [ "$INSTALL_V1" = true ]; then
    # 检测是否已存在独立版 docker-compose
    if [ -f /usr/local/bin/docker-compose ]; then
        EXIST_VER=$(/usr/local/bin/docker-compose --version 2>/dev/null || echo "未知版本")
        echo -e "${YELLOW}检测到已安装独立版: $EXIST_VER${NC}"
        if ! ask_user "是否覆盖重新安装?" "n"; then
            echo -e "${GREEN}跳过 Compose 安装。${NC}"
            INSTALL_V1=false
        fi
    fi
fi

if [ "$INSTALL_V1" = true ]; then
    PLATFORM="$(uname -s)-$(uname -m)"

    echo -e "${CYAN}-------------------------------------------------------${NC}"
    echo "选择下载源:"
    echo "  1) GitHub 直连 (latest)"
    echo "  2) GitHub CDN 加速 (download.githubcdn.com)"
    read -t 15 -p "选择 [1-2]: " P_CHOICE
    echo -e "${CYAN}-------------------------------------------------------${NC}"

    case $P_CHOICE in
        1) DURL="https://github.com/docker/compose/releases/latest/download/docker-compose-$PLATFORM" ;;
        *)
            GITHUB_URL="https://github.com/docker/compose/releases/download/v5.1.3/docker-compose-$PLATFORM"
            ENCODED_URL=$(echo "$GITHUB_URL" | sed 's|/|%2F|g')
            DURL="https://download.githubcdn.com/?url=$ENCODED_URL"
            echo -e "${YELLOW}使用 CDN 加速下载: $DURL${NC}"
            ;;
    esac

    echo -e "${GREEN}>>> 正在下载 Docker Compose (latest)...${NC}"
    sudo curl -L "$DURL" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    echo -e "${GREEN}Docker-Compose 安装完成。${NC}"
else
    echo -e "${GREEN}使用 Docker 自带 Compose 插件，跳过额外安装。${NC}"
fi

# 6. 验证与自动激活组权限
echo -e "\n${GREEN}===========================================${NC}"
docker --version 2>/dev/null
docker-compose --version 2>/dev/null || docker compose version 2>/dev/null
echo -e "${GREEN}>>> 安装成功！${NC}"
echo -e "${YELLOW}>>> 脚本即将执行 'newgrp docker' 自动激活免 sudo 权限... 如失败，请手动重试${NC}"
echo -e "${YELLOW}>>> 激活后您将进入新的 Shell，直接输入 'docker ps' 测试即可。${NC}"
echo -e "${GREEN}===========================================${NC}"

# 关键：执行权限切换，这必须是脚本的最后一行代码
exec newgrp docker