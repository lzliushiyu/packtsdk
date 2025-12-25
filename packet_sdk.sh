#!/bin/bash
# PacketSDK 自动部署脚本
# GitHub: https://github.com/yourusername/packet_sdk.sh
# 使用: bash packet_sdk.sh

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 1. 环境检查
check_environment() {
    log_info "检查系统环境..."
    
    if [ "$EUID" -ne 0 ]; then 
        log_error "请使用root权限运行 (sudo bash packet_sdk.sh)"
        exit 1
    fi
    
    if ! command -v systemctl &> /dev/null; then
        log_error "systemd不可用，此脚本仅支持systemd系统"
        exit 1
    fi
    
    if [ ! -d "/root/packet_sdk" ]; then
        log_error "未找到 /root/packet_sdk 目录"
        log_info "请先将SDK上传到/root目录并解压"
        exit 1
    fi
    
    log_info "环境检查通过"
}

# 2. 架构检测
detect_architecture() {
    log_info "检测CPU架构..."
    
    ARCH=$(uname -m)
    log_info "检测到架构: $ARCH"
    
    case "$ARCH" in
        x86_64)
            BIN_PATH="/root/packet_sdk/x86_64/packet_sdk"
            ;;
        i386|i686)
            BIN_PATH="/root/packet_sdk/x86/packet_sdk"
            ;;
        aarch64)
            BIN_PATH="/root/packet_sdk/aarch64/packet_sdk"
            ;;
        armv5l)
            BIN_PATH="/root/packet_sdk/armv5l/packet_sdk"
            ;;
        armv6|armv7l)
            BIN_PATH="/root/packet_sdk/armv7l/packet_sdk"
            ;;
        *)
            log_error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
    
    if [ ! -f "$BIN_PATH" ]; then
        log_error "未找到程序: $BIN_PATH"
        log_info "请确认SDK包已完整解压"
        exit 1
    fi
    
    log_info "使用程序: $BIN_PATH"
}

# 3. 设置执行权限
set_permissions() {
    log_info "设置执行权限..."
    
    # 修复Windows换行符
    if file "$BIN_PATH" | grep -q "with CRLF line terminators"; then
        log_warn "检测到Windows换行符，正在转换..."
        dos2unix "$BIN_PATH" 2>/dev/null || sed -i 's/\r$//' "$BIN_PATH"
    fi
    
    # 授权
    if ! chmod +x "$BIN_PATH"; then
        log_error "无法设置执行权限"
        ls -l "$BIN_PATH"
        exit 1
    fi
    
    # 验证
    if [ ! -x "$BIN_PATH" ]; then
        log_error "文件仍不可执行，请手动检查"
        ls -l "$BIN_PATH"
        exit 1
    fi
    
    log_info "✓ 权限设置成功"
}

# 4. 获取用户输入
get_user_input() {
    log_info "配置PacketSDK参数..."
    
    while true; do
        read -p "请输入appkey: " APPKEY
        APPKEY=$(echo "$APPKEY" | tr -d "\r" | xargs | tr -d "\"'")
        
        if [ ${#APPKEY} -lt 10 ]; then
            log_error "appkey格式不正确"
        else
            log_info "使用appkey: ${APPKEY:0:5}...${APPKEY: -5}"
            break
        fi
    done
    
    read -p "DNS服务器[8.8.8.8]: " DNS_SERVER
    DNS_SERVER=${DNS_SERVER:-8.8.8.8}
    
    while true; do
        read -p "DNS协议[udp/tcp]: " DNS_PROTO
        DNS_PROTO=${DNS_PROTO:-udp}
        [[ "$DNS_PROTO" =~ ^(udp|tcp)$ ]] && break
        log_error "请输入udp或tcp"
    done
}

# 5. 创建systemd服务
create_systemd_service() {
    log_info "创建systemd服务..."
    
    SERVICE_FILE="/etc/systemd/system/packetsdk.service"
    
    cat > "$SERVICE_FILE" << EOF
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
    
    log_info "服务文件已创建"
}

# 6. 启动服务
start_service() {
    log_info "启动服务..."
    systemctl daemon-reload
    systemctl enable packetsdk --now
    log_info "服务已启动"
}

# 7. 验证部署
verify_deployment() {
    log_info "验证部署..."
    sleep 3
    
    if systemctl is-active --quiet packetsdk; then
        log_info "✓ 服务运行正常"
    else
        log_error "服务启动失败"
        systemctl status packetsdk --no-pager -l
        exit 1
    fi
    
    if journalctl -u packetsdk --no-pager -n 10 | grep -q "successfully certified"; then
        log_info "✓ 认证成功，24小时后查看Dashboard"
    else
        log_warn "未检测到认证信息，请检查日志"
    fi
}

# 8. 显示管理命令
show_management_commands() {
    echo
    log_info "=== 部署完成！ ==="
    echo
    echo "查看日志: journalctl -u packetsdk -f"
    echo "服务状态: systemctl status packetsdk"
    echo "重启服务: systemctl restart packetsdk"
    echo "停止服务: systemctl stop packetsdk"
    echo
}

# 主流程
main() {
    echo "========================================="
    echo "  PacketSDK 自动部署脚本 v1.0"
    echo "========================================="
    echo
    
    check_environment
    detect_architecture
    set_permissions
    get_user_input
    create_systemd_service
    start_service
    verify_deployment
    show_management_commands
}

main
