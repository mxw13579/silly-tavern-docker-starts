#!/bin/bash
# linux-deploy-new-api-r2.sh
# 一键部署 new-api 服务 + MySQL + Redis 并启用 R2 备份

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

echo -e "${YELLOW}开始配置 MySQL 到 Cloudflare R2 的备份服务...${NC}"

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

#---------------- Cloudflare R2 配置 ---------------
if $INTERACTIVE; then
    read -p "R2 Access Key: " R2_ACCESS_KEY
    read -p "R2 Secret Key: " R2_SECRET_KEY
    read -p "R2 Bucket Name: " R2_BUCKET
    read -p "R2 Endpoint (如: https://xxxxx.r2.cloudflarestorage.com): " R2_ENDPOINT
else
    : "${R2_ACCESS_KEY:?非交互模式必须设置 R2_ACCESS_KEY}"
    : "${R2_SECRET_KEY:?非交互模式必须设置 R2_SECRET_KEY}"
    : "${R2_BUCKET:?非交互模式必须设置 R2_BUCKET}"
    : "${R2_ENDPOINT:?非交互模式必须设置 R2_ENDPOINT}"
fi
echo -e "${GREEN}R2 Bucket => $R2_BUCKET${NC}"

#--------------------------------------------------
# 创建目录结构
#--------------------------------------------------
mkdir -p "$PROJECT_DIR/backup" \
         "$PROJECT_DIR/backup-scripts" \
         "$PROJECT_DIR/mysql" \
         "$PROJECT_DIR/data" \
         "$PROJECT_DIR/logs"

#--------------------------------------------------
# 写入配置说明文件（稍后由备份脚本上传）
#--------------------------------------------------
cat > "$PROJECT_DIR/backup/db-config-info.txt" <<EOF
MySQL 备份配置说明
========================
时间            : $(date)
MySQL 用户       : $MYSQL_USER
MySQL 密码       : $MYSQL_PASSWORD
MySQL 数据库     : $MYSQL_DATABASE
R2 Bucket        : $R2_BUCKET
备份频率         : 10 分钟
保留版本         : 150
EOF

#--------------------------------------------------
# 生成 backup.sh (占位符后续 sed)
#--------------------------------------------------
cat > "$PROJECT_DIR/backup-scripts/backup.sh" <<'BACKUP_EOF'
#!/bin/sh
TIMESTAMP=$(date +"%Y%m%d%H%M")
BACKUP_FILE="/backup/$MYSQL_DATABASE-$TIMESTAMP.sql.gz"
MAX_BACKUPS=150

# ---------- rclone config ----------
if [ ! -f /root/.config/rclone/rclone.conf ]; then
  mkdir -p /root/.config/rclone
  cat > /root/.config/rclone/rclone.conf <<RCLONECONF
[cloudflare]
type = s3
provider = Cloudflare
access_key_id = __R2_ACCESS_KEY__
secret_access_key = __R2_SECRET_KEY__
endpoint = __R2_ENDPOINT__
acl = private
RCLONECONF
fi

# ---------- 首次上传说明文件 ----------
if [ ! -f /backup/.config_uploaded ]; then
  rclone copy /backup/db-config-info.txt cloudflare:__R2_BUCKET__/config/
  touch /backup/.config_uploaded
fi

# ---------- 备份 ----------
echo "开始备份 $MYSQL_DATABASE ..."
mysqldump -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE 2>/backup/error.log | gzip > "$BACKUP_FILE"

if [ $? -eq 0 ]; then
  echo "上传到 R2..."
  rclone copy "$BACKUP_FILE" cloudflare:__R2_BUCKET__/mysql_backups/

  # 保留本地 150 份
  ls -t /backup/*.sql.gz 2>/dev/null | awk "NR>$MAX_BACKUPS" | xargs -r rm
  # 保留远端 150 份
  CNT=$(rclone lsf cloudflare:__R2_BUCKET__/mysql_backups/ --format t | wc -l)
  if [ "$CNT" -gt "$MAX_BACKUPS" ]; then
    rclone lsf cloudflare:__R2_BUCKET__/mysql_backups/ --format tp | sort -r | tail -n $(("$CNT"-"$MAX_BACKUPS")) | \
    while read f; do rclone delete "cloudflare:__R2_BUCKET__/mysql_backups/$f"; done
  fi
  echo "$(date): 成功完成一次备份" >> /backup/backup.log
else
  echo "$(date): 备份失败，请查看 error.log" >> /backup/backup.log
fi
BACKUP_EOF

# 替换占位符
sed -i "s|__R2_ACCESS_KEY__|$R2_ACCESS_KEY|g" "$PROJECT_DIR/backup-scripts/backup.sh"
sed -i "s|__R2_SECRET_KEY__|$R2_SECRET_KEY|g" "$PROJECT_DIR/backup-scripts/backup.sh"
sed -i "s|__R2_ENDPOINT__|$R2_ENDPOINT|g"     "$PROJECT_DIR/backup-scripts/backup.sh"
sed -i "s|__R2_BUCKET__|$R2_BUCKET|g"         "$PROJECT_DIR/backup-scripts/backup.sh"

chmod +x "$PROJECT_DIR/backup-scripts/backup.sh"

#--------------------------------------------------
# 生成 setup-cron.sh
#--------------------------------------------------
cat > "$PROJECT_DIR/backup-scripts/setup-cron.sh" <<'CRON_EOF'
#!/bin/sh
echo "*/10 * * * * /usr/local/bin/backup.sh >> /backup/cron.log 2>&1" > /var/spool/cron/crontabs/root
crond -f
CRON_EOF
chmod +x "$PROJECT_DIR/backup-scripts/setup-cron.sh"

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
    command: >
      sh -c "apk add --no-cache mysql-client gzip curl tzdata rclone &&
             cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime &&
             cp /scripts/backup.sh /usr/local/bin/backup.sh &&
             chmod +x /usr/local/bin/backup.sh &&
             /scripts/setup-cron.sh"

volumes:
  mysql_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $PROJECT_DIR/mysql
EOF

#--------------------------------------------------
# 生成恢复脚本
#--------------------------------------------------
cat > "$PROJECT_DIR/restore-mysql-backup.sh" <<'RESTORE_EOF'
#!/bin/bash
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

R2_BUCKET="__R2_BUCKET__"
MYSQL_USER="__MYSQL_USER__"
MYSQL_PASSWORD="__MYSQL_PASSWORD__"
MYSQL_DATABASE="__MYSQL_DATABASE__"

if ! docker ps | grep -q mysql-backup; then
  echo -e "${RED}mysql-backup 容器未运行${NC}"; exit 1
fi

echo -e "${GREEN}从 R2 读取备份列表...${NC}"
LIST=$(docker exec mysql-backup rclone lsf cloudflare:$R2_BUCKET/mysql_backups/ --format "tp" | sort -r)
[ -z "$LIST" ] && { echo -e "${RED}没有备份文件${NC}"; exit 1; }

echo "$LIST" | nl
read -p "$(echo -e ${YELLOW}选择要恢复的编号: ${NC})" NO
SEL=$(echo "$LIST" | sed -n "${NO}p")
[ -z "$SEL" ] && { echo -e "${RED}编号无效${NC}"; exit 1; }

read -p "确认恢复 $SEL ? (y/n): " CFM
[[ $CFM != y && $CFM != Y ]] && exit 0

docker exec mysql-backup rclone copy cloudflare:$R2_BUCKET/mysql_backups/$SEL /backup/ || { echo -e "${RED}下载失败${NC}"; exit 1; }
docker exec mysql-backup sh -c "gunzip -c /backup/$SEL | mysql -h mysql -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" \
    && echo -e "${GREEN}恢复完成${NC}" \
    || echo -e "${RED}恢复失败${NC}"
RESTORE_EOF
sed -i "s|__R2_BUCKET__|$R2_BUCKET|g"       "$PROJECT_DIR/restore-mysql-backup.sh"
sed -i "s|__MYSQL_USER__|$MYSQL_USER|g"     "$PROJECT_DIR/restore-mysql-backup.sh"
sed -i "s|__MYSQL_PASSWORD__|$MYSQL_PASSWORD|g" "$PROJECT_DIR/restore-mysql-backup.sh"
sed -i "s|__MYSQL_DATABASE__|$MYSQL_DATABASE|g" "$PROJECT_DIR/restore-mysql-backup.sh"
chmod +x "$PROJECT_DIR/restore-mysql-backup.sh"

#--------------------------------------------------
# 启动服务
#--------------------------------------------------
if $INTERACTIVE; then
    read -p "是否立即启动服务？(y/n): " R
    [[ $R != y && $R != Y ]] && { echo -e "${YELLOW}稍后可手动执行: cd $PROJECT_DIR && $DOCKER_COMPOSE up -d${NC}"; exit 0; }
fi
echo -e "${GREEN}启动服务...${NC}"
cd "$PROJECT_DIR" && $DOCKER_COMPOSE down && $DOCKER_COMPOSE up -d
echo -e "${GREEN}所有容器已启动，可查看 docker ps${NC}"
echo -e "${YELLOW}备份日志: $PROJECT_DIR/backup/backup.log${NC}"
echo -e "${YELLOW}恢复脚本: $PROJECT_DIR/restore-mysql-backup.sh${NC}"
