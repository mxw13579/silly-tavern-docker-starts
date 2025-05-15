#!/usr/bin/env bash
# r2-backup-setup.sh  (兼安装 / 升级 / 恢复)
set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
BASE_DIR="/opt/r2-backup"
BACKUP_SH="$BASE_DIR/backup.sh"
RESTORE_SH="$BASE_DIR/restore.sh"
SERVICE=/etc/systemd/system/r2-backup.service
TIMER=/etc/systemd/system/r2-backup.timer
REMOTE_NAME="cf_r2"

need_root() { [ "$(id -u)" -eq 0 ] || { echo -e "${RED}请以 root 执行${NC}"; exit 1; }; }
need_root

#--------------------------------------------------#
# A. 若已安装 => 询问处理方式
#--------------------------------------------------#
if [ -f "$BACKUP_SH" ] && systemctl list-unit-files | grep -q r2-backup.timer; then
  echo -e "${GREEN}已检测到现有备份服务 (r2-backup.timer)${NC}"
  read -rp "$(echo -e ${YELLOW}是否修改备份配置?[y/N]: ${NC})" CHG
  if [[ ! $CHG =~ ^[Yy]$ ]]; then
    read -rp "$(echo -e ${YELLOW}是否现在执行恢复流程?[y/N]: ${NC})" DO_RESTORE
    if [[ $DO_RESTORE =~ ^[Yy]$ ]]; then
      bash "$RESTORE_SH"
    fi
    exit 0
  fi
  echo -e "${YELLOW}→ 将进入配置更新流程${NC}"
fi

#--------------------------------------------------#
# B. 收集新配置
#--------------------------------------------------#
read -rp "1) 请输入要备份的文件/目录绝对路径: " TARGET_PATH
[ -e "$TARGET_PATH" ] || { echo -e "${RED}路径不存在${NC}"; exit 1; }
TARGET_PATH=$(realpath "$TARGET_PATH")

read -rp "2) R2 Access Key: " R2_ACCESS_KEY
read -rp "3) R2 Secret Key: " R2_SECRET_KEY
read -rp "4) R2 Bucket Name: " R2_BUCKET
read -rp "5) R2 Endpoint (例 https://xxx.r2.cloudflarestorage.com): " R2_ENDPOINT

read -rp "6) 备份间隔(30m 6h 1d 2w，默认1d): " PERIOD
PERIOD=${PERIOD:-1d}
[[ $PERIOD =~ ^[0-9]+[smhdw]$ ]] || { echo -e "${RED}格式错误${NC}"; exit 1; }

read -rp "7) 仅保留最新几份备份(默认10): " KEEP
KEEP=${KEEP:-10}
[[ $KEEP =~ ^[0-9]+$ ]] || { echo -e "${RED}请输入数字${NC}"; exit 1; }

#--------------------------------------------------#
# C. 安装 rclone (若无)
#--------------------------------------------------#
if ! command -v rclone >/dev/null; then
  echo -e "${YELLOW}安装 rclone ...${NC}"
  curl -fsSL https://rclone.org/install.sh | bash
fi

mkdir -p /root/.config/rclone
cat > /root/.config/rclone/rclone.conf <<EOF
[$REMOTE_NAME]
type = s3
provider = Cloudflare
access_key_id = $R2_ACCESS_KEY
secret_access_key = $R2_SECRET_KEY
endpoint = $R2_ENDPOINT
acl = private
EOF

#--------------------------------------------------#
# D. 若 bucket 中已有备份 → 提示恢复
#--------------------------------------------------#
echo -e "${GREEN}检查 R2 bucket 是否已有备份...${NC}"
if rclone lsf "$REMOTE_NAME:$R2_BUCKET/backups/" --format p 2>/dev/null | grep -q . ; then
  echo -e "${YELLOW}检测到 R2/backups 目录已有数据${NC}"
  read -rp "$(echo -e ${YELLOW}是否立即进入恢复流程?[y/N]: ${NC})" NEED_RESTORE
  if [[ $NEED_RESTORE =~ ^[Yy]$ ]]; then
    # 生成临时恢复脚本所需占位符并执行一次恢复脚本
    export __TMP_REMOTE=$REMOTE_NAME __TMP_BUCKET=$R2_BUCKET
    bash -c '
      TMP=/tmp/tmp-restore.sh
      cat >$TMP <<EOF
#!/usr/bin/env bash
REMOTE="$__TMP_REMOTE"; BUCKET="$__TMP_BUCKET"
rclone lsf "\$REMOTE:\$BUCKET/backups/" --format p | nl
echo 仅查看列表，完整恢复请等新脚本生成后运行
EOF'; unset __TMP_REMOTE __TMP_BUCKET
  fi
fi

#--------------------------------------------------#
# E. 写入脚本 / systemd
#--------------------------------------------------#
mkdir -p "$BASE_DIR"

# 1. 备份脚本
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
  rclone copy /tmp/backup-info.txt "$REMOTE:$BUCKET/config/"
fi

tar -czf "$ARCHIVE" -C "$(dirname "$TARGET_PATH")" "$NAME"
rclone copy "$ARCHIVE" "$REMOTE:$BUCKET/backups/"

CNT=$(rclone lsf "$REMOTE:$BUCKET/backups/" --format p | wc -l)
if [ "$CNT" -gt "$KEEP" ]; then
  DEL=$((CNT-KEEP))
  rclone lsf "$REMOTE:$BUCKET/backups/" --format p | sort | head -n $DEL | \
    while read f; do rclone delete "$REMOTE:$BUCKET/backups/$f"; done
fi
rm -f "$ARCHIVE"
BACKUP_EOF
chmod +x "$BACKUP_SH"
sed -i -e "s|__TARGET_PATH__|$TARGET_PATH|g" \
       -e "s|__REMOTE__|$REMOTE_NAME|g" \
       -e "s|__BUCKET__|$R2_BUCKET|g" \
       -e "s|__KEEP__|$KEEP|g" "$BACKUP_SH"

# 2. systemd unit/timer
SYSD="${PERIOD: -1}"; NUM="${PERIOD%$SYSD}"
case $SYSD in s) SYSP="${NUM}sec";; m) SYSP="${NUM}min";; h) SYSP="${NUM}hour";; d) SYSP="${NUM}day";; w) SYSP="${NUM}week";; esac

cat > "$SERVICE" <<EOF
[Unit]
Description=Cloudflare R2 Backup Service

[Service]
Type=oneshot
ExecStart=$BACKUP_SH
EOF

cat > "$TIMER" <<EOF
[Unit]
Description=Run R2 Backup each $SYSP

[Timer]
OnBootSec=1min
OnUnitActiveSec=$SYSP
Unit=r2-backup.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now r2-backup.timer

# 3. 恢复脚本
cat > "$RESTORE_SH" <<'RESTORE_EOF'
#!/usr/bin/env bash
set -e
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
REMOTE="__REMOTE__"; BUCKET="__BUCKET__"
TMP=/tmp/r2-restore; mkdir -p $TMP

rclone copy "$REMOTE:$BUCKET/config/backup-info.txt" $TMP --quiet
source $TMP/backup-info.txt || { echo -e "${RED}无法读取 config/backup-info.txt${NC}"; exit 1; }

echo -e "目标路径: $TARGET_PATH"
LIST=$(rclone lsf "$REMOTE:$BUCKET/backups/" --format p | sort -r)
[ -z "$LIST" ] && { echo -e "${RED}无可用备份${NC}"; exit 1; }

echo "$LIST" | nl
read -rp "$(echo -e ${YELLOW}选择编号: ${NC})" NO
SEL=$(echo "$LIST" | sed -n "${NO}p")
[ -z "$SEL" ] && { echo -e "${RED}编号无效${NC}"; exit 1; }

read -rp "确认恢复 $SEL ? (y/N): " C
[[ $C != y && $C != Y ]] && exit 0

rclone copy "$REMOTE:$BUCKET/backups/$SEL" $TMP --quiet
tar -xzf "$TMP/$SEL" -C "$(dirname "$TARGET_PATH")"
echo -e "${GREEN}恢复完成${NC}"
RESTORE_EOF
chmod +x "$RESTORE_SH"
sed -i -e "s|__REMOTE__|$REMOTE_NAME|g" \
       -e "s|__BUCKET__|$R2_BUCKET|g" "$RESTORE_SH"

#--------------------------------------------------#
# F. 完成
#--------------------------------------------------#
echo -e "${GREEN}✔ 备份计划已配置，每 $PERIOD 备份一次，保留 $KEEP 份${NC}"
echo -e "• 备份脚本: $BACKUP_SH"
echo -e "• 恢复脚本: $RESTORE_SH"
echo -e "• systemd timer 已启动 (r2-backup.timer)"

read -rp "$(echo -e ${YELLOW}是否立即执行一次恢复脚本?[y/N]: ${NC})" R
[[ $R =~ ^[Yy]$ ]] && bash "$RESTORE_SH"
