#!/bin/bash

# 更新软件包列表并安装必要的包
pkg update -y
pkg install -y podman python

# 安装 podman-compose
pip install --user podman-compose

# 创建 docker-compose.yaml 文件的目录
mkdir -p /data/docker/sillytavem

# 写入 docker-compose.yaml 文件内容
cat <<EOF > /data/docker/sillytavem/docker-compose.yaml
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

# 切换到文件目录
cd /data/docker/sillytavem

# 使用 podman-compose 启动服务
~/.local/bin/podman-compose up -d
