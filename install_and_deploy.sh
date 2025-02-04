#!/bin/bash

# 更新系统包列表
sudo apt update -y

# 安装必要的包以允许 apt 通过 HTTPS 使用仓库
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common

# 添加 Docker 的官方 GPG 密钥
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# 设置 Docker 的稳定版仓库
echo  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 更新 apt 包索引
sudo apt update -y

# 安装最新版本的 Docker CE 和 containerd
sudo apt install -y docker-ce docker-ce-cli containerd.io

# 安装 Docker Compose (作为插件)
sudo apt install -y docker-compose-plugin

# 创建所需目录
mkdir -p /data/docker/sillytavem

# 写入 docker-compose.yaml 文件内容
cat <<EOF | sudo tee /data/docker/sillytavem/docker-compose.yaml
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
    restart: always

networks:
  DockerNet:
    name: DockerNet
EOF

# 改变目录至 /data/docker/sillytavem 并启动服务
cd /data/docker/sillytavem
sudo docker-compose up -d

echo "SillyTavern 已部署，可以通过 http://<your_server_ip>:8000 访问。"
