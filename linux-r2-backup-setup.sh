#!/usr/bin/env bash
# r2-backup-setup.sh     (安装 / 升级 / 备份 / 恢复)
set -e

#------------------- 基本变量 --------------------#
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

BASE_DIR="/opt/r2-backup"
BACKUP_SH="$BASE_DIR/backup.sh"
RESTORE_SH="$BASE_DIR/restore.sh"
SERVICE="/etc/systemd/system/r2-backup.service"
TIMER="/etc/systemd/system/r2-backup.timer"
REMOTE_NAME="cf_r2"
RCLONE_CONF="/root/.config/rclone/rclone.conf"

need_root() { [ "$(id -u)" -eq 0 ] || { echo -e "${RED}请以 root 身份执行${NC}"; exit 1; }; }
need_root

#---------------- 读取现有配置 (若有) --------------#
OLD_TARGET=""; OLD_KEEP=""; OLD_BUCKET=""
OLD_PERIOD_RAW=""; OLD_PERIOD=""
OLD_ACCESS=""; OLD_SECRET=""; OLD_ENDPOINT=""

if [ -f "$BACKUP_SH" ]; then
  OLD_TARGET=$(grep '^TARGET_PATH=' "$BACKUP_SH" | cut -d'"' -f2)
  OLD_KEEP=$(grep '^KEEP='        "$BACKUP_SH" | cut -d'"' -f2)
  OLD_BUCKET=$(grep '^BUCKET='     "$BACKUP_SH" | cut -d'"' -f2)
fi

if [ -f "$TIMER" ]; then
  OLD_PERIOD_RAW=$(grep '^OnUnitActiveSec=' "$TIMER" | cut -d= -f2)
  if [[ $OLD_PERIOD_RAW =~ ^([0-9]+)(sec|min|hour|day|week)$ ]]; then
    NUM=${BASH_REMATCH[1]}; UNIT=${BASH_REMATCH[2]}
    case $UNIT in
      sec)  OLD_PERIOD="${NUM}s" ;;
      min)  OLD_PERIOD="${NUM}m" ;;
      hour) OLD_PERIOD="${NUM}h" ;;
      day)  OLD_PERIOD="${NUM}d" ;;
      week) OLD_PERIOD="${NUM}w" ;;
    esac
  fi
fi

if [ -f "$RCLONE_CONF" ]; then
  OLD_ACCESS=$(awk -v s="[$REMOTE_NAME]" '
      $0==s{f=1;next} /^\[/{f=0}
      f && $1=="access_key_id"     {print $3}
  ' "$RCLONE_CONF")
  OLD_SECRET=$(awk -v s="[$REMOTE_NAME]" '
      $0==s{f=1;next} /^\[/{f=0}
      f && $1=="secret_access_key" {print $3}
  ' "$RCLONE_CONF")
  OLD_ENDPOINT=$(awk -v s="[$REMOTE_NAME]" '
      $0==s{f=1;next} /^\[/{f=0}
      f && $1=="endpoint"          {print $3}
  ' "$RCLONE_CONF")
fi

#------------- 如果已安装，给出 3 个操作 -------------#
if [ -f "$BACKUP_SH" ] && systemctl list-unit-files | grep -q '^r2-backup.timer'; then
  echo -e "${GREEN}检测到已安装的 r2-backup 服务${NC}"

  read -rp "$(echo -e ${YELLOW}是否修改备份配置?[y/N]: ${NC})" CHG
  if [[ ! $CHG =~ ^[Yy]$ ]]; then
    read -rp "$(echo -e ${YELLOW}是否现在执行恢复流程?[y/N]: ${NC})" DO_RESTORE
    if [[ $DO_RESTORE =~ ^[Yy]$ ]]; then
      bash "$RESTORE_SH"; fi

    read -rp "$(echo -e ${YELLOW}是否现在立即备份一次?[y/N]: ${NC})" DO_BAK
    if [[ $DO_BAK =~ ^[Yy]$ ]]; then
      bash "$BACKUP_SH"; fi
    exit 0
  fi
  echo -e "${YELLOW}→ 进入配置修改流程 (直接回车可保持原值)${NC}"
fi

#----------------- 收集 / 修改配置 ------------------#
read -rp "1) 请输入要备份的文件/目录绝对路径 [${OLD_TARGET:-无}]: " TARGET_PATH
TARGET_PATH=${TARGET_PATH:-$OLD_TARGET}
[ -z "$TARGET_PATH" ] && { echo -e "${RED}必须指定备份路径${NC}"; exit 1; }
[ -e "$TARGET_PATH" ]  || { echo -e "${RED}路径不存在${NC}"; exit 1; }
TARGET_PATH=$(realpath "$TARGET_PATH")

# 访问密钥
read -rp "2) R2 Access Key [${OLD_ACCESS:-无}]: " R2_ACCESS_KEY
R2_ACCESS_KEY=${R2_ACCESS_KEY:-$OLD_ACCESS}
read -rp "3) R2 Secret Key (留空保持不变): " R2_SECRET_KEY
[ -z "$R2_SECRET_KEY" ] && R2_SECRET_KEY=$OLD_SECRET

read -rp "4) R2 Bucket Name [${OLD_BUCKET:-无}]: " R2_BUCKET
R2_BUCKET=${R2_BUCKET:-$OLD_BUCKET}

read -rp "5) R2 Endpoint (例 https://xxx.r2.cloudflarestorage.com) [${OLD_ENDPOINT:-无}]: " R2_ENDPOINT
R2_ENDPOINT=${R2_ENDPOINT:-$OLD_ENDPOINT}

read -rp "6) 备份间隔(30m 6h 1d 2w) [${OLD_PERIOD:-1d}]: " PERIOD
PERIOD=${PERIOD:-${OLD_PERIOD:-1d}}
[[ $PERIOD =~ ^[0-9]+[smhdw]$ ]] || { echo -e "${RED}格式错误${NC}"; exit 1; }

read -rp "7) 仅保留最新几份备份(默认10) [${OLD_KEEP:-10}]: " KEEP
KEEP=${KEEP:-${OLD_KEEP:-10}}
[[ $KEEP =~ ^[0-9]+$ ]] || { echo -e "${RED}请输入数字${NC}"; exit 1; }

#-------------------- 安装 rclone -------------------#
if ! command -v unzip >/dev/null; then
  echo "installing unzip..."
  if   command -v apt-get >/dev/null; then apt-get  update -y && apt-get  install -y unzip;
  elif command -v yum     >/dev/null; then yum      install -y unzip;
  elif command -v apk     >/dev/null; then apk      add unzip; fi
fi

if ! command -v rclone >/dev/null; then
  echo -e "${YELLOW}安装 rclone ...${NC}"
  curl -fsSL https://rclone.org/install.sh | bash
fi

#------------- 写入 / 更新 rclone.conf --------------#
mkdir -p /root/.config/rclone
if [ -f "$RCLONE_CONF" ]; then
  awk -v s="[$REMOTE_NAME]" '
      $0==s{f=1;next}
      /^\[/{f=0}
      !f' "$RCLONE_CONF" > /tmp/rclone.tmp || true
  mv /tmp/rclone.tmp "$RCLONE_CONF"
fi

cat >> "$RCLONE_CONF" <<EOF
[$REMOTE_NAME]
type = s3
provider = Cloudflare
access_key_id = $R2_ACCESS_KEY
secret_access_key = $R2_SECRET_KEY
endpoint = $R2_ENDPOINT
acl = private
EOF

#------------ 判断远端是否已有备份文件 -------------#
HAS_BAK=0
if rclone lsf "$REMOTE_NAME:$R2_BUCKET/backups/" --format p 2>/dev/null | grep -q . ; then
  HAS_BAK=1
fi

#---------------- 创建脚本目录 ---------------------#
mkdir -p "$BASE_DIR"

#================== 生成 backup.sh =================#
cat > "$BACKUP_SH" <<'BACKUP_EOF'
#!/usr/bin/env bash
set -e
TARGET_PATH="__TARGET_PATH__"
REMOTE="__REMOTE__"
BUCKET="__BUCKET__"
KEEP="__KEEP__"

STAMP=$(date +%Y%m%d%H%M%S)
WORK=/tmp/r2-backup; mkdir -p "$WORK"
NAME=$(basename "$TARGET_PATH")
ARCHIVE="$WORK/${NAME}-${STAMP}.tar.gz"

# 首次写入 config
if ! rclone ls "$REMOTE:$BUCKET/config/backup-info.txt" &>/dev/null; then
  echo "TARGET_PATH=$TARGET_PATH" >/tmp/backup-info.txt
  rclone copy /tmp/backup-info.txt "$REMOTE:$BUCKET/config/" --quiet
fi

tar -czf "$ARCHIVE" -C "$(dirname "$TARGET_PATH")" "$NAME"
rclone copy "$ARCHIVE" "$REMOTE:$BUCKET/backups/" --quiet

CNT=$(rclone lsf "$REMOTE:$BUCKET/backups/" --format p | wc -l)
if [ "$CNT" -gt "$KEEP" ]; then
  DEL=$((CNT-KEEP))
  rclone lsf "$REMOTE:$BUCKET/backups/" --format p | sort | head -n "$DEL" | \
  while read f; do
    rclone delete "$REMOTE:$BUCKET/backups/$f" --quiet
  done
fi
rm -f "$ARCHIVE"
BACKUP_EOF

chmod +x "$BACKUP_SH"
sed -i -e "s|__TARGET_PATH__|$TARGET_PATH|g" \
       -e "s|__REMOTE__|$REMOTE_NAME|g"  \
       -e "s|__BUCKET__|$R2_BUCKET|g"    \
       -e "s|__KEEP__|$KEEP|g"           "$BACKUP_SH"

#================== 生成 restore.sh ================#
cat > "$RESTORE_SH" <<'RESTORE_EOF'
#!/usr/bin/env bash
set -e
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
REMOTE="__REMOTE__"; BUCKET="__BUCKET__"
TMP=/tmp/r2-restore; mkdir -p "$TMP"

TARGET_PATH=""

# (1) 优先尝试读 backup-info.txt
if rclone ls "$REMOTE:$BUCKET/config/backup-info.txt" &>/dev/null; then
  rclone copy "$REMOTE:$BUCKET/config/backup-info.txt" "$TMP" --quiet
  if [ -f "$TMP/backup-info.txt" ]; then
    source "$TMP/backup-info.txt"
    echo -e "${GREEN}已读取配置，默认恢复到: $TARGET_PATH${NC}"
  fi
fi

# (2) 如仍无目标路径，让用户手动输入
while [ -z "$TARGET_PATH" ]; do
  read -rp "$(echo -e ${YELLOW}请输入要恢复到的绝对路径: ${NC})" TARGET_PATH
done

# (3) 获取可用备份并让用户选
LIST=$(rclone lsf "$REMOTE:$BUCKET/backups/" --format p 2>/dev/null | sort -r)
[ -z "$LIST" ] && { echo -e "${RED}远端没有可用备份${NC}"; exit 1; }

echo -e "${GREEN}可用备份:${NC}"
echo "$LIST" | nl
read -rp "$(echo -e ${YELLOW}请选择编号: ${NC})" IDX
SEL=$(echo "$LIST" | sed -n "${IDX}p")
[ -z "$SEL" ] && { echo -e "${RED}编号无效${NC}"; exit 1; }

read -rp "$(echo -e ${YELLOW}确认恢复 $SEL ? [y/N]: ${NC})" OK
[[ ! $OK =~ ^[Yy]$ ]] && exit 0

echo -e "${GREEN}开始恢复...${NC}"
rclone copy "$REMOTE:$BUCKET/backups/$SEL" "$TMP" --quiet
tar -xzf "$TMP/$SEL" -C "$(dirname "$TARGET_PATH")"

echo -e "${GREEN}✔ 恢复完成${NC}"
RESTORE_EOF

chmod +x "$RESTORE_SH"
sed -i -e "s|__REMOTE__|$REMOTE_NAME|g" \
       -e "s|__BUCKET__|$R2_BUCKET|g"   "$RESTORE_SH"

#================= 生成 systemd 单元 ================#
SYSD="${PERIOD: -1}"; NUM="${PERIOD%$SYSD}"
case $SYSD in
  s) SYSP="${NUM}sec"  ;;
  m) SYSP="${NUM}min"  ;;
  h) SYSP="${NUM}hour" ;;
  d) SYSP="${NUM}day"  ;;
  w) SYSP="${NUM}week" ;;
esac

cat > "$SERVICE" <<EOF
[Unit]
Description=Cloudflare R2 Backup Service

[Service]
Type=oneshot
ExecStart=$BACKUP_SH
EOF

cat > "$TIMER" <<EOF
[Unit]
Description=Run R2 Backup every $SYSP

[Timer]
OnBootSec=1min
OnUnitActiveSec=$SYSP
Unit=r2-backup.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now r2-backup.timer

#----------------------- 收尾 ----------------------#
echo -e "${GREEN}✔ 备份计划已配置，每 $PERIOD 备份一次，保留 $KEEP 份${NC}"
echo    "• 备份脚本 : $BACKUP_SH"
echo    "• 恢复脚本 : $RESTORE_SH"
echo    "• systemd   : r2-backup.timer 已启动"

# 远端有备份且本次未立即恢复时，再次提醒
if [ "$HAS_BAK" -eq 1 ]; then
  echo -e "${YELLOW}提示: 远端已有备份，可随时执行 $RESTORE_SH 进行恢复${NC}"
fi

# 询问是否立刻执行一次备份
read -rp "$(echo -e ${YELLOW}是否立即执行一次备份?[y/N]: ${NC})" DO_BAK
[[ $DO_BAK =~ ^[Yy]$ ]] && bash "$BACKUP_SH"
