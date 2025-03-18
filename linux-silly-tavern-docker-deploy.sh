#!/bin/bash

# 检查是否具有sudo权限
if ! command -v sudo &> /dev/null; then
    echo "需要sudo权限来安装Docker"
    exit 1
fi

# 主安装流程
echo "检测系统类型..."
# 检查系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
elif [ -f /etc/redhat-release ]; then
    OS=$(cat /etc/redhat-release | sed 's/\(.*\)release.*/\1/' | tr '[:upper:]' '[:lower:]' | tr -d ' ')
elif [ -f /etc/arch-release ]; then
    OS="arch"
elif [ -f /etc/alpine-release ]; then
    OS="alpine"
elif [ -f /etc/SuSE-release ]; then
    OS="suse"
else
    echo "无法确定操作系统类型"
    exit 1
fi

# 检查并设置docker compose命令
setup_docker_compose() {
    # 首先检查是否有docker compose（新版命令）
    if docker compose version &> /dev/null; then
        echo "检测到 docker compose 命令可用"
        DOCKER_COMPOSE_CMD="docker compose"
        return 0
    fi
    
    # 检查是否有docker-compose（旧版命令）
    if command -v docker-compose &> /dev/null; then
        echo "检测到 docker-compose 命令可用"
        DOCKER_COMPOSE_CMD="docker-compose"
        return 0
    fi
    
    # 如果都没有，则需要安装docker-compose
    echo "未检测到 docker compose，将安装 docker-compose..."
    
    case $OS in
        debian|ubuntu)
            sudo apt-get update
            sudo apt-get install -y docker-compose
            ;;
        centos|rhel|fedora)
            sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
            ;;
        arch)
            sudo pacman -S --noconfirm docker-compose
            ;;
        alpine)
            sudo apk add docker-compose
            ;;
        suse|opensuse-leap|opensuse-tumbleweed)
            sudo zypper install -y docker-compose
            ;;
        *)
            echo "不支持的操作系统: $OS"
            exit 1
            ;;
    esac
    
    # 验证安装
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose 安装成功"
        DOCKER_COMPOSE_CMD="docker-compose"
        return 0
    else
        echo "docker-compose 安装失败"
        exit 1
    fi
}

# 检查现有安装
check_existing_installation() {
    if [ -f "/data/docker/sillytavem/docker-compose.yaml" ]; then
        return 0 # 安装存在
    else
        return 1 # 未找到安装
    fi
}

# 获取当前版本
get_current_version() {
    local current_version="未知"
    if sudo docker ps -q --filter "name=sillytavern" &> /dev/null; then
        current_version=$(sudo docker inspect --format='{{index .Config.Labels "org.opencontainers.image.version"}}' $(sudo docker ps -q --filter "name=sillytavern"))
        if [ -z "$current_version" ]; then
            current_version="无法获取版本信息"
        fi
    fi
    echo "$current_version"
}
# 获取最新版本
get_latest_version() {
    local latest_version="未知"

    # 尝试获取最新版本信息
    latest_version=$(curl -s "https://api.github.com/repos/sillytavern/sillytavern/releases/latest" | grep -Po '"tag_name": "\K.*?(?=")')

    if [ -z "$latest_version" ]; then
        latest_version="无法获取最新版本信息"
    fi

    echo "$latest_version"
}

setup_update_mode() {
    echo "请选择更新模式:"
    echo "1. 自动更新 (使用最新版本标签并启用每日更新检查)"
    echo "2. 手动更新 (使用固定版本标签，需手动执行更新)"

    read -r update_choice </dev/tty

    case $update_choice in
        1)
            echo "已选择自动更新模式"
            auto_update="y"
            image_tag="latest"
            include_watchtower="y"
            ;;
        2)
            echo "已选择手动更新模式"
            auto_update="n"

            # 获取最新版本以作为固定版本
            latest_version=$(get_latest_version)
            if [ "$latest_version" != "无法获取最新版本信息" ]; then
                image_tag=$latest_version
            else
                echo "无法获取最新版本，将使用默认最新标签"
                image_tag="latest"
            fi

            include_watchtower="n"
            ;;
        *)
            echo "无效选择，默认使用自动更新模式"
            auto_update="y"
            image_tag="latest"
            include_watchtower="y"
            ;;
    esac
}

create_docker_compose_file() {
    local image_tag=$1
    local include_watchtower=$2

    echo "创建docker-compose.yaml文件，使用镜像版本: $image_tag"

    # 基本服务配置
    cat <<EOF | sudo tee /data/docker/sillytavem/docker-compose.yaml
version: '3.8'

services:
  sillytavern:
    image: ghcr.io/sillytavern/sillytavern:${image_tag}
    container_name: sillytavern
    networks:
      - DockerNet
    ports:
      - "8000:8000"
    volumes:
      - ./plugins:/home/node/app/plugins:rw
      - ./config:/home/node/app/config:rw
      - ./data:/home/node/app/data:rw
      - ./extensions:/home/node/app/public/scripts/extensions/third-party:rw
    restart: always
EOF

    # 根据选择添加自动更新相关标签和服务
    if [ "$include_watchtower" = "y" ]; then
        cat <<EOF | sudo tee -a /data/docker/sillytavem/docker-compose.yaml
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

  # 添加watchtower服务自动更新容器
  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --interval 86400 --cleanup --label-enable # 每天检查一次更新
    restart: always
    networks:
      - DockerNet
EOF
    fi

    # 添加网络配置
    cat <<EOF | sudo tee -a /data/docker/sillytavem/docker-compose.yaml

networks:
  DockerNet:
    name: DockerNet
EOF
}



# 添加备份脚本检查和创建功能
ensure_backup_script_exists() {
    if [ ! -f "/data/docker/sillytavem/backup.sh" ]; then
        echo "未找到备份脚本，正在创建..."
        # 创建备份脚本以便将来使用
        cat <<EOF | sudo tee /data/docker/sillytavem/backup.sh
#!/bin/bash

# 设置变量
backup_dir="/data/docker/sillytavem"
backups_folder="\${backup_dir}/backups"
timestamp=\$(date +"%Y%m%d_%H%M%S")
backup_file="\${backups_folder}/sillytavern_data_backup_\${timestamp}.zip"

# 确保备份目录存在
mkdir -p "\${backups_folder}"

echo "正在创建数据备份..."

# 检查数据目录是否存在
if [ ! -d "\${backup_dir}/data" ]; then
    echo "错误: 数据目录不存在 (\${backup_dir}/data)"
    exit 1
fi

# 检查zip命令是否存在，如果不存在则安装
if ! command -v zip &> /dev/null; then
    echo "正在安装zip工具..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y zip
    elif command -v yum &> /dev/null; then
        sudo yum install -y zip
    else
        echo "无法安装zip工具，请手动安装"
        exit 1
    fi
fi

# 创建备份
cd "\${backup_dir}" && sudo zip -r "\${backup_file}" data/

if [ \$? -eq 0 ]; then
    sudo chmod 644 "\${backup_file}"
    echo "备份成功创建: \${backup_file}"
else
    echo "备份创建失败，请检查错误信息"
    exit 1
fi
EOF
        # 使备份脚本可执行
        sudo chmod +x /data/docker/sillytavem/backup.sh
        echo "备份脚本已创建"
    fi
}



# 更新酒馆
update_tavern() {
    echo "正在更新酒馆..."

    # 检查是否是自动更新模式
    if grep -q "watchtower" /data/docker/sillytavem/docker-compose.yaml; then
        auto_update="y"
    else
        auto_update="n"
    fi

    if [ "$auto_update" = "y" ]; then
        echo "检测到自动更新模式，将更新至最新版本"
    else
        # 手动更新模式，提示用户选择版本
        latest_version=$(get_latest_version)
        echo "当前为手动更新模式"
        echo "最新可用版本: $latest_version"
        echo "请选择更新方式:"
        echo "1. 更新到最新版本 ($latest_version)"
        echo "2. 输入特定版本号"

        read -r choice </dev/tty

        case $choice in
            1)
                target_version=$latest_version
                ;;
            2)
                echo "请输入要更新到的版本号 (例如: v2.0.0):"
                read -r target_version </dev/tty
                ;;
            *)
                echo "无效选择，将使用最新版本 $latest_version"
                target_version=$latest_version
                ;;
        esac

        # 更新 docker-compose.yaml 文件中的版本号
        echo "将更新到版本: $target_version"
        sudo sed -i "s|image: ghcr.io/sillytavern/sillytavern:.*|image: ghcr.io/sillytavern/sillytavern:$target_version|g" /data/docker/sillytavem/docker-compose.yaml
    fi

    cd /data/docker/sillytavem
    sudo $DOCKER_COMPOSE_CMD pull
    sudo $DOCKER_COMPOSE_CMD down
    sudo $DOCKER_COMPOSE_CMD up -d

    # 检查服务状态
    check_service_status "更新并启动"
}



# 导入备份
import_backup() {
    echo "请选择导入方式："
    echo "1. 选择远程zip文件"
    echo "2. 本地目录"
    read -r import_choice </dev/tty

    case $import_choice in
        1)
            echo "请输入远程zip文件URL:"
            read -r backup_url </dev/tty

            temp_dir=$(mktemp -d)
            echo "正在下载备份文件..."

            # 支持多种下载工具
            if command -v curl &> /dev/null; then
                curl -L "$backup_url" -o "$temp_dir/backup.zip"
            elif command -v wget &> /dev/null; then
                wget -O "$temp_dir/backup.zip" "$backup_url"
            else
                echo "未找到curl或wget，请安装后重试"
                rm -rf "$temp_dir"
                return 1
            fi

            echo "正在解压备份文件..."
            unzip -o "$temp_dir/backup.zip" -d "$temp_dir"

            echo "正在导入备份数据..."
            sudo $DOCKER_COMPOSE_CMD down
            sudo cp -r "$temp_dir/data/"* "/data/docker/sillytavem/data/"
            sudo chown -R $(id -u):$(id -g) "/data/docker/sillytavem/data/"

            rm -rf "$temp_dir"
            echo "备份数据导入完成！"
            ;;
        2)
            echo "请输入本地备份目录路径 (留空使用默认路径 /data/docker/sillytavem/backups/):"
            read -r backup_dir </dev/tty

            if [ -z "$backup_dir" ]; then
                backup_dir="/data/docker/sillytavem/backups"
            fi

            if [ ! -d "$backup_dir" ]; then
                echo "目录不存在: $backup_dir"
                return 1
            fi

            # 列出可用的备份文件
            echo "可用的备份文件:"
            ls -1 "$backup_dir" | grep -E '\.zip$' | cat -n
            echo "请选择要导入的备份文件编号:"
            read -r backup_num </dev/tty

            backup_file=$(ls -1 "$backup_dir" | grep -E '\.zip$' | sed -n "${backup_num}p")
            if [ -z "$backup_file" ]; then
                echo "无效的选择"
                return 1
            fi

            full_path="$backup_dir/$backup_file"

            temp_dir=$(mktemp -d)
            echo "正在解压备份文件 $full_path..."
            unzip -o "$full_path" -d "$temp_dir"

            echo "正在导入备份数据..."
            sudo $DOCKER_COMPOSE_CMD down
            sudo cp -r "$temp_dir/data/"* "/data/docker/sillytavem/data/"
            sudo chown -R $(id -u):$(id -g) "/data/docker/sillytavem/data/"

            rm -rf "$temp_dir"
            echo "备份数据导入完成！"
            ;;
        *)
            echo "无效的选择"
            return 1
            ;;
    esac

    # 导入完成后启动服务
    sudo $DOCKER_COMPOSE_CMD up -d

    # 检查服务是否成功启动
    check_service_status "导入备份"
}
# 启动酒馆
start_tavern() {
    echo "正在启动酒馆..."
    cd /data/docker/sillytavem
    sudo $DOCKER_COMPOSE_CMD up -d

    # 检查服务状态
    check_service_status "启动"
}



# 安装Docker的函数 - Debian系统
install_docker_debian() {
    echo "在 Debian 系统上安装 Docker..."

    # 移除旧版本
    sudo apt-get remove docker docker-engine docker.io containerd runc || true

    # 更新并安装依赖
    sudo apt-get update
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # 添加Docker官方GPG密钥（Debian专用）
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # 设置Debian仓库
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # 安装Docker
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# 安装Docker的函数 - Ubuntu系统
install_docker_ubuntu() {
    echo "在 Ubuntu 系统上安装 Docker..."

    # 移除旧版本
    sudo apt-get remove docker docker-engine docker.io containerd runc || true

    # 更新并安装依赖
    sudo apt-get update
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # 添加Docker官方GPG密钥（Ubuntu专用）
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # 设置Ubuntu仓库
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # 安装Docker
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# 安装Docker的函数 - 基于CentOS/RHEL系统
install_docker_centos() {
    echo "在 CentOS/RHEL 系统上安装 Docker..."

    # 移除旧版本
    sudo yum remove docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine || true

    # 安装必要的工具
    sudo yum install -y yum-utils

    # 添加Docker仓库
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    # 安装Docker
    sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
}

# Arch Linux 安装函数
install_docker_arch() {
    echo "在 Arch Linux 系统上安装 Docker..."
    sudo pacman -Sy
    sudo pacman -S --noconfirm docker docker-compose
}

# Alpine Linux 安装函数
install_docker_alpine() {
    echo "在 Alpine Linux 系统上安装 Docker..."
    sudo apk update
    sudo apk add docker docker-compose
}

# OpenSUSE 安装函数
install_docker_suse() {
    echo "在 OpenSUSE 系统上安装 Docker..."
    sudo zypper refresh
    sudo zypper install -y docker docker-compose
}

# 安装Docker的函数 - 基于Fedora系统
install_docker_fedora() {
    echo "在 Fedora 系统上安装 Docker..."

    # 移除旧版本
    sudo dnf remove docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine || true

    # 添加Docker仓库
    sudo dnf -y install dnf-plugins-core
    sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo

    # 安装Docker
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
}

# 检查服务状态
check_service_status() {
    local action_description=$1

    # 检查服务是否成功启动
    if [ $? -eq 0 ]; then
        # 获取外网IP
        public_ip=$(curl -sS https://api.ipify.org)
        echo "SillyTavern 已成功${action_description}"
        echo "访问地址: http://${public_ip}:8000"

        # 读取认证信息并显示
        read_auth_credentials
        if [[ "$enable_external_access" == "y" ]]; then
            echo "用户名: ${username}"
            echo "密码: ${password}"
        fi

        # 检查watchtower是否正常运行
        if sudo $DOCKER_COMPOSE_CMD ps | grep -q "watchtower.*Up"; then
            echo "自动更新服务(watchtower)已成功启动，将每天检查更新"
        else
            echo "自动更新服务(watchtower)启动失败，请检查日志"
        fi
    else
        echo "服务${action_description}失败，请检查日志"
        sudo $DOCKER_COMPOSE_CMD logs
    fi
}

# 从配置文件中读取认证信息
read_auth_credentials() {
    if [ -f "/data/docker/sillytavem/config/config.yaml" ]; then
        # 从配置文件中读取用户名和密码
        enable_external_access="y"

        # 更准确地定位和提取用户名密码
        username=$(grep -A1 "username:" /data/docker/sillytavem/config/config.yaml | tail -1 | sed 's/^[ \t]*username:[ \t]*//g')
        password=$(grep -A1 "password:" /data/docker/sillytavem/config/config.yaml | tail -1 | sed 's/^[ \t]*password:[ \t]*//g')

        # 检查是否成功获取到了值
        if [ -z "$username" ] || [ -z "$password" ]; then
            # 尝试另一种格式
            username=$(awk '/basicAuthUser:/,/enableCorsProxy:/' /data/docker/sillytavem/config/config.yaml | grep "username:" | awk '{print $2}')
            password=$(awk '/basicAuthUser:/,/enableCorsProxy:/' /data/docker/sillytavem/config/config.yaml | grep "password:" | awk '{print $2}')
        fi
    else
        enable_external_access="n"
    fi
}


# 修改账号密码
change_credentials() {
    echo "修改账号密码..."

    # 确保配置目录存在
    sudo mkdir -p /data/docker/sillytavem/config

    # 如果配置文件不存在，先创建基本配置
    if [ ! -f "/data/docker/sillytavem/config/config.yaml" ]; then
        echo "未找到现有配置文件，将创建新配置..."
        cat <<EOF | sudo tee /data/docker/sillytavem/config/config.yaml
# TODO: 基础配置内容
basicAuthMode: true
basicAuthUser:
  username: admin
  password: admin
EOF
    fi

    # 获取新的认证信息
    echo -n "请输入新用户名(不可以使用纯数字): "
    read -r new_username </dev/tty
    echo -n "请输入新密码(不可以使用纯数字): "
    read -r new_password </dev/tty

    # 更新配置文件中的用户名密码
    sudo sed -i "s/username:.*$/username: $new_username/" /data/docker/sillytavem/config/config.yaml
    sudo sed -i "s/password:.*$/password: $new_password/" /data/docker/sillytavem/config/config.yaml

    echo "账号密码已更新"
    echo "用户名: $new_username"
    echo "密码: $new_password"

    # 重启服务以应用新配置
    echo "重启服务以应用新配置..."
    sudo $DOCKER_COMPOSE_CMD restart

    # 检查服务状态
    check_service_status "重启"
}




# 主安装流程
echo "当前操作系统类型为 $OS"

# 检查是否已安装Docker
if ! command -v docker &> /dev/null; then
    case $OS in
        debian)
            install_docker_debian
            ;;
        ubuntu)
            install_docker_ubuntu
            ;;
        centos|rhel)
            install_docker_centos
            ;;
        fedora)
            install_docker_fedora
            ;;
        arch)
            install_docker_arch
            ;;
        alpine)
            install_docker_alpine
            ;;
        suse|opensuse-leap|opensuse-tumbleweed)
            install_docker_suse
            ;;
        *)
            echo "不支持的操作系统: $OS"
            exit 1
            ;;
    esac

    # 启动Docker服务
    # Alpine 的特殊处理
    if [ "$OS" = "alpine" ]; then
        sudo rc-update add docker boot
        sudo service docker start
    else
        sudo systemctl start docker
        sudo systemctl enable docker
    fi

    # 验证Docker安装
    if ! docker --version > /dev/null 2>&1; then
        echo "Docker安装失败"
        exit 1
    fi
else
    echo "Docker已安装，跳过安装步骤"
fi

# 设置 docker compose 命令
setup_docker_compose


# 检查Docker和Docker Compose是否可用
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    echo "未找到docker-compose或docker compose命令，请安装Docker和Docker Compose"
    exit 1
fi
# 检查是否已有安装
if check_existing_installation; then
    echo "检测到已存在的SillyTavern安装"
    current_version=$(get_current_version)
    latest_version=$(get_latest_version)

    echo "当前版本: $current_version"
    echo "最新版本: $latest_version"

    echo "请选择操作:"
    echo "1. 更新酒馆"
    echo "2. 备份数据"
    echo "3. 导入备份"
    echo "4. 修改账号密码"
    echo "5. 启动酒馆"
    read -r choice </dev/tty

    case $choice in
        1)
            update_tavern
            ;;
        2)
            sudo bash /data/docker/sillytavem/backup.sh
            ;;
        3)
            import_backup
            ;;
        4)
            change_credentials
            ;;
        5)
            start_tavern
            ;;
        *)
            echo "无效的选择，将默认启动酒馆"
            start_tavern
            ;;
    esac
else
    # 执行新安装
    # 创建所需目录
    sudo mkdir -p /data/docker/sillytavem

    # 询问更新模式
    setup_update_mode

    # 创建适合的docker-compose文件
    create_docker_compose_file "$image_tag" "$include_watchtower"

    # 提示用户确认是否开启外网访问
    echo "请选择是否开启外网访问"
    while true; do
        echo -n "是否开启外网访问？(y/n): "
        read -r response </dev/tty
        case $response in
            [Yy]* )
                enable_external_access="y"
                break
                ;;
            [Nn]* )
                enable_external_access="n"
                break
                ;;
            * )
                echo "请输入 y 或 n"
                ;;
        esac
    done

    # 确保显示用户的选择
    echo "您选择了: $([ "$enable_external_access" = "y" ] && echo "开启" || echo "不开启")外网访问"

    # 生成随机字符串的函数
    generate_random_string() {
        tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16
    }

    if [[ $enable_external_access == "y" || $enable_external_access == "Y" ]]; then
        # 让用户选择用户名密码的生成方式
        echo "请选择用户名密码的生成方式:"
        echo "1. 随机生成"
        echo "2. 手动输入(推荐)"
        while true; do
            read -r choice </dev/tty
            case $choice in
                1)
                    username=$(generate_random_string)
                    password=$(generate_random_string)
                    echo "已生成随机用户名: $username"
                    echo "已生成随机密码: $password"
                    break
                    ;;
                2)
                    echo -n "请输入用户名(不可以使用纯数字): "
                    read -r username </dev/tty
                    echo -n "请输入密码(不可以使用纯数字): "
                    read -r password </dev/tty
                    break
                    ;;
                *)
                    echo "请输入 1 或 2"
                    ;;
            esac
        done

        # 创建config目录和配置文件
        sudo mkdir -p /data/docker/sillytavem/config
        cat <<EOF | sudo tee /data/docker/sillytavem/config/config.yaml
dataRoot: ./data
cardsCacheCapacity: 100
listen: true
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
basicAuthMode: true
basicAuthUser:
  username: $username
  password: $password
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

        echo "已开启外网访问"
        echo "用户名: $username"
        echo "密码: $password"
    else
        echo "未开启外网访问，将使用默认配置。"
    fi

    # 创建备份脚本以便将来使用
    cat <<EOF | sudo tee /data/docker/sillytavem/backup.sh
#!/bin/bash

# 设置变量
backup_dir="/data/docker/sillytavem"
backups_folder="\${backup_dir}/backups"
timestamp=\$(date +"%Y%m%d_%H%M%S")
backup_file="\${backups_folder}/sillytavern_data_backup_\${timestamp}.zip"

# 确保备份目录存在
mkdir -p "\${backups_folder}"

echo "正在创建数据备份..."

# 检查数据目录是否存在
if [ ! -d "\${backup_dir}/data" ]; then
    echo "错误: 数据目录不存在 (\${backup_dir}/data)"
    exit 1
fi

# 检查zip命令是否存在，如果不存在则安装
if ! command -v zip &> /dev/null; then
    echo "正在安装zip工具..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y zip
    elif command -v yum &> /dev/null; then
        sudo yum install -y zip
    else
        echo "无法安装zip工具，请手动安装"
        exit 1
    fi
fi

# 创建备份
cd "\${backup_dir}" && sudo zip -r "\${backup_file}" data/

if [ \$? -eq 0 ]; then
    sudo chmod 644 "\${backup_file}"
    echo "备份成功创建: \${backup_file}"
else
    echo "备份创建失败，请检查错误信息"
    exit 1
fi
EOF

    # 使备份脚本可执行
    sudo chmod +x /data/docker/sillytavem/backup.sh

    # 启动服务
    echo "服务未运行，正在启动..."
    sudo $DOCKER_COMPOSE_CMD up -d

    # 检查服务是否成功启动
    if [ $? -eq 0 ]; then
        # 获取外网IP
        public_ip=$(curl -sS https://api.ipify.org)
        echo "SillyTavern 已成功部署"
        echo "访问地址: http://${public_ip}:8000"
        if [[ $enable_external_access == "y" || $enable_external_access == "Y" ]]; then
            echo "用户名: ${username}"
            echo "密码: ${password}"
        fi

        # 检查watchtower是否正常运行
        if sudo $DOCKER_COMPOSE_CMD ps | grep -q "watchtower.*Up"; then
            echo "自动更新服务(watchtower)已成功启动，将每天检查更新"
        else
            echo "自动更新服务(watchtower)启动失败，请检查日志"
        fi
    else
        echo "服务启动失败，请检查日志"
        sudo $DOCKER_COMPOSE_CMD logs
    fi
fi

echo ""
echo "您可以通过运行以下命令随时备份数据："
echo "sudo bash /data/docker/sillytavem/backup.sh"


# 检查服务是否成功启动
if [ $? -eq 0 ]; then
    # 获取外网IP
    public_ip=$(curl -sS https://api.ipify.org)
    echo "SillyTavern 已成功部署"
    echo "访问地址: http://${public_ip}:8000"
    if [[ $enable_external_access == "y" || $enable_external_access == "Y" ]]; then
        echo "用户名: ${username}"
        echo "密码: ${password}"
    fi

    # 检查watchtower是否正常运行
    if sudo $DOCKER_COMPOSE_CMD ps | grep -q "watchtower.*Up"; then
        echo "自动更新服务(watchtower)已成功启动，将每天检查更新"
    else
        echo "自动更新服务(watchtower)启动失败，请检查日志"
    fi
else
    echo "服务启动失败，请检查日志"
    sudo $DOCKER_COMPOSE_CMD logs
fi

# 添加备份选项，仅当数据目录存在时才提供
if [ -d "/data/docker/sillytavem/data" ] && [ -n "$(ls -A /data/docker/sillytavem/data 2>/dev/null)" ]; then
    echo ""
    echo "检测到数据目录存在，是否要创建数据备份？(y/n): "
    read -r backup_choice </dev/tty
    if [[ $backup_choice == "y" || $backup_choice == "Y" ]]; then
        sudo bash /data/docker/sillytavem/backup.sh
    fi
fi

echo ""
echo "您可以通过运行以下命令随时备份数据："
echo "    sudo bash /data/docker/sillytavem/backup.sh"
