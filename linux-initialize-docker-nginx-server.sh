#!/bin/bash
set -e

# 安装docker及compose
echo "安装Docker..."
curl -fsSL https://raw.githubusercontent.com/mxw13579/silly-tavern-docker-starts/main/linux-initialize-docker.sh | sudo bash

# beszel-agent compose
BESZEL_DIR="/data/docker/beszel-agent"
mkdir -p "$BESZEL_DIR"
cat > "$BESZEL_DIR/docker-compose.yml" <<EOF
services:
  beszel-agent:
    image: "henrygd/beszel-agent"
    container_name: "beszel-agent"
    restart: unless-stopped
    network_mode: host
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      PORT: 45876
      KEY: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIISJjq7eJccuFuU9vVYfacKqELGap6isDLsXhTfRiwCc"

  watchtower:
    image: containrrr/watchtower
    container_name: watchtower-beszel
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --cleanup --interval 3600 beszel-agent
EOF

# nginx-ui compose
NGINXUI_DIR="/data/docker/nginx-ui"
mkdir -p "$NGINXUI_DIR"
cat > "$NGINXUI_DIR/docker-compose.yml" <<EOF
services:
  nginx-ui:
    image: uozi/nginx-ui:latest
    container_name: nginx-ui
    restart: always
    environment:
      - TZ=Asia/Shanghai
      - NGINX_UI_NGINX_CONFIG_DIR=/etc/nginx
    volumes:
      - /mnt/user/appdata/nginx:/etc/nginx
      - /mnt/user/appdata/nginx-ui:/etc/nginx-ui
      - /var/www:/var/www
      - /var/run/docker.sock:/var/run/docker.sock
    network_mode: host
    tty: true
    stdin_open: true

  watchtower:
    image: containrrr/watchtower
    container_name: watchtower-nginx-ui
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --cleanup --interval 3600 nginx-ui
EOF

echo "启动 beszel-agent 及 Watchtower..."
docker compose -f "$BESZEL_DIR/docker-compose.yml" up -d

echo "启动 nginx-ui 及 Watchtower..."
docker compose -f "$NGINXUI_DIR/docker-compose.yml" up -d

echo "部署完成，每个项目已独立自动更新"
