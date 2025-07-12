#!/bin/bash
# linux-deploy-new-api.sh
# 一键部署 new-api 服务 + MySQL + Redis

#--------------------------------------------------
# 颜色
#--------------------------------------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

#--------------------------------------------------
# 选择 docker compose 命令
#--------------------------------------------------
if command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker-compose"
elif docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
else
    echo -e "${RED}错误：系统未安装 docker-compose / docker compose${NC}"
    exit 1
fi

echo -e "${YELLOW}开始配置 new-api 服务...${NC}"

#--------------------------------------------------
# 判断是否交互式
#--------------------------------------------------
if [ -t 0 ]; then
    INTERACTIVE=true
else
    INTERACTIVE=false
    echo -e "${YELLOW}检测到非交互执行，将使用环境变量或默认值${NC}"
fi

#--------------------------------------------------
# 目录与变量
#--------------------------------------------------
PROJECT_DIR="/data/docker/new-api"
mkdir -p "$PROJECT_DIR"
echo -e "${GREEN}项目目录: $PROJECT_DIR${NC}"

# ---------- MySQL 配置 ----------
if $INTERACTIVE; then
    read -p "MySQL ROOT 密码 [123456]: " MYSQL_ROOT_PASSWORD
    MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-123456}
    read -p "业务用户(不能写 root) [app]: " MYSQL_USER
    MYSQL_USER=${MYSQL_USER:-app}
    read -p "业务用户密码 [apppwd]: " MYSQL_PASSWORD
    MYSQL_PASSWORD=${MYSQL_PASSWORD:-apppwd}
    read -p "数据库名 [new-api]: " MYSQL_DATABASE
    MYSQL_DATABASE=${MYSQL_DATABASE:-new-api}
else
    MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-123456}
    MYSQL_USER=${MYSQL_USER:-app}
    MYSQL_PASSWORD=${MYSQL_PASSWORD:-apppwd}
    MYSQL_DATABASE=${MYSQL_DATABASE:-new-api}
fi

echo -e "${GREEN}MySQL => 用户:$MYSQL_USER  数据库:$MYSQL_DATABASE${NC}"

#--------------------------------------------------
# 创建目录结构
#--------------------------------------------------
mkdir -p "$PROJECT_DIR/mysql" \
         "$PROJECT_DIR/data" \
         "$PROJECT_DIR/logs"

#--------------------------------------------------
# docker-compose.yml
#--------------------------------------------------
cat > "$PROJECT_DIR/docker-compose.yml" <<EOF
services:
  new-api:
    image: calciumion/new-api:latest
    container_name: new-api
    restart: always
    command: --log-dir /app/logs
    ports:
      - "3000:3000"
    volumes:
      - ./data:/data
      - ./logs:/app/logs
    environment:
      - SQL_DSN=$MYSQL_USER:$MYSQL_PASSWORD@tcp(mysql:3306)/$MYSQL_DATABASE
      - REDIS_CONN_STRING=redis://redis
      - TZ=Asia/Shanghai
    depends_on:
      - redis
      - mysql

  redis:
    image: redis:latest
    container_name: redis
    restart: always

  mysql:
    image: mysql:8.2
    container_name: mysql
    restart: always
    environment:
      # root 口令
      MYSQL_ROOT_PASSWORD: $MYSQL_ROOT_PASSWORD
      # 业务数据库及账号
      MYSQL_DATABASE: $MYSQL_DATABASE
      MYSQL_USER: $MYSQL_USER
      MYSQL_PASSWORD: $MYSQL_PASSWORD
    volumes:
      - mysql_data:/var/lib/mysql

volumes:
  mysql_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $PROJECT_DIR/mysql
EOF

#--------------------------------------------------
# 启动服务
#--------------------------------------------------
if $INTERACTIVE; then
    read -p "是否立即启动服务？(y/n): " R
    if [[ "$R" != "y" && "$R" != "Y" ]]; then
        echo -e "${YELLOW}稍后可手动执行: cd $PROJECT_DIR && $DOCKER_COMPOSE up -d${NC}"
        exit 0
    fi
fi

echo -e "${GREEN}启动服务...${NC}"
cd "$PROJECT_DIR" && $DOCKER_COMPOSE down && $DOCKER_COMPOSE up -d

echo -e "${GREEN}所有容器已启动，可使用 'docker ps' 查看运行状态。${NC}"
echo -e "${GREEN}服务访问地址: http://<your-server-ip>:3000${NC}"
echo -e "${YELLOW}配置文件: $PROJECT_DIR/docker-compose.yml${NC}"
echo -e "${YELLOW}数据目录: $PROJECT_DIR/data, $PROJECT_DIR/mysql${NC}"
echo -e "${YELLOW}日志目录: $PROJECT_DIR/logs${NC}"

