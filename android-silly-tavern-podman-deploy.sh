#!/bin/bash

# 更新软件包列表
pkg update -y

# 安装必要的包
pkg install -y git nodejs-lts

# 克隆 SillyTavern 项目
git clone https://github.com/SillyTavern/SillyTavern.git ~/sillytavern

# 进入项目目录
cd ~/sillytavern

# 安装依赖
npm install

# 创建必要的目录
mkdir -p plugins config data extensions

# 启动应用（以后台方式）
nohup node server.js &

echo "SillyTavern 已启动，可以通过 http://localhost:8000 访问。"
