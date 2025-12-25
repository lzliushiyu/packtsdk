#!/bin/bash
# PacketSDK 自动部署脚本（含下载功能）
# GitHub: https://github.com/lzliushiyu/packtsdk/blob/main/packet_sdk.sh
# 远程下载地址: http://209.17.118.158/onekey/packet_sdk

set -e

# ============= 配置区 =============
DOWNLOAD_BASE_URL="http://209.17.118.158/onekey/packet_sdk"
LOCAL_SDK_PATH="/root/packet_sdk"
# =================================

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 1. 下载SDK函数
download_sdk() {
    log_info "未找到本地SDK，开始下载..."
    
    # 检测架构
    ARCH=$(uname -m)
    log_info "检测到CPU架构: $ARCH"
    
    # 根据架构确定下载路径
    case "$ARCH" in
        x86_64) REMOTE_ARCH="x86_64" ;;
        aarch64) REMOTE_ARCH="aarch64" ;;
        i386|i686) REMOTE_ARCH="x86" ;;
        armv5l) REMOTE_ARCH="armv5l" ;;
        armv6|armv7l) REMOTE_ARCH="armv7l" ;;
        *)
            log_error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
    
    # 确保下载工具可用
    if ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
        log_error "未找到wget或curl，请先安装"
        exit 1
    fi
    
    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # 下载SDK压缩包（假设是zip格式）
    # 如果服务器提供的是文件夹而非压缩包，需要调整此逻辑
    SDK_URL="${DOWNLOAD_BASE_URL}/${REMOTE_ARCH}.tar.gz"
    
    log_info "正在下载: $SDK_URL"
    
    if command -v wget &> /dev/null; then
        wget -q --show-progress "$SDK_URL" -O "packet_sdk_${REMOTE_ARCH}.tar.gz"
    else
        curl -L --progress-bar "$SDK_URL" -o "packet_sdk_${REMOTE_ARCH}.tar.gz"
    fi
    
    # 解压到目标位置
    log_info "解压文件中..."
    mkdir -p "$LOCAL_SDK_PATH"
    
    # 解压（假设是tar.gz格式，如果是zip请改用unzip）
    tar -xzf "packet_sdk_${REMOTE_ARCH}.tar.gz" -C /root/
    
    # 清理临时文件
    cd /
    rm -rf "$TEMP_DIR"
    
    # 验证下载
    if [ ! -f "${LOCAL_SDK_PATH}/${REMOTE_ARCH}/packet_sdk" ]; then
        log_error "下载后未找到程序文件，请检查下载链接和文件结构"
        exit 1
    fi
    
    log_info "✓ SDK下载完成"
}

# 2. 环境检查
check_environment() {
    log_info "检查系统环境..."
    
    if [ "$EUID" -ne 0 ]; then 
        log_error "请使用root权限运行 (sudo bash packet_sdk.sh)"
        exit 1
    fi
    
    if ! command -v systemctl &> /dev/null; then
        log_error "systemd不可用"
        exit 1
    fi
    
    # 检查本地SDK是否存在，不存在则下载
    if [ ! -d "$LOCAL_SDK_PATH" ]; then
        download_sdk
    else
        log_info "发现本地SDK: $LOCAL_SDK_PATH"
    fi
    
    log_info "环境检查通过"
}

# 3. 架构检测
detect_architecture() {
    log_info "检测CPU架构..."
    ARCH=$(uname -m)
    
    case "$ARCH" in
        x86_64) BIN_PATH="${LOCAL_SDK_PATH}/x86_64/packet_sdk" ;;
        aarch64) BIN_PATH="${LOCAL_SDK_PATH}/aarch64/packet_sdk" ;;
        i386|i686) BIN_PATH="${LOCAL_SDK_PATH}/x86/packet_sdk" ;;
        armv5l) BIN_PATH="${LOCAL_SDK_PATH}/armv5l/packet_sdk" ;;
        armv6|armv7l) BIN_PATH="${LOCAL_SDK_PATH}/armv7l/packet_sdk" ;;
        *)
            log_error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
    
    [ ! -f "$BIN_PATH" ] && { log_error "未找到程序: $BIN_PATH"; exit 1; }
    log_info "使用程序: $BIN_PATH"
}

# 4. 设置执行权限
set_permissions() {
    log_info "设置执行权限..."
    chmod +x "$BIN_PATH"
    [ ! -x "$BIN_PATH" ] && { log_error "文件仍不可执行"; exit 1; }
    log_info "✓ 权限设置成功"
}

# 5. 获取用户输入
get_user_input() {
    log_info "配置PacketSDK..."
    
    while true; do
        read -p "请输入appkey: " APPKEY
        APPKEY=$(echo "$APPKEY" | tr -d "\r" | xargs)
        [ ${#APPKEY} -ge 10 ] && break
        log_error "appkey格式不正确"
    done
    
    # 使用固定默认值
    DNS_SERVER="8.8.8.8"
    DNS_PROTO="udp"
    log_info "DNS配置: $DNS_SERVER ($DNS_PROTO)"
}

# 6. 创建systemd服务
create_systemd_service() {
    log_info "创建systemd服务..."
    cat > /etc/systemd/system/packetsdk.service << EOF
[Unit]
Description=PacketSDK Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$(dirname "$BIN_PATH")
ExecStart=$BIN_PATH -appkey=$APPKEY -dns_server=$DNS_SERVER -dns_network_protocol=$DNS_PROTO
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
}

# 7. 启动服务
start_service() {
    log_info "启动服务..."
    systemctl daemon-reload
    systemctl enable packetsdk --now
}

# 8. 验证部署
verify_deployment() {
    log_info "验证部署..."
    sleep 3
    
    if systemctl is-active --quiet packetsdk; then
        log_info "✓ 服务运行正常"
        journalctl -u packetsdk --no-pager -n 5 | grep -q "successfully certified" && \
            log_info "✓ 认证成功，24小时后查看Dashboard" || \
            log_warn "未检测到认证信息，请检查日志"
    else
        log_error "服务启动失败"
        systemctl status packetsdk --no-pager -l
        exit 1
    fi
}

# 主流程
main() {
    echo "========================================="
    echo "  PacketSDK 自动部署脚本 v2.0"
    echo "  支持自动下载"
    echo "========================================="
    echo
    
    check_environment
    detect_architecture
    set_permissions
    get_user_input
    create_systemd_service
    start_service
    verify_deployment
}

main
