## PacketSDK 自动部署脚本

### 快速开始该脚本适用于linux系统

v2:
**添加根据cpu类型下载对应的安装程序**
感谢使用我的注册链接https://packetsdk.com/?r=LyxxNmdV
创建app（名称随便写），系统选择linux，appkey使用自己的就可以
#### 一键部署（推荐）
wget https://raw.githubusercontent.com/lzliushiyu/packtsdk/main/packet_sdk.sh && chmod +x packet_sdk.sh && sudo ./packet_sdk.sh

v1：
**要求**：Linux系统（支持systemd）、root权限、已上传PacketSDK到/root目录，文件夹名称为packet_sdk不能改

#### 一键部署（推荐）
```bash
bash &lt;(curl -s https://raw.githubusercontent.com/lzliushiyu/packtsdk/main/packet_sdk.sh)
