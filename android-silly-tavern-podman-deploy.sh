#!/data/data/com.termux/files/usr/bin/bash

# 更新包列表并安装必要的工具
pkg update && pkg upgrade -y
pkg install -y docker docker-compose git

# 启动 Docker 服务
dockerd &

# 等待 Docker 启动
sleep 5

# 创建项目目录
mkdir -p ~/sillytavern-docker
cd ~/sillytavern-docker

# 创建 docker-compose.yml 文件
cat <<EOF > docker-compose.yml
version: '3.8'

services:
  sillytavern:
    image: ghcr.io/sillytavern/sillytavern:latest
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

networks:
  DockerNet:
    name: DockerNet
EOF

# 启动 Docker Compose
docker-compose up -d

echo "SillyTavern 已启动，您可以通过 http://localhost:8000 访问它。"
