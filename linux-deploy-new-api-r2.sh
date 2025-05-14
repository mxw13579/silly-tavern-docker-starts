#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color


if command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker-compose"
elif docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
else
    echo -e "${RED}错误：系统中既没有 docker-compose 也没有 docker compose，请先安装 Docker Compose${NC}"
    exit 1
fi

echo -e "${YELLOW}开始配置MySQL到Cloudflare R2的备份服务...${NC}"

# 检查是否在交互式终端中运行
if [ -t 0 ]; then
    INTERACTIVE=true
else
    INTERACTIVE=false
    echo -e "${YELLOW}非交互模式检测，将使用默认设置或环境变量。${NC}"
    echo -e "${YELLOW}如需交互式配置，请直接运行脚本: ./script.sh${NC}"
fi

# 指定项目根目录
PROJECT_DIR="/data/docker/new-api"
echo -e "${GREEN}项目目录: $PROJECT_DIR${NC}"

# 确保项目目录存在
mkdir -p $PROJECT_DIR

# 获取MySQL配置
if [ "$INTERACTIVE" = true ]; then
    echo -e "${YELLOW}请输入MySQL配置信息:${NC}"
    read -p "MySQL用户名 [root]: " MYSQL_USER
    MYSQL_USER=${MYSQL_USER:-root}

    read -p "MySQL密码 [123456]: " MYSQL_PASSWORD
    MYSQL_PASSWORD=${MYSQL_PASSWORD:-123456}

    read -p "MySQL数据库名 [new-api]: " MYSQL_DATABASE
    MYSQL_DATABASE=${MYSQL_DATABASE:-new-api}
else
    # 使用环境变量或默认值
    MYSQL_USER=${MYSQL_USER:-root}
    MYSQL_PASSWORD=${MYSQL_PASSWORD:-123456}
    MYSQL_DATABASE=${MYSQL_DATABASE:-new-api}
    echo -e "${GREEN}使用MySQL配置: 用户=$MYSQL_USER, 数据库=$MYSQL_DATABASE${NC}"
fi

# 获取Cloudflare R2配置
if [ "$INTERACTIVE" = true ]; then
    echo -e "${YELLOW}请输入Cloudflare R2配置信息:${NC}"
    read -p "R2 Access Key: " R2_ACCESS_KEY
    read -p "R2 Secret Key: " R2_SECRET_KEY
    read -p "R2 Bucket Name: " R2_BUCKET
    read -p "R2 Endpoint (例如: https://xxxx.r2.cloudflarestorage.com): " R2_ENDPOINT
else
    # 使用环境变量
    if [ -z "$R2_ACCESS_KEY" ] || [ -z "$R2_SECRET_KEY" ] || [ -z "$R2_BUCKET" ] || [ -z "$R2_ENDPOINT" ]; then
        echo -e "${RED}错误: 非交互模式下必须设置以下环境变量:${NC}"
        echo -e "${RED}R2_ACCESS_KEY, R2_SECRET_KEY, R2_BUCKET, R2_ENDPOINT${NC}"
        echo -e "${YELLOW}例如:${NC}"
        echo -e "R2_ACCESS_KEY=your_key R2_SECRET_KEY=your_secret R2_BUCKET=your_bucket R2_ENDPOINT=https://xxx.r2.cloudflarestorage.com curl -fsSL https://raw.githubusercontent.com/mxw13579/silly-tavern-docker-starts/main/linux-deploy-new-api-r2.sh > /tmp/deploy-script.sh && chmod +x /tmp/deploy-script.sh && /tmp/deploy-script.sh"
        exit 1
    fi
    echo -e "${GREEN}使用R2配置: Bucket=$R2_BUCKET${NC}"
fi

# 创建必要的目录
echo -e "${GREEN}创建必要的目录...${NC}"
mkdir -p $PROJECT_DIR/backup $PROJECT_DIR/backup-scripts $PROJECT_DIR/mysql $PROJECT_DIR/data $PROJECT_DIR/logs

# 创建临时的配置信息文件
CONFIG_FILE="$PROJECT_DIR/backup/db-config-info.txt"
cat > $CONFIG_FILE << EOF
MySQL备份配置信息
=================
时间: $(date)
MySQL服务器: mysql
MySQL用户: $MYSQL_USER
MySQL密码: $MYSQL_PASSWORD
MySQL数据库: $MYSQL_DATABASE
R2存储桶: $R2_BUCKET
备份频率: 每10分钟一次
保留版本数: 150个
EOF

# 创建备份脚本
echo -e "${GREEN}创建备份脚本...${NC}"
cat > $PROJECT_DIR/backup-scripts/backup.sh << 'BACKUPEOF'
#!/bin/sh

# 设置变量
TIMESTAMP=$(date +"%Y%m%d%H%M")
BACKUP_FILE="/backup/$MYSQL_DATABASE-$TIMESTAMP.sql.gz"
MAX_BACKUPS=150

# 创建rclone配置（如果不存在）
if [ ! -f /root/.config/rclone/rclone.conf ]; then
    mkdir -p /root/.config/rclone
    cat > /root/.config/rclone/rclone.conf << RCLONECONF
[cloudflare]
type = s3
provider = Cloudflare
access_key_id = $R2_ACCESS_KEY
secret_access_key = $R2_SECRET_KEY
endpoint = $R2_ENDPOINT
acl = private
RCLONECONF
fi

# 上传配置信息文件到R2（仅在首次运行时）
if [ ! -f /backup/.config_uploaded ]; then
    echo "上传数据库配置信息到R2..."
    rclone copy /backup/db-config-info.txt cloudflare:$R2_BUCKET/config/
    touch /backup/.config_uploaded
fi

# 执行备份并压缩
echo "开始备份数据库 $MYSQL_DATABASE 到 $BACKUP_FILE..."
mysqldump -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE | gzip > $BACKUP_FILE

# 如果备份成功，上传到CF R2
if [ $? -eq 0 ]; then
    echo "备份成功，正在上传到Cloudflare R2..."

    # 上传到R2
    rclone copy $BACKUP_FILE cloudflare:$R2_BUCKET/mysql_backups/

    # 记录日志
    echo "$(date): 备份成功并上传至CF R2: $BACKUP_FILE" >> /backup/backup.log

    echo "清理本地旧备份，仅保留最新的$MAX_BACKUPS个版本..."
    # 获取文件列表，按时间排序，保留最新的MAX_BACKUPS个文件
    ls -t /backup/*.sql.gz 2>/dev/null | awk "NR>$MAX_BACKUPS" | xargs -r rm

    echo "清理R2旧备份，仅保留最新的$MAX_BACKUPS个版本..."
    # 列出R2中的文件，按时间排序，删除旧文件
    BACKUP_FILES=$(rclone lsf cloudflare:$R2_BUCKET/mysql_backups/ --format tp | sort -r)
    COUNT=$(echo "$BACKUP_FILES" | wc -l)

    if [ "$COUNT" -gt "$MAX_BACKUPS" ]; then
        echo "$BACKUP_FILES" | tail -n $(($COUNT - $MAX_BACKUPS)) | while read FILE; do
            echo "删除旧备份: $FILE"
            rclone delete "cloudflare:$R2_BUCKET/mysql_backups/$FILE"
        done
    fi

    echo "备份流程完成"
else
    echo "$(date): 备份失败" >> /backup/backup.log
    echo "备份失败，请检查日志"
fi
BACKUPEOF

# 替换备份脚本中的变量
sed -i "s|\$R2_ACCESS_KEY|$R2_ACCESS_KEY|g" $PROJECT_DIR/backup-scripts/backup.sh
sed -i "s|\$R2_SECRET_KEY|$R2_SECRET_KEY|g" $PROJECT_DIR/backup-scripts/backup.sh
sed -i "s|\$R2_ENDPOINT|$R2_ENDPOINT|g" $PROJECT_DIR/backup-scripts/backup.sh
sed -i "s|\$R2_BUCKET|$R2_BUCKET|g" $PROJECT_DIR/backup-scripts/backup.sh

# 创建cron设置脚本
echo -e "${GREEN}创建cron设置脚本...${NC}"
cat > $PROJECT_DIR/backup-scripts/setup-cron.sh << 'CRONEOF'
#!/bin/sh

# 创建crontab文件
echo "*/10 * * * * /usr/local/bin/backup.sh >> /backup/cron.log 2>&1" > /var/spool/cron/crontabs/root

# 确保备份日志被创建并有正确权限
touch /backup/backup.log /backup/cron.log
chmod 644 /backup/backup.log /backup/cron.log

echo "已设置cron任务，每10分钟执行一次备份"

# 启动cron并保持容器运行
crond -f
CRONEOF

# 设置脚本权限
echo -e "${GREEN}设置脚本权限...${NC}"
chmod +x $PROJECT_DIR/backup-scripts/backup.sh $PROJECT_DIR/backup-scripts/setup-cron.sh

# 创建或修改docker-compose.yml
echo -e "${GREEN}修改docker-compose.yml...${NC}"

# 保存原始docker-compose.yml
if [ -f $PROJECT_DIR/docker-compose.yml ]; then
    cp $PROJECT_DIR/docker-compose.yml $PROJECT_DIR/docker-compose.yml.bak
    echo -e "${GREEN}已创建docker-compose.yml备份为docker-compose.yml.bak${NC}"
fi

# 创建新的docker-compose.yml
cat > $PROJECT_DIR/docker-compose.yml << EOF
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
    healthcheck:
      test: ["CMD-SHELL", "wget -q -O - http://localhost:3000/api/status | grep -o '\"success\":\\s*true' | awk -F: '{print \$\$2}'"]
      interval: 30s
      timeout: 10s
      retries: 3

  redis:
    image: redis:latest
    container_name: redis
    restart: always

  mysql:
    image: mysql:8.2
    container_name: mysql
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: $MYSQL_PASSWORD
      MYSQL_DATABASE: $MYSQL_DATABASE
      MYSQL_USER: $MYSQL_USER
      MYSQL_PASSWORD: $MYSQL_PASSWORD
    volumes:
      - mysql_data:/var/lib/mysql

  # MySQL备份服务
  mysql-backup:
    image: alpine:latest
    container_name: mysql-backup
    restart: always
    volumes:
      - ./backup:/backup
      - ./backup-scripts:/scripts
    environment:
      - MYSQL_HOST=mysql
      - MYSQL_USER=$MYSQL_USER
      - MYSQL_PASSWORD=$MYSQL_PASSWORD
      - MYSQL_DATABASE=$MYSQL_DATABASE
      - TZ=Asia/Shanghai
    depends_on:
      - mysql
    command: sh -c "apk add --no-cache mysql-client gzip curl tzdata && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && curl -O https://rclone.org/install.sh && chmod +x install.sh && ./install.sh && cp /scripts/backup.sh /usr/local/bin/ && chmod +x /usr/local/bin/backup.sh && /scripts/setup-cron.sh"

volumes:
  mysql_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $PROJECT_DIR/mysql
EOF

# 创建恢复脚本
echo -e "${GREEN}创建恢复脚本...${NC}"
cat > $PROJECT_DIR/restore-mysql-backup.sh << 'RESTOREEOF'
#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 这些变量将在脚本创建时替换
R2_BUCKET="__R2_BUCKET__"
MYSQL_USER="__MYSQL_USER__"
MYSQL_PASSWORD="__MYSQL_PASSWORD__"
MYSQL_DATABASE="__MYSQL_DATABASE__"
BACKUP_DIR="/data/docker/new-api/backup"

echo -e "${YELLOW}MySQL备份恢复工具${NC}"
echo -e "${GREEN}此工具将帮助您从Cloudflare R2恢复MySQL备份${NC}"
echo -e "${GREEN}数据库信息：用户 $MYSQL_USER, 数据库 $MYSQL_DATABASE${NC}"

# 检查mysql-backup容器是否运行
if ! docker ps | grep -q mysql-backup; then
    echo -e "${RED}错误: mysql-backup容器未运行${NC}"
    echo -e "请确保先运行部署脚本并启动服务"
    exit 1
fi

# 列出可用备份
echo -e "${YELLOW}正在从R2获取备份列表...${NC}"
BACKUP_LIST=$(docker exec mysql-backup rclone lsf cloudflare:$R2_BUCKET/mysql_backups/ --format "tp")

if [ -z "$BACKUP_LIST" ]; then
    echo -e "${RED}未找到备份文件${NC}"
    exit 1
fi

# 显示备份列表，按日期排序（最新的在上面）
echo -e "${GREEN}可用备份:${NC}"
echo "$BACKUP_LIST" | sort -r | nl

# 询问要恢复的备份编号
echo -e "${YELLOW}请输入要恢复的备份编号 (1是最新备份):${NC}"
read -p "编号: " BACKUP_NUMBER

# 验证输入
if ! [[ "$BACKUP_NUMBER" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}错误: 请输入有效的数字${NC}"
    exit 1
fi

# 获取选择的备份文件名
SELECTED_BACKUP=$(echo "$BACKUP_LIST" | sort -r | sed -n "${BACKUP_NUMBER}p")

if [ -z "$SELECTED_BACKUP" ]; then
    echo -e "${RED}错误: 无效的备份编号${NC}"
    exit 1
fi

echo -e "${GREEN}您选择的备份: $SELECTED_BACKUP${NC}"

# 询问确认
read -p "确认恢复此备份? 这将覆盖当前数据库内容! (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo -e "${YELLOW}操作已取消${NC}"
    exit 0
fi

# 下载并恢复备份
echo -e "${YELLOW}正在从R2下载备份...${NC}"
docker exec mysql-backup rclone copy cloudflare:$R2_BUCKET/mysql_backups/$SELECTED_BACKUP /backup/

if [ $? -ne 0 ]; then
    echo -e "${RED}下载备份失败${NC}"
    exit 1
fi

echo -e "${YELLOW}正在恢复数据库...${NC}"
docker exec mysql-backup sh -c "gunzip -c /backup/$SELECTED_BACKUP | mysql -h mysql -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}数据库恢复成功!${NC}"
else
    echo -e "${RED}数据库恢复失败!${NC}"
    exit 1
fi

echo -e "${GREEN}操作完成${NC}"
RESTOREEOF

# 替换恢复脚本中的变量
sed -i "s|__R2_BUCKET__|$R2_BUCKET|g" $PROJECT_DIR/restore-mysql-backup.sh
sed -i "s|__MYSQL_USER__|$MYSQL_USER|g" $PROJECT_DIR/restore-mysql-backup.sh
sed -i "s|__MYSQL_PASSWORD__|$MYSQL_PASSWORD|g" $PROJECT_DIR/restore-mysql-backup.sh
sed -i "s|__MYSQL_DATABASE__|$MYSQL_DATABASE|g" $PROJECT_DIR/restore-mysql-backup.sh

# 设置恢复脚本权限
chmod +x $PROJECT_DIR/restore-mysql-backup.sh

echo -e "${GREEN}配置完成！${NC}"
echo -e "${YELLOW}系统已配置：${NC}"
echo -e "1. 每10分钟备份一次MySQL数据到Cloudflare R2"
echo -e "2. 本地和R2存储中均只保留最近150个备份"
echo -e "3. 备份日志保存在 $PROJECT_DIR/backup/backup.log"
echo -e "4. 恢复脚本已创建: $PROJECT_DIR/restore-mysql-backup.sh"

# 询问是否立即启动服务
if [ "$INTERACTIVE" = true ]; then
    read -p "是否立即启动服务？(y/n): " START_SERVICE
    if [[ "$START_SERVICE" == "y" || "$START_SERVICE" == "Y" ]]; then
        echo -e "${GREEN}启动服务...${NC}"
        cd $PROJECT_DIR && $DOCKER_COMPOSE down && $DOCKER_COMPOSE up -d

        echo -e "${GREEN}服务已启动！${NC}"
        echo -e "${YELLOW}您可以通过以下命令检查备份服务状态：${NC}"
        echo -e "docker logs mysql-backup"
    else
        echo -e "${YELLOW}您可以稍后通过以下命令启动服务：${NC}"
        echo -e "cd $PROJECT_DIR && docker-compose up -d"
    fi
else
    # 非交互模式下自动启动服务
    echo -e "${GREEN}自动启动服务...${NC}"
    cd $PROJECT_DIR && $DOCKER_COMPOSE down && $DOCKER_COMPOSE up -d
    echo -e "${GREEN}服务已启动！${NC}"
fi

echo -e "${GREEN}脚本执行完毕！${NC}"

