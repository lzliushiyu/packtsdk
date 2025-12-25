#!/bin/bash
# PacketSDK 自动部署脚本（直接下载文件）
# GitHub: https://github.com/lzliushiyu/packtsdk/blob/main/packet_sdk.sh
# 远程文件地址: http://209.17.118.158/onekey/packet_sdk

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

# 1. 下载SDK函数（直接下载文件）
download_sdk() {
    log_info "未找到本地SDK，开始从远程下载..."
    
    # 检测架构
    ARCH=$(uname -m)
    log_info "检测到CPU架构: $ARCH"
    
    # 根据架构确定下载路径
    case "$ARCH" in
        x86_64) REMOTE_ARCH="x86_64" ;;
        aarch64) REMOTE_ARCH="aarch64" ;;
        i386|i686) REMOTE_ARCH="i386" ;;
        armv5l) REMOTE_ARCH="armv5l" ;;
        armv6l) REMOTE_ARCH="armv6l" ;;
        armv7l) REMOTE_ARCH="armv7l" ;;
        *)
            log_error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
    
    # 确保下载工具可用
    if ! command -v wget &> /dev/null; then
        log_error "未找到wget，请先安装: apt-get install wget"
        exit 1
    fi
    
    # 创建目标目录
    TARGET_DIR="${LOCAL_SDK_PATH}/${REMOTE_ARCH}"
    mkdir -p "$TARGET_DIR"
    
    # 直接下载 packet_sdk 文件
    REMOTE_URL="${DOWNLOAD_BASE_URL}/${REMOTE_ARCH}/packet_sdk"
    LOCAL_FILE="${TARGET_DIR}/packet_sdk"
    
    log_info "正在下载: $REMOTE_URL"
    log_info "保存到: $LOCAL_FILE"
    
    # 使用wget直接下载文件
    wget -q --show-progress -O "$LOCAL_FILE" "$REMOTE_URL"
    
    # 验证下载
    if [ ! -f "$LOCAL_FILE" ]; then
        log_error "下载失败: 文件未创建"
        exit 1
    fi
    
    # 检查文件大小（确保不是没有内容的错误文件）
    FILE_SIZE=$(stat -c%s "$LOCAL_FILE" 2>/dev/null || stat -f%z "$LOCAL_FILE" 2>/dev/null)
    if [ "$FILE_SIZE" -lt 10000 ]; then  # 假设packet_sdk至少10KB
        log_error "下载的文件太小($FILE_SIZE bytes)，可能下载失败"
        ls -lh "$LOCAL_FILE"
        exit 1
    fi
    
    log_info "✓ SDK下载完成: ${LOCAL_FILE}"
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
    
    # 检查本地SDK是否存在
    if [ ! -d "$LOCAL_SDK_PATH" ]; then
        download_sdk
    else
        # 检查是否包含当前架构的文件夹
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64) CHECK_ARCH="x86_64" ;;
            aarch64) CHECK_ARCH="aarch64" ;;
            i386|i686) CHECK_ARCH="i386" ;;
            armv5l) CHECK_ARCH="armv5l" ;;
            armv6l) CHECK_ARCH="armv6l" ;;
            armv7l) CHECK_ARCH="armv7l" ;;
        esac
        
        if [ ! -d "${LOCAL_SDK_PATH}/${CHECK_ARCH}" ] || [ ! -f "${LOCAL_SDK_PATH}/${CHECK_ARCH}/packet_sdk" ]; then
            log_warn "本地缺少当前架构(${CHECK_ARCH})的文件，将重新下载"
            rm -rf "$LOCAL_SDK_PATH"
            download_sdk
        else
            log_info "发现本地SDK: $LOCAL_SDK_PATH/${CHECK_ARCH}"
        fi
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
        i386|i686) BIN_PATH="${LOCAL_SDK_PATH}/i386/packet_sdk" ;;
        armv5l) BIN_PATH="${LOCAL_SDK_PATH}/armv5l/packet_sdk" ;;
        armv6l) BIN_PATH="${LOCAL_SDK_PATH}/armv6l/packet_sdk" ;;
        armv7l) BIN_PATH="${LOCAL_SDK_PATH}/armv7l/packet_sdk" ;;
        *) log_error "不支持的架构: $ARCH"; exit 1 ;;
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
    echo "  PacketSDK 自动部署脚本 v2.2"
    echo "  支持自动下载文件夹"
    echo "========================================="
    echo
    
    check_environment
    detect_architecture
    set_permissions
    get_user_input
    create_systemd_service
    start_service
    verify_deployment
    
    echo
    log_info "=== 部署完成！ ==="
    echo
    echo "查看日志: journalctl -u packetsdk -f"
    echo "服务状态: systemctl status packetsdk"
    echo "重启服务: systemctl restart packetsdk"
    echo "停止服务: systemctl stop packetsdk"
    echo
}

main
