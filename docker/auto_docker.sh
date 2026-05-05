#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}>>> 正在启动 Docker 自动化安装程序...${NC}"

# 1. 卸载旧版本
echo -e "${YELLOW}>>> 正在清理可能存在的旧版本组件...${NC}"
if command -v apt-get &> /dev/null; then
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc docker-ce docker-ce-cli; do 
        sudo apt-get remove -y $pkg &>/dev/null
    done
elif command -v dnf &> /dev/null; then
    sudo dnf remove -y docker docker-client docker-client-latest docker-common docker-latest \
                docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux \
                docker-engine docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin &>/dev/null
elif command -v yum &> /dev/null; then
    sudo yum remove -y docker docker-client docker-client-latest docker-common docker-latest \
                docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux \
                docker-engine docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin &>/dev/null
fi

# 2. 安装 Docker 核心引擎
echo -e "${CYAN}-------------------------------------------------------${NC}"
echo -e "请选择 Docker 安装源:"
echo "1) 官方脚本 + 阿里云镜像加速 (推荐)"
echo "2) 官方脚本 + 清华大学镜像加速 (Ubuntu/Debian 推荐)"
echo "3) 官方脚本 (直连下载，不使用镜像)"
echo "4) 跳过安装 Docker 引擎 (仅配置或装 Compose)"
read -p "请输入数字 [1-4]: " DOCKER_SOURCE
echo -e "${CYAN}-------------------------------------------------------${NC}"

case $DOCKER_SOURCE in
    1)
        curl -fsSL get.docker.com -o get-docker.sh
        sudo sh get-docker.sh --mirror Aliyun
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

# 3. 基础配置
if command -v docker &> /dev/null; then
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo groupadd -f docker
    sudo usermod -aG docker $USER
fi

# 4. 配置 Daemon.json
echo -e "${GREEN}>>> 配置镜像加速器及日志限制...${NC}"
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.1panel.live",
    "https://registry.dockermirror.com",
    "https://docker.m.daocloud.io"
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

# 5. 智能检测 Docker Compose
echo -e "\n${CYAN}>>> 正在检测 Compose 状态...${NC}"
HAS_PLUGIN=false
if docker compose version &>/dev/null; then
    echo -e "${GREEN}检测到 Docker 已自带 Compose V2 插件 (命令: docker compose)${NC}"
    HAS_PLUGIN=true
fi

INSTALL_V1=false
if [ "$HAS_PLUGIN" = true ]; then
    read -p "是否仍需安装独立二进制版 docker-compose (兼容带横杠命令)? (y/N): " REQ_V1
    [[ "$REQ_V1" =~ ^[Yy]$ ]] && INSTALL_V1=true
else
    echo -e "${YELLOW}未检测到 Compose 插件，建议安装。${NC}"
    INSTALL_V1=true
fi

if [ "$INSTALL_V1" = true ]; then
    DEFAULT_COMPOSE="v2.26.1"
    echo -e "${YELLOW}最新版查看: https://github.com/docker/compose/releases${NC}"
    read -p "请输入版本号 (默认 $DEFAULT_COMPOSE): " COMPOSE_VERSION
    COMPOSE_VERSION=${COMPOSE_VERSION:-$DEFAULT_COMPOSE}
    
    echo -e "选择下载代理: 1) ghproxy.cn  2) mirror.ghproxy.com  3) GitHub"
    read -p "选择 [1-3]: " P_CHOICE
    URL="https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)"
    case $P_CHOICE in
        1) DURL="https://ghproxy.cn/$URL" ;;
        2) DURL="https://mirror.ghproxy.com/$URL" ;;
        *) DURL="$URL" ;;
    esac
    sudo curl -L "$DURL" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
else
    echo -e "${GREEN}使用 Docker 自带 Compose 插件，跳过额外安装。${NC}"
fi

# 6. 验证与自动激活组权限
echo -e "\n${GREEN}===========================================${NC}"
docker --version 2>/dev/null
docker-compose --version 2>/dev/null
echo -e "${GREEN}>>> 安装成功！${NC}"
echo -e "${YELLOW}>>> 脚本即将执行 'newgrp docker' 自动激活免 sudo 权限... 如失败，请手动重试${NC}"
echo -e "${YELLOW}>>> 激活后您将进入新的 Shell，直接输入 'docker ps' 测试即可。${NC}"
echo -e "${GREEN}===========================================${NC}"

# 关键：执行权限切换，这必须是脚本的最后一行代码
exec newgrp docker