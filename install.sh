#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "错误：请以 root 权限运行此脚本（使用 sudo）"
    exit 1
fi

# 检查网络连接
echo "检查网络连接..."
if ! ping -c 3 8.8.8.8 > /dev/null 2>&1; then
    echo "错误：无法连接到网络，请检查网络状态后重试"
    exit 1
fi

# 更新系统并安装必要的工具
echo "更新系统并安装必要工具..."
if ! apt update; then
    echo "错误：apt update 失败，请检查网络或软件源配置"
    exit 1
fi
if ! apt upgrade -y; then
    echo "警告：apt upgrade 失败，继续执行后续步骤..."
fi
if ! apt install -y wget tar iptables; then
    echo "错误：安装 wget、tar 或 iptables 失败"
    exit 1
fi

# 检测系统架构
echo "检测系统架构..."
ARCH=$(uname -m)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$ARCH" in
    x86_64) ARCH="amd64";;
    aarch64) ARCH="arm64";;
    armv7l) ARCH="armv7";;
    i386|i686) ARCH="386";;
    *) echo "错误：不支持的系统架构：$ARCH"; exit 1;;
esac
echo "检测到系统架构：$OS-$ARCH"

# 设置 sing-box 版本和下载地址
SINGBOX_VERSION="1.11.4"
SINGBOX_BASE_URL="https://gh.sageer.me/github.com/SagerNet/sing-box/releases/download"
SINGBOX_URL="${SINGBOX_BASE_URL}/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-${OS}-${ARCH}.tar.gz"
echo "sing-box 下载地址：$SINGBOX_URL"

# 下载并安装 sing-box
echo "下载并安装 sing-box..."
if ! wget -O sing-box.tar.gz "$SINGBOX_URL"; then
    echo "错误：下载 sing-box 失败，请检查网络或 URL 是否有效"
    exit 1
fi
if ! tar -xzf sing-box.tar.gz; then
    echo "错误：解压 sing-box.tar.gz 失败，文件可能损坏"
    exit 1
fi
if [ ! -f sing-box-${SINGBOX_VERSION}-${OS}-${ARCH}/sing-box ]; then
    echo "错误：解压后未找到 sing-box 可执行文件"
    exit 1
fi
mv sing-box-${SINGBOX_VERSION}-${OS}-${ARCH}/sing-box /usr/local/bin/
chmod +x /usr/local/bin/sing-box
rm -rf sing-box.tar.gz sing-box-${SINGBOX_VERSION}-${OS}-${ARCH}

# 检查 sing-box 是否安装成功
if ! command -v sing-box > /dev/null 2>&1; then
    echo "错误：sing-box 安装失败，无法找到可执行文件"
    exit 1
fi

# 获取配置文件 URL
DEFAULT_CONFIG_URL="https://sub.hechunyu.com/config-zz-realip-route"
echo "请输入 sing-box 配置文件 URL（直接回车使用默认值）:"
echo "默认 URL: $DEFAULT_CONFIG_URL"
read -r CONFIG_URL
if [ -z "$CONFIG_URL" ]; then
    CONFIG_URL="$DEFAULT_CONFIG_URL"
    echo "未输入 URL，将使用默认配置文件地址：$CONFIG_URL"
fi

# 下载 sing-box 配置文件
echo "下载 sing-box 配置文件..."
mkdir -p /etc/sing-box
if ! wget -O /etc/sing-box/config.json "$CONFIG_URL"; then
    echo "错误：下载配置文件失败，请检查网络或 URL 是否有效"
    exit 1
fi

# 创建 sing-box systemd 服务文件
echo "配置 sing-box 为系统服务..."
cat << EOF > /etc/systemd/system/sing-box.service
[Unit]
Description=Sing-box Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

# 检查 systemd 是否可用并启用服务
if ! systemctl daemon-reload || ! systemctl enable sing-box || ! systemctl start sing-box; then
    echo "错误：配置或启动 sing-box 服务失败，请检查配置文件"
    exit 1
fi

# 停止并禁用 systemd-resolved 服务
echo "停止并禁用 systemd-resolved 服务..."
if systemctl is-active systemd-resolved > /dev/null 2>&1; then
    systemctl stop systemd-resolved
    systemctl disable systemd-resolved
else
    echo "警告：systemd-resolved 服务未运行，跳过此步骤"
fi

# 检查并配置 /etc/resolv.conf
echo "检查并配置 /etc/resolv.conf..."
if [ -L /etc/resolv.conf ]; then
    echo "/etc/resolv.conf 是一个软连接，正在删除并重建..."
    rm -f /etc/resolv.conf
elif [ -f /etc/resolv.conf ]; then
    echo "/etc/resolv.conf 不是软连接，直接覆盖内容..."
else
    echo "/etc/resolv.conf 不存在，正在创建..."
fi
echo "nameserver 127.0.0.1" > /etc/resolv.conf
chattr +i /etc/resolv.conf || echo "警告：无法锁定 /etc/resolv.conf"

# 启用 IP 转发
echo "启用 IP 转发..."
if ! sysctl -w net.ipv4.ip_forward=1 || ! sysctl -w net.ipv6.conf.all.forwarding=1; then
    echo "错误：启用 IP 转发失败"
    exit 1
fi
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf

# 配置 iptables 规则
echo "配置 iptables 规则..."
if ! iptables -F || ! iptables -t nat -F; then
    echo "错误：清理 iptables 规则失败"
    exit 1
fi
iptables -A INPUT -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -i end0 -j ACCEPT
iptables -t nat -A POSTROUTING -o end0 -j MASQUERADE

# 保存 iptables 规则
echo "保存 iptables 规则..."
mkdir -p /etc/iptables
[ -f /etc/iptables/rules.v4 ] && mv /etc/iptables/rules.v4 /etc/iptables/rules.v4.bak-$(date +%F-%T)
if ! iptables-save > /etc/iptables/rules.v4; then
    echo "错误：保存 iptables 规则失败"
    exit 1
fi

# 配置 iptables 持久化
echo "安装 iptables-persistent 并保存规则..."
echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
if ! apt install -y iptables-persistent; then
    echo "错误：安装 iptables-persistent 失败"
    exit 1
fi

# 重启网络服务
echo "重启网络服务..."
systemctl restart networking || echo "警告：重启网络服务失败，可能需要手动重启"

# 检查服务状态
echo "检查服务状态..."
if systemctl status sing-box > /dev/null 2>&1; then
    echo "sing-box 服务运行正常"
else
    echo "错误：sing-box 服务未正常运行"
fi
iptables -L -v -n
iptables -t nat -L -v -n

echo "部署完成！请将其他设备的网关和 DNS 指向此设备的 IP（192.168.1.3）。"
