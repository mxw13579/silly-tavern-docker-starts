#!/bin/bash
# Docker 管理模块

source "$(dirname "$0")/common.sh"

install_docker() {
    if command -v docker &> /dev/null; then
        msg_warn "Docker 已安装，无需重复操作。"
        return
    fi
    check_sudo
    msg_info "开始安装 Docker..."

    # 预先更新包列表
    if [ "$PKG_MANAGER" == "apt-get" ]; then sudo apt-get update; fi

    case $OS in
        debian|ubuntu)
            DOCKER_REPO_URL="https://download.docker.com"
            [ "$USE_CHINA_MIRROR" = true ] && DOCKER_REPO_URL="https://mirrors.aliyun.com/docker-ce"
            sudo $PKG_MANAGER install -y apt-transport-https ca-certificates curl gnupg lsb-release
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL "${DOCKER_REPO_URL}/linux/${OS}/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            sudo chmod a+r /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] ${DOCKER_REPO_URL}/linux/${OS} $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo $PKG_MANAGER update
            sudo $PKG_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        centos|rhel|fedora)
            sudo $PKG_MANAGER install -y ${PKG_MANAGER}-utils
            REPO_URL="https://download.docker.com/linux/centos/docker-ce.repo"
            if [ "$USE_CHINA_MIRROR" = true ]; then
                REPO_URL="http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo"
            fi
            sudo ${PKG_MANAGER}-config-manager --add-repo $REPO_URL
            sudo $PKG_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        *)
            msg_error "对于 $OS, 暂不支持自动安装 Docker，请手动安装。"
            return 1
            ;;
    esac

    if ! command -v docker &>/dev/null; then
        msg_error "Docker 安装失败。"
        exit 1
    fi
    msg_ok "Docker 安装成功。"
    sudo systemctl start docker && sudo systemctl enable docker
    msg_info "Docker 服务已启动并设置为开机自启。"

    # 安装后自动配置镜像
    config_docker_mirror
    # 重新检测docker-compose命令
    setup_docker_compose_cmd
}

config_docker_mirror() {
    check_sudo
    if [ "$USE_CHINA_MIRROR" = false ]; then
        msg_warn "非中国大陆服务器，跳过Docker镜像加速配置。"
        return
    fi
    msg_info "正在配置 Docker 国内镜像加速器..."
    sudo mkdir -p /etc/docker
    sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": [
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com",
    "https://registry.docker-cn.com"
  ]
}
EOF
    msg_info "重启Docker服务以应用配置..."
    restart_docker_service
    msg_ok "Docker 镜像加速器配置完成。"
}

restart_docker_service() {
    check_sudo
    if command -v docker &>/dev/null; then
        msg_info "正在重启 Docker 服务..."
        sudo systemctl daemon-reload
        sudo systemctl restart docker
        msg_ok "Docker 服务已重启。"
    else
        msg_error "Docker 未安装，无法重启。"
    fi
}

list_docker_images() {
    check_sudo
    if command -v docker &>/dev/null; then
        msg_info "当前已下载的 Docker 镜像列表:"
        sudo docker images
    else
        msg_error "Docker 未安装，无法查看镜像。"
    fi
}

status_docker() {
    echo -n "   Docker 环境: "
    if command -v docker &> /dev/null; then
        if systemctl is-active --quiet docker; then
            local ver=$(docker -v | awk '{print $3}' | sed 's/,//')
            echo -e "${C_GREEN}已安装 (v${ver}) 且正在运行${C_RESET}"
        else
            echo -e "${C_YELLOW}已安装但未运行${C_RESET}"
        fi
        if [ "$USE_CHINA_MIRROR" = true ]; then
            if [ -f /etc/docker/daemon.json ] && grep -q "registry-mirrors" /etc/docker/daemon.json; then
                 echo "     └─ 镜像加速: ${C_GREEN}已配置${C_RESET}"
            else
                 echo "     └─ 镜像加速: ${C_YELLOW}未配置${C_RESET}"
            fi
        fi
    else
        echo -e "${C_RED}未安装${C_RESET}"
    fi
}


case "$1" in
    install) install_docker ;;
    config_mirror) config_docker_mirror ;;
    restart_service) restart_docker_service ;;
    list_images) list_docker_images ;;
    status) status_docker ;;
    *) msg_error "用法: $0 {install|config_mirror|restart_service|list_images|status}" ;;
esac
