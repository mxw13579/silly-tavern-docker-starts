#!/data/data/com.termux/files/usr/bin/bash

# 安装必要组件
pkg update -y && pkg install -y podman podman-compose

# 初始化 Podman 存储（Termux 需要特殊配置）
mkdir -p ~/.local/share/containers/storage
if ! grep -q "driver = \"overlay\"" ~/.config/containers/storage.conf 2>/dev/null; then
    podman info >/dev/null  # 自动生成配置文件
fi

# 创建项目目录
BASE_DIR="$HOME/storage/shared/docker/sillytavern"  # 使用 Termux 共享存储路径
mkdir -p "$BASE_DIR"

# 写入 docker-compose.yaml
cat <<EOF > "$BASE_DIR/docker-compose.yaml"
version: '3.8'

services:
  sillytavern:
    image: ghcr.io/sillytavern/sillytavern:1.12.11
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
    restart: unless-stopped

networks:
  DockerNet:
    name: DockerNet
EOF

# 启动容器
cd "$BASE_DIR"
podman-compose up -d

echo "安装完成！可通过以下方式访问："
echo "1. 同一网络设备访问：http://你的手机IP:8000"
echo "2. 本机访问：http://localhost:8000"