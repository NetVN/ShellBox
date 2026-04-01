#!/bin/bash

#############################################
#   专业级一键部署脚本 ss.sh
#   功能：下载 → 解压 → 执行 dns.py → 改 hostname → 安装
#############################################

# ================================
# 配置区域（请按需修改）
# ================================
DOWNLOAD_URL="https://raw.githubusercontent.com/NetVN/ShellBox/refs/heads/main/ss_package.zip"
TMP_ZIP="/tmp/ss_package.zip"
TARGET_DIR="/root/ss"
DNS_SCRIPT="/root/ss/dns.py"
OUTLINE_SCRIPT="/root/ss/install_server.sh"
API_CONF="/root/ss/api.conf"
LOG_FILE="/var/log/ss.log"
# ================================


# ================================
# 彩色输出
# ================================
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
BLUE="\033[36m"
RESET="\033[0m"

log() {
    echo -e "${BLUE}[*]${RESET} $1"
    echo "[*] $1" >> "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[✓]${RESET} $1"
    echo "[✓] $1" >> "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[!]${RESET} $1"
    echo "[!] $1" >> "$LOG_FILE"
}

error() {
    echo -e "${RED}[X]${RESET} $1"
    echo "[X] $1" >> "$LOG_FILE"
    exit 1
}


# ================================
# 必须是 root
# ================================
if [ "$EUID" -ne 0 ]; then
    error "请使用 root 权限运行本脚本"
fi


# ================================
# 检测系统类型
# ================================
log "检测系统类型..."

OS="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
fi

success "系统类型：$OS"


# ================================
# 检测 CPU 架构
# ================================
ARCH=$(uname -m)
success "CPU 架构：$ARCH"


# ================================
# 自动安装依赖
# ================================
install_pkg() {
    PKG=$1
    if ! command -v $PKG >/dev/null 2>&1; then
        log "安装 $PKG ..."
        case "$OS" in
            ubuntu|debian)
                apt update -y && apt install -y $PKG
                ;;
            centos|rhel|rocky)
                yum install -y $PKG
                ;;
            fedora)
                dnf install -y $PKG
                ;;
            *)
                error "无法识别系统，请手动安装 $PKG"
                ;;
        esac
    fi
}

install_pkg wget
install_pkg unzip
install_pkg zip
install_pkg curl
install_pkg jq


# ================================
# 检测 unzip 是否支持密码
# ================================
if ! unzip -hh 2>&1 | grep -q "\-P"; then
    warn "当前 unzip 不支持密码，正在安装完整版 unzip"
    install_pkg unzip
fi


# ================================
# 检测 Python3 + pip
# ================================
log "检测 Python3..."

if ! command -v python3 >/dev/null 2>&1; then
    log "安装 Python3..."
    case "$OS" in
        ubuntu|debian)
            apt install -y python3 python3-pip
            ;;
        centos|rhel|rocky)
            yum install -y python3 python3-pip
            ;;
        fedora)
            dnf install -y python3 python3-pip
            ;;
        *)
            error "无法识别系统，请手动安装 Python3"
            ;;
    esac
else
    success "Python3 已安装"
fi


# ================================
# 清理旧文件
# ================================
if [ -f "$TMP_ZIP" ]; then
    log "清理旧的压缩包..."
    rm -f "$TMP_ZIP"
fi


# ================================
# 下载压缩包（自动重试 3 次）
# ================================
log "下载压缩包..."

RETRY=3
for i in $(seq 1 $RETRY); do
    wget -O "$TMP_ZIP" "$DOWNLOAD_URL" && break
    warn "下载失败，重试第 $i 次..."
    sleep 2
done

if [ ! -f "$TMP_ZIP" ]; then
    error "下载失败，已尝试 $RETRY 次"
fi

success "下载完成"


# ================================
# 创建解压目录
# ================================
mkdir -p "$TARGET_DIR"


# ================================
# 解压缩
# ================================
log "解压缩到 $TARGET_DIR ..."

unzip -o -P "$1" "$TMP_ZIP" -d "$TARGET_DIR" || error "解压失败，可能是密码错误"

success "解压完成"


# ================================
# 执行 dns.py（如果有第二参数）
# ================================
if [ -n "$2" ]; then
    log "执行 dns.py $2 ..."

    if [ ! -f "$DNS_SCRIPT" ]; then
        error "找不到 $DNS_SCRIPT"
    fi

    python3 "$DNS_SCRIPT" "$2"

    NEW_HOSTNAME="jump-ss-$2"
    log "修改 hostname 为：$NEW_HOSTNAME"
    hostnamectl set-hostname "$NEW_HOSTNAME"
fi


# ================================
# 下载 Outline 安装脚本
# ================================
log "下载 Outline install_server.sh ..."

wget -qO "$OUTLINE_SCRIPT" \
  https://raw.githubusercontent.com/Jigsaw-Code/outline-apps/master/server_manager/install_scripts/install_server.sh \
  || error "下载 install_server.sh 失败"

chmod +x "$OUTLINE_SCRIPT"
success "Outline 安装脚本已下载"


# ================================
# 执行 Outline 安装脚本
# ================================
if [ -n "$2" ]; then
    HOST4="sql$2.4.netdq.cc"
    KEYS_PORT="${2}443"   # ← 关键修改：keys-port = 第二变量 + 443

    log "开始安装 Outline Server..."

    OUT_JSON=$(bash "$OUTLINE_SCRIPT" \
        --hostname "$HOST4" \
        --api-port 54320 \
        --keys-port "$KEYS_PORT")

    echo "$OUT_JSON" | jq . >/dev/null 2>&1 || error "Outline 安装失败，未返回 JSON"

    success "Outline 安装成功"
    log "返回 JSON：$OUT_JSON"


    # 写入第一行原始 JSON
    echo "$OUT_JSON" > "$API_CONF"

    # 替换 apiUrl 为 IPv6 域名
    HOST6="sql$2.6.netdq.cc"
    NEW_JSON=$(echo "$OUT_JSON" | jq --arg h "$HOST6" '.apiUrl |= sub("https://[^:]*"; "https://\($h)")')

    echo "$NEW_JSON" >> "$API_CONF"

    success "api.conf 已生成：$API_CONF"
fi

# ================================
# 部署 authorized_keys
# ================================
if [ -f "$TARGET_DIR/authorized_keys" ]; then
    log "检测到 authorized_keys，开始部署..."

    mkdir -p /root/.ssh
    cp -f "$TARGET_DIR/authorized_keys" /root/.ssh/authorized_keys

    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys

    success "authorized_keys 已部署到 /root/.ssh/"
else
    warn "未找到 $TARGET_DIR/authorized_keys，跳过 SSH 密钥部署"
fi

success "脚本执行完成"
