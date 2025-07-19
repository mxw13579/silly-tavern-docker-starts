#!/bin/bash
# SillyTavern 应用管理模块

# 设置工作目录并引入通用脚本
cd "$(dirname "$0")"
source ./common.sh


# 检查Docker环境是否就绪
check_docker_env() {
    if ! command -v docker &> /dev/null; then
        msg_error "Docker 未安装。请先从主菜单选择 '2. Docker 环境管理' -> '1. 安装 Docker'。"
        return 1
    fi
    if [ -z "$DOCKER_COMPOSE_CMD" ]; then
        msg_error "docker-compose 或 docker compose 插件未安装。请先安装 Docker。"
        return 1
    fi
    return 0
}

# 生成 docker-compose.yaml 文件
generate_compose_file() {
    msg_info "正在生成 docker-compose.yaml 文件..."
    SILLYTAVERN_IMAGE="ghcr.io/sillytavern/sillytavern:latest"
    WATCHTOWER_IMAGE="containrrr/watchtower"

    if [ "$USE_CHINA_MIRROR" = true ]; then
        msg_info "检测到在中国，将使用南京大学镜像站加速..."
        SILLYTAVERN_IMAGE="ghcr.nju.edu.cn/sillytavern/sillytavern:latest"
        WATCHTOWER_IMAGE="ghcr.nju.edu.cn/containrrr/watchtower"
    fi

    sudo mkdir -p "$ST_PATH"
    sudo tee "$ST_COMPOSE_FILE" > /dev/null <<EOF
services:
  sillytavern:
    image: ${SILLYTAVERN_IMAGE}
    container_name: sillytavern
    ports:
      - "8000:8000"
    volumes:
      - ./config:/home/node/app/config:rw
      - ./data:/home/node/app/data:rw
      - ./extensions:/home/node/app/public/scripts/extensions/third-party:rw
    restart: always
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
  watchtower:
    image: ${WATCHTOWER_IMAGE}
    container_name: watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --interval 86400 --cleanup --label-enable
    restart: always
networks:
  default:
    name: sillytavern_net
EOF
    msg_ok "docker-compose.yaml 文件已生成。"
}

# 生成完整的 config.yaml 文件
generate_full_config_file() {
    local username=$1
    local password=$2
    local listen_mode=$3

    msg_info "正在生成完整的 config.yaml 配置文件..."
    sudo mkdir -p "${ST_PATH}/config"

=
    sudo tee "${ST_CONFIG_FILE}" > /dev/null <<EOF
# 由SillyTavern工具箱生成的完整配置文件
dataRoot: ./data
cardsCacheCapacity: 100
listen: ${listen_mode}
protocol:
  ipv4: true
  ipv6: false
dnsPreferIPv6: false
autorunHostname: auto
port: 8000
autorunPortOverride: -1
whitelistMode: false
enableForwardedWhitelist: true
whitelist:
  - ::1
  - 127.0.0.1
  - 0.0.0.0
basicAuthMode: ${listen_mode}
basicAuthUser:
  username: ${username}
  password: ${password}
enableCorsProxy: false
requestProxy:
  enabled: false
  url: socks5://username:password@example.com:1080
  bypass:
    - localhost
    - 127.0.0.1
enableUserAccounts: false
enableDiscreetLogin: false
autheliaAuth: false
perUserBasicAuth: false
sessionTimeout: 86400
cookieSecret: 6XgkD9H+Foh+h9jVCbx7bEumyZuYtc5RVzKMEc+ORjDGOAvfWVjfPGyRmbFSVPjdy8ofG3faMe8jDf+miei0yQ==
disableCsrfProtection: false
securityOverride: false
autorun: true
avoidLocalhost: false
backups:
  common:
    numberOfBackups: 50
  chat:
    enabled: true
    maxTotalBackups: -1
    throttleInterval: 10000
thumbnails:
  enabled: true
  format: jpg
  quality: 95
  dimensions:
    bg:
      - 160
      - 90
    avatar:
      - 96
      - 144
allowKeysExposure: false
skipContentCheck: false
whitelistImportDomains:
  - localhost
  - cdn.discordapp.com
  - files.catbox.moe
  - raw.githubusercontent.com
requestOverrides: []
enableExtensions: true
enableExtensionsAutoUpdate: true
enableDownloadableTokenizers: true
extras:
  disableAutoDownload: false
  classificationModel: Cohee/distilbert-base-uncased-go-emotions-onnx
  captioningModel: Xenova/vit-gpt2-image-captioning
  embeddingModel: Cohee/jina-embeddings-v2-base-en
  speechToTextModel: Xenova/whisper-small
  textToSpeechModel: Xenova/speecht5_tts
promptPlaceholder: "[Start a new chat]"
openai:
  randomizeUserId: false
  captionSystemPrompt: ""
deepl:
  formality: default
mistral:
  enablePrefix: false
ollama:
  keepAlive: -1
claude:
  enableSystemPromptCache: false
  cachingAtDepth: -1
enableServerPlugins: false
EOF
    msg_ok "完整的 config.yaml 文件已生成。"
}

# 交互式配置访问权限
configure_access() {
    local username password

    echo
    msg_info "现在来设置访问权限。"
    msg_warn "强烈建议您开启外网访问并设置一个强密码，否则酒馆可能不安全或无法从外部访问。"

    local enable_external_access
    while true; do
        read -p "是否要设置用户名和密码来开启外网访问？(y/n): " -r response </dev/tty
        case $response in
            [Yy]*) enable_external_access="y"; break ;;
            [Nn]*) enable_external_access="n"; break ;;
            *) msg_error "请输入 y 或 n" ;;
        esac
    done

    if [[ $enable_external_access == "y" ]]; then
        while true; do
            read -p "请输入您的用户名 (例如: admin, 不能是纯数字): " -r username </dev/tty
            if [[ "$username" =~ ^[0-9]+$ ]]; then
                msg_error "出于安全考虑，用户名不能是纯数字，请重新输入。"
            elif [ -z "$username" ]; then
                 msg_error "用户名不能为空，请重新输入。"
            else
                break
            fi
        done

        while true; do
            read -p "请输入您的密码 (请使用复杂密码): " -r password </dev/tty
             if [ -z "$password" ]; then
                 msg_error "密码不能为空，请重新输入。"
            else
                break
            fi
        done

        generate_full_config_file "$username" "$password" "true"
        msg_ok "已开启外网访问，并设置用户名为: $username"
        msg_warn "请务必牢记您的密码！如果忘记，请回到菜单选择 '8. 修改/设置...密码'。"
    else
        # 如果不开启外网访问，生成一个只在本地监听且不启用认证的配置
        generate_full_config_file "user" "password" "false"
        msg_info "已配置为仅本地访问，并禁用了密码认证。"
    fi
}

# --- 主功能实现 ---

install_st() {
    check_sudo
    if ! check_docker_env; then return 1; fi
    if [ -f "$ST_COMPOSE_FILE" ]; then
        msg_warn "检测到 SillyTavern 已安装。如果想重新安装，请先手动删除整个目录: ${C_YELLOW}${ST_PATH}${C_RESET}"
        return
    fi

    msg_info "开始全新安装 SillyTavern..."
    generate_compose_file
    configure_access

    msg_info "正在拉取最新镜像，请稍候... (此过程可能需要几分钟)"
    if sudo $DOCKER_COMPOSE_CMD -f "$ST_COMPOSE_FILE" pull; then
        msg_ok "镜像拉取成功。"
        start_st
    else
        msg_error "镜像拉取失败。请检查网络或镜像地址。您可能需要先配置Docker镜像加速器(主菜单->2->2)。"
        return 1
    fi
}

start_st() {
    check_sudo
    if ! check_docker_env; then return 1; fi
    if [ ! -f "$ST_COMPOSE_FILE" ]; then msg_error "未找到SillyTavern安装，请先从菜单 '1' 开始安装。"; return; fi
    msg_info "正在启动 SillyTavern 服务..."
    sudo $DOCKER_COMPOSE_CMD -f "$ST_COMPOSE_FILE" up -d
    msg_ok "SillyTavern 已启动。请查看下方的状态信息获取访问地址。"
}

stop_st() {
    check_sudo
    if ! check_docker_env; then return 1; fi
    if [ ! -f "$ST_COMPOSE_FILE" ]; then msg_error "未找到SillyTavern安装。"; return; fi
    msg_info "正在停止 SillyTavern 服务..."
    sudo $DOCKER_COMPOSE_CMD -f "$ST_COMPOSE_FILE" down
    msg_ok "SillyTavern 已停止。"
}

restart_st() {
    check_sudo
    if ! check_docker_env; then return 1; fi
    if [ ! -f "$ST_COMPOSE_FILE" ]; then msg_error "未找到SillyTavern安装。"; return; fi
    msg_info "正在重启 SillyTavern 服务..."
    sudo $DOCKER_COMPOSE_CMD -f "$ST_COMPOSE_FILE" restart
    msg_ok "SillyTavern 已重启。"
}

update_st() {
    check_sudo
    if ! check_docker_env; then return 1; fi
    if [ ! -f "$ST_COMPOSE_FILE" ]; then msg_error "未找到SillyTavern安装。"; return; fi
    msg_info "正在拉取最新的 SillyTavern 和 Watchtower 镜像..."
    if sudo $DOCKER_COMPOSE_CMD -f "$ST_COMPOSE_FILE" pull; then
        msg_ok "镜像拉取成功。"
        msg_info "正在使用新镜像重启服务..."
        sudo $DOCKER_COMPOSE_CMD -f "$ST_COMPOSE_FILE" up -d
        msg_ok "SillyTavern 更新并重启完成。"
    else
        msg_error "镜像拉取失败，更新操作已中断。"
    fi
}

logs_st() {
    check_sudo
    if ! check_docker_env; then return 1; fi
    if [ ! -f "$ST_COMPOSE_FILE" ]; then msg_error "未找到SillyTavern安装。"; return; fi
    msg_info "正在显示 SillyTavern 实时日志... 按 Ctrl+C 退出。"
    sudo $DOCKER_COMPOSE_CMD -f "$ST_COMPOSE_FILE" logs -f sillytavern
}

backup_st() {
    check_sudo
    if [ ! -d "$ST_PATH" ]; then
        msg_error "SillyTavern 目录不存在，无法备份。"
        return
    fi
    local backup_file="$HOME/sillytavern_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    msg_info "正在将 ${ST_PATH} 备份到 ${backup_file} ..."
    # 使用sudo打包，但将最终文件所有权改为当前用户
    sudo tar -czf "$backup_file" -C "$(dirname "$ST_PATH")" "$(basename "$ST_PATH")"
    sudo chown $USER:$USER "$backup_file"
    msg_ok "备份成功！文件位于: $backup_file"
}

change_password_st() {
    check_sudo
    if [ ! -f "$ST_COMPOSE_FILE" ]; then
        msg_error "SillyTavern尚未安装，无法设置密码。请先安装。"
        return
    fi
    if [ ! -f "$ST_CONFIG_FILE" ]; then
        msg_warn "未找到配置文件，将为您创建新的配置文件并设置密码。"
    fi
    configure_access
    msg_info "配置已更新，正在重启SillyTavern以使新设置生效..."
    restart_st
}

status_st() {
    echo -n "   SillyTavern: "
    if [ -f "$ST_COMPOSE_FILE" ]; then
        local container_id=$(sudo docker ps -q -f name=sillytavern 2>/dev/null)
        if [ -n "$container_id" ]; then
            local container_status=$(sudo docker inspect --format '{{.State.Status}}' "$container_id")
            if [ "$container_status" == "running" ]; then
                echo -e "${C_GREEN}已安装且正在运行${C_RESET}"
                 local ip=$(curl -s4 ip.sb || echo "<你的公网IP>")
                 echo "     └─ 访问地址: ${C_YELLOW}http://${ip}:8000${C_RESET}"
                 if [ -f "$ST_CONFIG_FILE" ] && grep -q "basicAuthMode: true" "$ST_CONFIG_FILE"; then
                    local user=$(grep "username:" "$ST_CONFIG_FILE" | awk '{print $2}')
                    echo "     └─ 访问认证: ${C_GREEN}已开启 (用户: ${user})${C_RESET}"
                 else
                    echo "     └─ 访问认证: ${C_RED}未开启 (仅本地访问)${C_RESET}"
                 fi
            else
                echo -e "${C_YELLOW}已安装但处于停止状态 (${container_status})${C_RESET}"
            fi
        else
            echo -e "${C_YELLOW}配置文件存在但容器未运行 (可尝试启动)${C_RESET}"
        fi
    else
        echo -e "${C_RED}未安装${C_RESET}"
    fi
}

# --- 脚本入口：根据传入的第一个参数执行相应函数 ---
case "$1" in
    install) install_st ;;
    start) start_st ;;
    stop) stop_st ;;
    restart) restart_st ;;
    update) update_st ;;
    logs) logs_st ;;
    backup) backup_st ;;
    change_password) change_password_st ;;
    status) status_st ;;
    *) msg_error "用法错误: $0 {install|start|stop|restart|update|logs|backup|change_password|status}" ;;
esac
