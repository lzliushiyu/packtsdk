# 一键部署脚本（复制整段代码到SSH终端执行）
bash -c '
#!/bin/bash
set -e

echo "=== PacketSDK systemd一键部署 ==="

# 检测架构
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) BIN_PATH="/root/packet_sdk/x86_64/packet_sdk" ;;
    aarch64) BIN_PATH="/root/packet_sdk/aarch64/packet_sdk" ;;
    *) echo "不支持架构: $ARCH"; exit 1 ;;
esac

if [ ! -f "$BIN_PATH" ]; then
    echo "错误: 未找到 $BIN_PATH"
    echo "请确认SDK已解压到/root目录"
    exit 1
fi

# 输入appkey
while true; do
    read -p "请输入appkey: " APPKEY
    APPKEY=$(echo "$APPKEY" | tr -d "\r" | xargs)
    [ ${#APPKEY} -ge 10 ] && break
    echo "appkey无效，请重新输入"
done

# 创建服务
cat > /etc/systemd/system/packetsdk.service << EOF
[Unit]
Description=PacketSDK Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$(dirname $BIN_PATH)
ExecStart=$BIN_PATH -appkey=$APPKEY -dns_server=8.8.8.8 -dns_network_protocol=udp
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable --now packetsdk

echo "=== 部署成功！ ==="
echo "查看状态: systemctl status packetsdk"
echo "查看日志: journalctl -u packetsdk -f"
'
