#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

#############################################
#   专业级一键部署脚本 shadow-auto.sh
#############################################

DOWNLOAD_URL="https://raw.githubusercontent.com/NetVN/ShellBox/refs/heads/main/ss_package.zip"
TMP_ZIP="/tmp/ss_package.zip"
TARGET_DIR="/root/ss"
DNS_SCRIPT="/root/ss/dns.py"
OUTLINE_SCRIPT="/root/ss/install_server.sh"
API_CONF="/root/ss/api.conf"
LOG_FILE="/var/log/ss.log"

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
BLUE="\033[36m"
RESET="\033[0m"

log() { echo -e "${BLUE}[*]${RESET} $1"; echo "[*] $1" >> "$LOG_FILE"; }
success() { echo -e "${GREEN}[✓]${RESET} $1"; echo "[✓] $1" >> "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[!]${RESET} $1"; echo "[!] $1" >> "$LOG_FILE"; }
error() { echo -e "${RED}[X]${RESET} $1"; echo "[X] $1" >> "$LOG_FILE"; exit 1; }

# 必须 root
[ "$EUID" -ne 0 ] && error "请使用 root 权限运行本脚本"

# 参数检查
if [ -z "$1" ] || [ -z "$2" ]; then
    error "用法：./shadow-auto.sh <zip密码> <编号>"
fi

ZIP_PASS="$1"
SERVER_ID="$2"

HOST4="sql${SERVER_ID}.4.netdq.cc"
HOST6="sql${SERVER_ID}.6.netdq.cc"
KEYS_PORT="${SERVER_ID}443"

log "HOST4 = $HOST4"
log "HOST6 = $HOST6"
log "KEYS_PORT = $KEYS_PORT"

# 系统类型
log "检测系统类型..."
OS="unknown"
[ -f /etc/os-release ] && . /etc/os-release && OS=$ID
success "系统类型：$OS"

# CPU 架构
ARCH=$(uname -m)
success "CPU 架构：$ARCH"

# 安装依赖
install_pkg() {
    PKG=$1
    if ! command -v $PKG >/dev/null 2>&1; then
        log "安装 $PKG ..."
        case "$OS" in
            ubuntu|debian) apt update -y && apt install -y $PKG ;;
            centos|rhel|rocky) yum install -y $PKG ;;
            fedora) dnf install -y $PKG ;;
            *) error "无法识别系统，请手动安装 $PKG" ;;
        esac
    fi
}

install_pkg wget
install_pkg unzip
install_pkg zip
install_pkg curl
install_pkg jq
install_pkg python3

# 清理旧 zip
[ -f "$TMP_ZIP" ] && rm -f "$TMP_ZIP"

# 下载 zip
log "下载压缩包..."
wget -O "$TMP_ZIP" "$DOWNLOAD_URL" || error "下载失败"
success "下载完成"

# 解压
mkdir -p "$TARGET_DIR"
log "解压缩到 $TARGET_DIR ..."
unzip -o -P "$ZIP_PASS" "$TMP_ZIP" -d "$TARGET_DIR" || error "解压失败"
success "解压完成"

# 执行 dns.py
log "执行 dns.py $SERVER_ID ..."
python3 "$DNS_SCRIPT" "$SERVER_ID"

NEW_HOSTNAME="jump-ss-$SERVER_ID"
log "修改 hostname 为：$NEW_HOSTNAME"
hostnamectl set-hostname "$NEW_HOSTNAME"

# 下载 Outline 安装脚本
log "下载 Outline install_server.sh ..."
wget -qO "$OUTLINE_SCRIPT" \
  https://raw.githubusercontent.com/Jigsaw-Code/outline-apps/master/server_manager/install_scripts/install_server.sh \
  || error "下载 install_server.sh 失败"
chmod +x "$OUTLINE_SCRIPT"
success "Outline 安装脚本已下载"

# 清理旧容器
log "清理旧的 Outline 容器..."
docker rm -f watchtower >/dev/null 2>&1 || true
docker rm -f shadowbox >/dev/null 2>&1 || true
success "旧容器清理完成"

# 执行 Outline 安装
log "开始安装 Outline Server..."

RAW_OUT=$("$OUTLINE_SCRIPT" \
    --hostname "$HOST4" \
    --api-port 54320 \
    --keys-port "$KEYS_PORT")

log "install_server.sh 原始输出：$RAW_OUT"

# 解析输出（JSON 或 YAML）
if echo "$RAW_OUT" | jq . >/dev/null 2>&1; then
    OUT_JSON="$RAW_OUT"
else
    CERT=$(echo "$RAW_OUT" | grep certSha256 | cut -d':' -f2)
    API=$(echo "$RAW_OUT" | grep apiUrl | cut -d':' -f2-)

    [ -z "$CERT" ] && error "无法解析 certSha256"
    [ -z "$API" ] && error "无法解析 apiUrl"

    OUT_JSON=$(jq -n --arg a "$API" --arg c "$CERT" \
        '{apiUrl:$a, certSha256:$c}')
fi

success "Outline 安装成功"
log "解析后的 JSON：$OUT_JSON"

# 写入 IPv4 JSON
echo "$OUT_JSON" > "$API_CONF"

# 生成 IPv6 JSON
NEW_JSON=$(echo "$OUT_JSON" | jq --arg h "$HOST6" \
    '.apiUrl |= sub("https://[^/]*"; "https://\($h)")')

echo "$NEW_JSON" >> "$API_CONF"

success "api.conf 已生成：$API_CONF"

# 部署 SSH 密钥
if [ -f "$TARGET_DIR/authorized_keys" ]; then
    log "部署 authorized_keys ..."
    mkdir -p /root/.ssh
    cp -f "$TARGET_DIR/authorized_keys" /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys
    success "authorized_keys 已部署"
fi

success "脚本执行完成"
