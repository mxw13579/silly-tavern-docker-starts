cat > /tmp/fixed-r2-backup-setup.sh << 'EOF'
#!/usr/bin/env bash
# r2-backup-setup.sh    (安装 / 升级 / 备份 / 恢复 一体)
# 移除 set -e，改为在关键点检查错误
# set -e

# ---------- 常量 ----------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
BASE_DIR="/opt/r2-backup"
BACKUP_SH="$BASE_DIR/backup.sh"
RESTORE_SH="$BASE_DIR/restore.sh"
SERVICE=/etc/systemd/system/r2-backup.service
TIMER=/etc/systemd/system/r2-backup.timer
REMOTE_NAME="cf_r2"
RCLONE_CONF="/root/.config/rclone/rclone.conf"

need_root() { [ "$(id -u)" -eq 0 ] || { echo -e "${RED}请以 root 身份执行${NC}"; exit 1; }; }
need_root

# ---------- 读取现有配置（若有） ----------
# 更安全的配置读取函数
old() {
  if [ -f "$BACKUP_SH" ]; then
    awk -F'="' "/^$1=/"'{print $2}' "$BACKUP_SH" 2>/dev/null | tr -d '"' || echo ""
  else
    echo ""
  fi
}

# 读取主要配置
OLD_TARGET=$(old TARGET_PATH)
OLD_KEEP=$(old KEEP)
OLD_BUCKET=$(old BUCKET)
OLD_PERIOD=""

# 读取定时器配置
if [ -f "$TIMER" ]; then
  raw=$(grep '^OnUnitActiveSec=' "$TIMER" 2>/dev/null | cut -d= -f2) || raw=""
  if [[ $raw =~ ^([0-9]+)(sec|min|hour|day|week)$ ]]; then
    n=${BASH_REMATCH[1]} u=${BASH_REMATCH[2]}
    case $u in
      sec) OLD_PERIOD=${n}s ;;
      min) OLD_PERIOD=${n}m ;;
      hour) OLD_PERIOD=${n}h ;;
      day) OLD_PERIOD=${n}d ;;
      week) OLD_PERIOD=${n}w ;;
    esac
  fi
fi

# 更安全的读取 rclone 配置函数
read_rclone_field() {
  if [ -f "$RCLONE_CONF" ]; then
    awk -v s="[$REMOTE_NAME]" -v k="$1" '
      $0==s {f=1; next}
      /^\[/ {f=0}
      f && $1==k {print $3}
    ' "$RCLONE_CONF" 2>/dev/null || echo ""
  else
    echo ""
  fi
}

# 读取 rclone 配置
OLD_ACCESS=$(read_rclone_field access_key_id)
OLD_SECRET=$(read_rclone_field secret_access_key)
OLD_ENDPOINT=$(read_rclone_field endpoint)

# ---------- 检查现有安装并提供选项 ----------
if [ -f "$BACKUP_SH" ] && systemctl list-unit-files 2>/dev/null | grep -q '^r2-backup.timer'; then
  echo -e "${GREEN}检测到已安装的 r2-backup 服务${NC}"

  # 使用分离的 echo 和 read 命令，避免语法错误
  echo -e "${YELLOW}A) 修改配置 B) 立即恢复 C) 立即备份 (a/b/c)?${NC}"
  read -r CHOICE

  case "${CHOICE,,}" in
    b)
      if [ -f "$RESTORE_SH" ]; then
        bash "$RESTORE_SH"
        exit $?
      else
        echo -e "${RED}恢复脚本不存在${NC}"
      fi
      ;;
    c)
      if [ -f "$BACKUP_SH" ]; then
        bash "$BACKUP_SH"
        exit $?
      else
        echo -e "${RED}备份脚本不存在${NC}"
      fi
      ;;
    *) echo -e "${YELLOW}→ 进入配置修改流程 (回车保持原值)${NC}" ;;
  esac
fi

# ---------- 收集 / 修改配置 ----------
echo -e "${YELLOW}1) 备份文件/目录绝对路径 [${OLD_TARGET:-无}]:${NC}"
read -r TARGET_PATH
TARGET_PATH=${TARGET_PATH:-$OLD_TARGET}
[ -z "$TARGET_PATH" ] && { echo -e "${RED}必须填写${NC}"; exit 1; }
[ -e "$TARGET_PATH" ]  || { echo -e "${RED}路径不存在${NC}"; exit 1; }
TARGET_PATH=$(realpath "$TARGET_PATH")

echo -e "${YELLOW}2) R2 Access Key [${OLD_ACCESS:-无}]:${NC}"
read -r R2_ACCESS_KEY
R2_ACCESS_KEY=${R2_ACCESS_KEY:-$OLD_ACCESS}

echo -e "${YELLOW}3) R2 Secret Key (留空保持不变):${NC}"
read -r R2_SECRET_KEY
[ -z "$R2_SECRET_KEY" ] && R2_SECRET_KEY=$OLD_SECRET

echo -e "${YELLOW}4) R2 Bucket 名称 [${OLD_BUCKET:-无}]:${NC}"
read -r R2_BUCKET
R2_BUCKET=${R2_BUCKET:-$OLD_BUCKET}

echo -e "${YELLOW}5) R2 Endpoint [${OLD_ENDPOINT:-无}]:${NC}"
read -r R2_ENDPOINT
R2_ENDPOINT=${R2_ENDPOINT:-$OLD_ENDPOINT}

echo -e "${YELLOW}6) 备份间隔 30m/6h/1d/2w [${OLD_PERIOD:-1d}]:${NC}"
read -r PERIOD
PERIOD=${PERIOD:-${OLD_PERIOD:-1d}}
[[ $PERIOD =~ ^[0-9]+[smhdw]$ ]] || { echo -e "${RED}格式错误${NC}"; exit 1; }

echo -e "${YELLOW}7) 仅保留最新几份(默认10) [${OLD_KEEP:-10}]:${NC}"
read -r KEEP
KEEP=${KEEP:-${OLD_KEEP:-10}}
[[ $KEEP =~ ^[0-9]+$ ]] || { echo -e "${RED}请输入数字${NC}"; exit 1; }

# ---------- 安装 rclone（若无） ----------
if ! command -v unzip >/dev/null; then
  echo "installing unzip..."
  if command -v apt-get >/dev/null; then
    apt-get update -y && apt-get install -y unzip
  elif command -v yum >/dev/null; then
    yum install -y unzip
  elif command -v apk >/dev/null; then
    apk add unzip
  fi
fi

if ! command -v rclone >/dev/null; then
  echo -e "${YELLOW}安装 rclone ...${NC}"
  curl -fsSL https://rclone.org/install.sh | bash || {
    echo -e "${RED}安装 rclone 失败${NC}"
    exit 1
  }
fi

# ---------- 写入 / 更新 rclone.conf ----------
mkdir -p /root/.config/rclone
# 移除旧段落
if [ -f "$RCLONE_CONF" ]; then
  awk -v s="[$REMOTE_NAME]" '$0==s{f=1;next} /^\[/{f=0} !f' "$RCLONE_CONF" > /tmp/rc.tmp
  mv /tmp/rc.tmp "$RCLONE_CONF"
fi

# 添加新配置
cat >> "$RCLONE_CONF" <<EOF
[$REMOTE_NAME]
type = s3
provider = Cloudflare
access_key_id = $R2_ACCESS_KEY
secret_access_key = $R2_SECRET_KEY
endpoint = $R2_ENDPOINT
acl = private
EOF

# ---------- 检查远端是否已有备份 ----------
HAS_BAK=0
if rclone lsf "$REMOTE_NAME:$R2_BUCKET/backups/" --format p 2>/dev/null | grep -q . ; then
  HAS_BAK=1
fi

# ---------- 创建脚本目录 ----------
mkdir -p "$BASE_DIR"

# ========== 生成 backup.sh ==========
cat > "$BACKUP_SH" <<'BACKUP_EOF'
#!/usr/bin/env bash
set -e
TARGET_PATH="__TARGET_PATH__"
REMOTE="__REMOTE__"
BUCKET="__BUCKET__"
KEEP="__KEEP__"
PERIOD="__PERIOD__"

STAMP=$(date +%Y%m%d%H%M%S)
WORK=/tmp/r2-backup; mkdir -p "$WORK"
NAME=$(basename "$TARGET_PATH")
ARCHIVE="$WORK/${NAME}-${STAMP}.tar.gz"

# 写 / 覆盖 config 文件
CFG="$WORK/backup-info.txt"
cat > "$CFG" <<EOF
TARGET_PATH=$TARGET_PATH
REMOTE=$REMOTE
BUCKET=$BUCKET
PERIOD=$PERIOD
KEEP=$KEEP
EOF
rclone copy "$CFG" "$REMOTE:$BUCKET/config/" --quiet

# 打包并上传
tar -czf "$ARCHIVE" -C "$(dirname "$TARGET_PATH")" "$NAME"
rclone copy "$ARCHIVE" "$REMOTE:$BUCKET/backups/" --quiet

# 保留最新 KEEP 份
CNT=$(rclone lsf "$REMOTE:$BUCKET/backups/" --format p | wc -l)
if [ "$CNT" -gt "$KEEP" ]; then
  DEL=$((CNT-KEEP))
  rclone lsf "$REMOTE:$BUCKET/backups/" --format p | sort | head -n "$DEL" |
  while read f; do rclone delete "$REMOTE:$BUCKET/backups/$f" --quiet; done
fi
rm -f "$ARCHIVE" "$CFG"
BACKUP_EOF
chmod +x "$BACKUP_SH"
sed -i -e "s|__TARGET_PATH__|$TARGET_PATH|g" \
       -e "s|__REMOTE__|$REMOTE_NAME|g"  \
       -e "s|__BUCKET__|$R2_BUCKET|g"    \
       -e "s|__KEEP__|$KEEP|g"           \
       -e "s|__PERIOD__|$PERIOD|g"       "$BACKUP_SH"

# ========== 生成 restore.sh ==========
cat > "$RESTORE_SH" <<'RESTORE_EOF'
#!/usr/bin/env bash
set -e
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
REMOTE="__REMOTE__"
BUCKET="__BUCKET__"
TMP=/tmp/r2-restore
mkdir -p "$TMP"

# 读取 config/backup-info.txt
if rclone copy "$REMOTE:$BUCKET/config/backup-info.txt" "$TMP" --quiet 2>/dev/null; then
  source "$TMP/backup-info.txt"
  echo -e "${GREEN}已读取配置文件:${NC}"
  cat "$TMP/backup-info.txt"
else
  echo -e "${YELLOW}未找到 config/backup-info.txt${NC}"
fi

# 请求恢复目录
echo -e "${YELLOW}恢复目录:${NC} (回车使用 $TARGET_PATH)"
read -r NEW
[ -z "$NEW" ] && NEW=$TARGET_PATH
[ -z "$NEW" ] && { echo -e "${RED}必须指定目录${NC}"; exit 1; }
TARGET_PATH=$NEW

# 确保目标目录存在
mkdir -p "$TARGET_PATH"

# 获取可用备份列表
LIST=$(rclone lsf "$REMOTE:$BUCKET/backups/" --format p 2>/dev/null | sort -r)
[ -z "$LIST" ] && { echo -e "${RED}远端无可用备份${NC}"; exit 1; }

# 显示备份列表
echo -e "${GREEN}可用备份:${NC}"
echo "$LIST" | nl

# 选择备份
echo -e "${YELLOW}选择编号:${NC}"
read -r IDX
SEL=$(echo "$LIST" | sed -n "${IDX}p")
[ -z "$SEL" ] && { echo -e "${RED}编号无效${NC}"; exit 1; }

# 确认恢复
echo -e "${YELLOW}确认恢复 $SEL ? (y/N):${NC}"
read -r OK
[[ ! $OK =~ ^[Yy]$ ]] && exit 0

# 执行恢复
echo -e "${GREEN}开始恢复...${NC}"
rclone copy "$REMOTE:$BUCKET/backups/$SEL" "$TMP" --quiet

# 获取备份文件名中的原始目录名
ARCHIVE_NAME=$(basename "$SEL" .tar.gz)
ORIG_DIR=$(echo "$ARCHIVE_NAME" | cut -d'-' -f1)

# 临时解压目录
EXTRACT_DIR="$TMP/extract"
mkdir -p "$EXTRACT_DIR"

# 解压到临时目录
tar -xzf "$TMP/$SEL" -C "$EXTRACT_DIR"

# 将文件移动到目标目录
if [ -d "$EXTRACT_DIR/$ORIG_DIR" ]; then
  # 如果解压出的是目录，复制目录内容到目标目录
  echo "将 $ORIG_DIR 内容复制到 $TARGET_PATH"
  cp -rf "$EXTRACT_DIR/$ORIG_DIR/"* "$TARGET_PATH/"
else
  # 如果解压出的是文件，直接复制到目标目录
  echo "将解压的文件复制到 $TARGET_PATH"
  cp -rf "$EXTRACT_DIR/"* "$TARGET_PATH/"
fi

echo -e "${GREEN}✔ 恢复完成${NC}"
echo -e "${YELLOW}文件已恢复到: $TARGET_PATH${NC}"
ls -la "$TARGET_PATH"

# 清理临时文件
rm -rf "$EXTRACT_DIR" "$TMP/$SEL"
RESTORE_EOF
chmod +x "$RESTORE_SH"
sed -i -e "s|__REMOTE__|$REMOTE_NAME|g" \
       -e "s|__BUCKET__|$R2_BUCKET|g"   "$RESTORE_SH"

# ========== systemd unit/timer ==========
