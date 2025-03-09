#!/bin/sh

# 日志级别设置 (DEBUG/INFO)，全局变量
LOG_LEVEL="INFO"  # 默认设置为 INFO

# 日志函数，使用 printf 替代 echo -e
log() {
    level="$1"
    msg="$2"
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    NC='\033[0m' # No Color
    
    case "$level" in
        "DEBUG")
            if [ "$LOG_LEVEL" = "DEBUG" ]; then
                printf "[%s] %bDEBUG%b: %s\n" "$timestamp" "$YELLOW" "$NC" "$msg"
            fi
            ;;
        "INFO")
            printf "[%s] %bINFO%b:  %s\n" "$timestamp" "$GREEN" "$NC" "$msg"
            ;;
        "ERROR")
            printf "[%s] %bERROR%b: %s\n" "$timestamp" "$RED" "$NC" "$msg" >&2
            ;;
        "WARN")
            printf "[%s] %bWARN%b:  %s\n" "$timestamp" "$YELLOW" "$NC" "$msg" >&2
            ;;
    esac
}

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    log "ERROR" "请以 root 权限运行此脚本（使用 sudo）"
    exit 1
fi

# 检查系统版本和型号
check_system() {
    log "INFO" "正在检测系统信息..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        SYSTEM_NAME="${PRETTY_NAME:-未知系统}"
        SYSTEM_ID="${ID:-unknown}"
        SYSTEM_VERSION="${VERSION_ID:-unknown}"
        log "INFO" "系统: $SYSTEM_NAME ($SYSTEM_ID $SYSTEM_VERSION)"
    else
        log "WARN" "无法读取 /etc/os-release，系统信息未知"
        SYSTEM_NAME="未知系统"
        SYSTEM_ID="unknown"
        SYSTEM_VERSION="unknown"
    fi
    ARCH=$(uname -m)
    log "INFO" "架构: $ARCH"
    if [ -f /proc/cpuinfo ]; then
        HARDWARE_MODEL=$(grep -i "^Model" /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//')
        [ -z "$HARDWARE_MODEL" ] && HARDWARE_MODEL=$(grep -i "^Hardware" /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//')
        [ -z "$HARDWARE_MODEL" ] && HARDWARE_MODEL="未知型号"
    else
        HARDWARE_MODEL="未知型号"
    fi
    log "INFO" "硬件型号: $HARDWARE_MODEL"
    case "$SYSTEM_ID" in
        "ubuntu"|"debian")
            if echo "$SYSTEM_VERSION" | grep -q "24.04"; then
                log "INFO" "检测到 Ubuntu 24.04 或类似系统，使用 nftables"
                USE_NFTABLES="yes"
            else
                log "INFO" "检测到 Debian/Ubuntu 系统，使用 iptables"
                USE_NFTABLES="no"
            fi
            ;;
        *)
            log "WARN" "未知系统类型 ($SYSTEM_ID)，默认使用 iptables"
            USE_NFTABLES="no"
            ;;
    esac
    if echo "$HARDWARE_MODEL" | grep -qi "NanoPi R2S"; then
        log "INFO" "检测到 NanoPi R2S，优化网络接口检测"
        EXPECTED_INTERFACE="end0"
    else
        EXPECTED_INTERFACE=""
    fi
}

# 获取默认网络接口和IP地址
get_network_info() {
    log "INFO" "正在检测网络信息..."
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [ -z "$INTERFACE" ]; then
        log "ERROR" "无法检测到默认网络接口"
        exit 1
    fi
    if [ -n "$EXPECTED_INTERFACE" ] && [ "$INTERFACE" != "$EXPECTED_INTERFACE" ]; then
        log "WARN" "检测到的接口 ($INTERFACE) 与预期 ($EXPECTED_INTERFACE) 不符，使用检测到的接口"
    fi
    IP_ADDR=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
    if [ -z "$IP_ADDR" ]; then
        log "ERROR" "无法获取 IP 地址"
        exit 1
    fi
    NETMASK=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | head -n1 | cut -d'/' -f2)
    if [ -z "$NETMASK" ]; then
        log "WARN" "无法检测子网掩码，默认使用 24 (255.255.255.0)"
        NETMASK="24"
    fi
    GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n1)
    if [ -z "$GATEWAY" ]; then
        log "ERROR" "无法检测到网关地址"
        exit 1
    fi
    log "INFO" "网络信息: 接口 $INTERFACE, IP $IP_ADDR/$NETMASK, 网关 $GATEWAY"
}

# 检查网络连接
check_network() {
    log "INFO" "检查网络连接..."
    if ! ping -c 3 8.8.8.8 > /dev/null 2>&1; then
        log "ERROR" "无法连接到网络，请检查网络状态"
        exit 1
    fi
    log "INFO" "网络连接正常"
}

# 更新系统和安装工具
update_and_install() {
    log "INFO" "快速安装（跳过更新）？[Y/N，默认N]: "
    read FAST_INSTALL
    case "$FAST_INSTALL" in
        [Yy]*)
            log "INFO" "选择快速安装，跳过系统更新"
            ;;
        *)
            log "INFO" "选择完整安装，执行系统更新"
            FAST_INSTALL="N"
            ;;
    esac

    log "INFO" "正在更新软件源..."
    if ! apt update > /dev/null 2>&1; then
        log "WARN" "软件源更新失败，尝试修复..."
        apt update --fix-missing > /dev/null 2>&1 || { log "ERROR" "软件源更新失败，请检查网络或 /etc/apt/sources.list"; exit 1; }
    else
        log "INFO" "软件源更新完成"
    fi
    
    if [ "$FAST_INSTALL" != "Y" ] && [ "$FAST_INSTALL" != "y" ]; then
        log "INFO" "正在更新系统（可能耗时较长）..."
        apt upgrade -y > /dev/null 2>&1 || log "WARN" "系统更新失败，继续执行"
    fi
    
    log "INFO" "安装必要工具..."
    apt install -y wget tar > /dev/null 2>&1 || { log "ERROR" "安装基本工具失败，请检查软件源"; exit 1; }
    
    if [ "$USE_NFTABLES" = "yes" ]; then
        log "INFO" "安装 nftables..."
        apt install -y nftables > /dev/null 2>&1 || { log "ERROR" "安装 nftables 失败"; exit 1; }
    else
        log "INFO" "安装 iptables..."
        apt install -y iptables > /dev/null 2>&1 || { log "ERROR" "安装 iptables 失败"; exit 1; }
        update-alternatives --set iptables /usr/sbin/iptables-legacy > /dev/null 2>&1
    fi

    apt install -y ip6tables > /dev/null 2>&1 || log "WARN" "无法安装 ip6tables，IPv6 支持可能受限"
    
    if ! command -v ipcalc > /dev/null 2>&1; then
        log "INFO" "安装 ipcalc..."
        apt install -y ipcalc > /dev/null 2>&1 || log "WARN" "安装 ipcalc 失败，使用默认子网掩码"
    fi

    if ! command -v netplan > /dev/null 2>&1; then
        log "INFO" "安装 netplan..."
        apt install -y netplan.io > /dev/null 2>&1 || { log "ERROR" "安装 netplan.io 失败"; exit 1; }
    fi
}

# 安装 sing-box
install_singbox() {
    ARCH=$(uname -m)
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    case "$ARCH" in
        x86_64) ARCH="amd64";;
        aarch64) ARCH="arm64";;
        armv7l) ARCH="armv7";;
        i386|i686) ARCH="386";;
        *) log "ERROR" "不支持的架构: $ARCH"; exit 1;;
    esac
    log "INFO" "系统架构: $OS-$ARCH"

    SINGBOX_VERSION="1.11.4"
    DEFAULT_SINGBOX_URL="https://gh.aaa.team/github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-${OS}-${ARCH}.tar.gz"
    
    log "INFO" "使用自定义 sing-box 下载地址？[Y/N，默认N]: "
    read USE_CUSTOM_URL
    case "$USE_CUSTOM_URL" in
        [Yy]*)
            log "INFO" "请输入自定义下载地址（需为 .tar.gz 格式）: "
            read SINGBOX_URL
            [ -z "$SINGBOX_URL" ] && { log "ERROR" "下载地址不能为空"; exit 1; }
            log "INFO" "使用自定义地址: $SINGBOX_URL"
            ;;
        *)
            SINGBOX_URL="$DEFAULT_SINGBOX_URL"
            log "INFO" "使用默认地址: $SINGBOX_URL"
            ;;
    esac

    log "INFO" "下载 sing-box..."
    wget -q -O sing-box.tar.gz "$SINGBOX_URL" || { log "ERROR" "下载 sing-box 失败"; exit 1; }
    log "INFO" "解压 sing-box..."
    tar -xzf sing-box.tar.gz || { log "ERROR" "解压 sing-box 失败"; exit 1; }
    [ -f "sing-box-${SINGBOX_VERSION}-${OS}-${ARCH}/sing-box" ] || { log "ERROR" "未找到 sing-box 可执行文件"; exit 1; }
    mv "sing-box-${SINGBOX_VERSION}-${OS}-${ARCH}/sing-box" /usr/local/bin/
    chmod +x /usr/local/bin/sing-box
    rm -rf sing-box.tar.gz "sing-box-${SINGBOX_VERSION}-${OS}-${ARCH}"
    
    command -v sing-box > /dev/null 2>&1 || { log "ERROR" "sing-box 安装失败"; exit 1; }
    log "INFO" "sing-box 安装完成"
}

# 配置自动更新脚本
setup_update_script() {
    log "INFO" "配置自动更新脚本..."
    UP_CONFIG_URL="https://gh.aaa.team/https://raw.githubusercontent.com/Lsmoisu/sing-box-shell/refs/heads/main/upconfig.sh"
    log "INFO" "下载更新脚本..."
    wget -q -O /usr/local/bin/upconfig.sh "$UP_CONFIG_URL" || { log "ERROR" "下载更新脚本失败"; exit 1; }
    chmod +x /usr/local/bin/upconfig.sh
    [ -x /usr/local/bin/upconfig.sh ] || { log "ERROR" "更新脚本权限设置失败"; exit 1; }
    
    (crontab -l 2>/dev/null | grep -v "upconfig.sh"; echo "* * * * * bash /usr/local/bin/upconfig.sh > /dev/null 2>&1") | crontab - || log "WARN" "配置 crontab 失败"
    log "INFO" "自动更新脚本配置完成"
}

# 下载配置文件
download_config() {
    DEFAULT_CONFIG_URL="https://sub.aaa.team/config-66ca38b4bd8d"
    log "INFO" "请输入配置文件 URL（回车使用默认: $DEFAULT_CONFIG_URL）: "
    read CONFIG_URL
    [ -z "$CONFIG_URL" ] && CONFIG_URL="$DEFAULT_CONFIG_URL" && log "INFO" "使用默认配置文件: $CONFIG_URL"
    
    mkdir -p /etc/sing-box
    log "INFO" "下载配置文件..."
    wget -q -O /etc/sing-box/config.json "$CONFIG_URL" || { log "ERROR" "下载配置文件失败"; exit 1; }
    log "INFO" "配置文件下载完成"
}

# 释放 53 端口
release_port_53() {
    log "INFO" "检查并释放 53 端口..."

    # 检查 53 端口是否被占用（TCP 和 UDP）
    PORT_53_TCP=$(ss -tuln | grep -E ":53\s+.*(0.0.0.0|\[::\]|127.0.0.53|127.0.0.54)" | awk '{print $1 " " $5}' | sed 's/  */ /g')
    PORT_53_UDP=$(ss -uuln | grep -E ":53\s+.*(0.0.0.0|\[::\]|127.0.0.53|127.0.0.54)" | awk '{print $1 " " $5}' | sed 's/  */ /g')
    if [ -z "$PORT_53_TCP" ] && [ -z "$PORT_53_UDP" ]; then
        log "INFO" "53 端口（TCP 和 UDP）未被占用，无需释放"
        return 0
    fi

    # 显示占用详情（优化格式）
    if [ -n "$PORT_53_TCP" ]; then
        TCP_INFO=$(echo "$PORT_53_TCP" | tr '\n' '; ' | sed 's/; $//')
        log "WARN" "53 端口 TCP 被占用: $TCP_INFO"
    fi
    if [ -n "$PORT_53_UDP" ]; then
        UDP_INFO=$(echo "$PORT_53_UDP" | tr '\n' '; ' | sed 's/; $//')
        log "WARN" "53 端口 UDP 被占用: $UDP_INFO"
    fi

    # 直接停止 systemd-resolved
    log "INFO" "尝试停止 systemd-resolved 服务以释放 53 端口..."
    systemctl stop systemd-resolved > /dev/null 2>&1 || log "WARN" "无法停止 systemd-resolved，可能未运行"
    systemctl disable systemd-resolved > /dev/null 2>&1 || log "WARN" "无法禁用 systemd-resolved，可能已禁用"

    # 等待 1 秒后再次检查 53 端口
    sleep 1
    PORT_53_TCP=$(ss -tuln | grep -E ":53\s+.*(0.0.0.0|\[::\]|127.0.0.53|127.0.0.54)" | awk '{print $1 " " $5}' | sed 's/  */ /g')
    PORT_53_UDP=$(ss -uuln | grep -E ":53\s+.*(0.0.0.0|\[::\]|127.0.0.53|127.0.0.54)" | awk '{print $1 " " $5}' | sed 's/  */ /g')
    if [ -n "$PORT_53_TCP" ] || [ -n "$PORT_53_UDP" ]; then
        TCP_INFO=$(echo "$PORT_53_TCP" | tr '\n' '; ' | sed 's/; $//')
        UDP_INFO=$(echo "$PORT_53_UDP" | tr '\n' '; ' | sed 's/; $//')
        log "ERROR" "53 端口仍未完全释放，TCP: ${TCP_INFO:-无}, UDP: ${UDP_INFO:-无}"
        log "INFO" "请手动检查占用 53 端口的进程并释放（使用 'ss -tulnp | grep :53' 查看）"
        exit 1
    fi

    log "INFO" "53 端口释放成功"
}




# 配置服务
setup_service() {
    log "INFO" "配置 sing-box 服务..."
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

    systemctl daemon-reload || { log "ERROR" "systemd 重新加载失败"; exit 1; }
    systemctl enable sing-box > /dev/null 2>&1 || { log "ERROR" "启用 sing-box 服务失败"; exit 1; }

    # 尝试启动服务，最多重试 2 次
    MAX_RETRIES=2
    for i in $(seq 0 $MAX_RETRIES); do
        systemctl start sing-box || log "WARN" "sing-box 服务启动失败，第 $i 次尝试"
        sleep 2
        if systemctl is-active sing-box > /dev/null 2>&1; then
            log "INFO" "sing-box 服务启动成功"
            return 0
        fi
        log "DEBUG" "等待服务启动... (尝试 $i/$MAX_RETRIES)"
    done

    log "ERROR" "sing-box 服务启动失败，请检查日志: journalctl -u sing-box"
    exit 1
}

# 配置网络
configure_network() {
    log "INFO" "配置网络设置..."
    log "INFO" "设置接口 $INTERFACE 为静态 IP..."
    
    if [ -d /etc/netplan ]; then
        cat << EOF > /etc/netplan/01-netcfg.yaml
network:
  version: 2
  ethernets:
    $INTERFACE:
      dhcp4: no
      addresses:
        - $IP_ADDR/$NETMASK
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses: [127.0.0.1, 8.8.8.8]
EOF
        chmod 600 /etc/netplan/01-netcfg.yaml
        netplan apply || { log "ERROR" "应用 netplan 配置失败"; exit 1; }
        log "INFO" "已设置静态 IP: $IP_ADDR"
        sleep 5
    else
        NETMASK_DOT=$(ipcalc -m "$IP_ADDR/$NETMASK" | cut -d= -f2 2>/dev/null || echo "255.255.255.0")
        cat << EOF > /etc/network/interfaces
auto lo
iface lo inet loopback

auto $INTERFACE
iface $INTERFACE inet static
    address $IP_ADDR
    netmask $NETMASK_DOT
    gateway $GATEWAY
EOF
        systemctl restart networking || { log "ERROR" "重启网络服务失败"; exit 1; }
        log "INFO" "已设置静态 IP: $IP_ADDR"
        sleep 5
    fi

    RESOLV_CONF_BACKUP="/etc/resolv.conf.bak"
    if [ -e /etc/resolv.conf ]; then
        if [ -L /etc/resolv.conf ]; then
            cp -a /etc/resolv.conf "$RESOLV_CONF_BACKUP"
            rm -f /etc/resolv.conf
        else
            mv /etc/resolv.conf "$RESOLV_CONF_BACKUP" 2>/dev/null
        fi
    fi
    echo "nameserver 127.0.0.1" > /etc/resolv.conf || { log "ERROR" "无法写入 /etc/resolv.conf"; exit 1; }
    chattr +i /etc/resolv.conf || log "WARN" "无法锁定 /etc/resolv.conf"

    sysctl -w net.ipv4.ip_forward=1 > /dev/null || { log "ERROR" "启用 IPv4 转发失败"; exit 1; }
    sysctl -w net.ipv6.conf.all.forwarding=1 > /dev/null 2>&1 || log "WARN" "启用 IPv6 转发失败"
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    log "INFO" "网络配置完成"
}

# 配置防火墙
setup_firewall() {
    log "INFO" "配置防火墙规则..."
    if [ "$USE_NFTABLES" = "yes" ]; then
        nft flush ruleset
        cat << EOF > /etc/nftables.conf
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        ct state established,related accept
        ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } accept
        tcp dport 22 accept
        udp dport 53 accept
    }
    chain forward {
        type filter hook forward priority 0; policy accept;
        iifname "$INTERFACE" accept
    }
}
table inet nat {
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        oifname "$INTERFACE" masquerade
    }
}
EOF
        chmod +x /etc/nftables.conf
        nft -f /etc/nftables.conf || { log "ERROR" "应用 nftables 规则失败"; exit 1; }
        systemctl enable nftables 2>/dev/null || log "WARN" "无法启用 nftables 服务"
    else
        iptables -F && iptables -t nat -F || { log "ERROR" "清理 IPv4 规则失败"; exit 1; }
        iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
        iptables -A INPUT -s 10.0.0.0/8 -j ACCEPT
        iptables -A INPUT -s 172.16.0.0/12 -j ACCEPT
        iptables -A INPUT -s 192.168.0.0/16 -j ACCEPT
        iptables -A INPUT -p tcp --dport 22 -j ACCEPT
        iptables -A INPUT -p udp --dport 53 -j ACCEPT
        iptables -A FORWARD -i "$INTERFACE" -j ACCEPT
        iptables -t nat -A POSTROUTING -o "$INTERFACE" -j MASQUERADE
        
        if command -v ip6tables > /dev/null 2>&1; then
            ip6tables -F || { log "ERROR" "清理 IPv6 规则失败"; exit 1; }
            ip6tables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
            ip6tables -A INPUT -p tcp --dport 22 -j ACCEPT
            ip6tables -A INPUT -p udp --dport 53 -j ACCEPT
            ip6tables -A FORWARD -i "$INTERFACE" -j ACCEPT
        fi
        
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4 || { log "ERROR" "保存 IPv4 规则失败"; exit 1; }
        [ -x /sbin/ip6tables ] && ip6tables-save > /etc/iptables/rules.v6 || log "WARN" "无法保存 IPv6 规则"
        apt install -y iptables-persistent > /dev/null 2>&1 || log "WARN" "安装 iptables-persistent 失败"
    fi
    log "INFO" "防火墙配置完成"
}

# 检查系统版本和型号
check_system() {
    log "INFO" "正在检测系统信息..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        SYSTEM_NAME="${PRETTY_NAME:-未知系统}"
        SYSTEM_ID="${ID:-unknown}"
        SYSTEM_VERSION="${VERSION_ID:-unknown}"
        log "INFO" "系统: $SYSTEM_NAME ($SYSTEM_ID $SYSTEM_VERSION)"
    else
        log "WARN" "无法读取 /etc/os-release，系统信息未知"
        SYSTEM_NAME="未知系统"
        SYSTEM_ID="unknown"
        SYSTEM_VERSION="unknown"
    fi
    ARCH=$(uname -m)
    log "INFO" "架构: $ARCH"
    if [ -f /proc/cpuinfo ]; then
        # 只取第一行有效的硬件型号，避免重复
        HARDWARE_MODEL=$(grep -i -m 1 "^Model" /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//')
        [ -z "$HARDWARE_MODEL" ] && HARDWARE_MODEL=$(grep -i -m 1 "^Hardware" /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//')
        [ -z "$HARDWARE_MODEL" ] && HARDWARE_MODEL="未知型号"
    else
        HARDWARE_MODEL="未知型号"
    fi
    log "INFO" "硬件型号: $HARDWARE_MODEL"
    case "$SYSTEM_ID" in
        "ubuntu"|"debian")
            if echo "$SYSTEM_VERSION" | grep -q "24.04"; then
                log "INFO" "检测到 Ubuntu 24.04 或类似系统，使用 nftables"
                USE_NFTABLES="yes"
            else
                log "INFO" "检测到 Debian/Ubuntu 系统，使用 iptables"
                USE_NFTABLES="no"
            fi
            ;;
        *)
            log "WARN" "未知系统类型 ($SYSTEM_ID)，默认使用 iptables"
            USE_NFTABLES="no"
            ;;
    esac
    if echo "$HARDWARE_MODEL" | grep -qi "NanoPi R2S"; then
        log "INFO" "检测到 NanoPi R2S，优化网络接口检测"
        EXPECTED_INTERFACE="end0"
    else
        EXPECTED_INTERFACE=""
    fi
}


# 检查状态
check_status() {
    log "INFO" "检查服务状态..."
    log "DEBUG" "检查 sing-box 服务状态..."
    if systemctl is-active sing-box > /dev/null 2>&1; then
        log "INFO" "sing-box 服务运行正常"
    else
        log "ERROR" "sing-box 服务未运行，请检查日志: journalctl -u sing-box"
        exit 1
    fi
}

# 卸载函数
uninstall() {
    log "INFO" "开始卸载 sing-box..."
    
    systemctl stop sing-box 2>/dev/null && log "INFO" "已停止 sing-box 服务" || log "INFO" "sing-box 服务未运行"
    systemctl disable sing-box 2>/dev/null && log "INFO" "已禁用 sing-box 服务" || log "INFO" "sing-box 服务未启用"
    rm -f /etc/systemd/system/sing-box.service && systemctl daemon-reload || log "WARN" "删除服务文件失败"

    rm -f /usr/local/bin/sing-box && log "INFO" "已移除 sing-box 可执行文件" || log "WARN" "未找到 sing-box 可执行文件"
    rm -f /usr/local/bin/upconfig.sh && log "INFO" "已移除更新脚本" || log "WARN" "未找到更新脚本"
    (crontab -l 2>/dev/null | grep -v "upconfig.sh") | crontab - || log "WARN" "清理 crontab 失败"
    rm -rf /etc/sing-box && log "INFO" "已移除配置文件目录" || log "WARN" "未找到配置文件目录"

    RESOLV_CONF_BACKUP="/etc/resolv.conf.bak"
    if [ -e /etc/resolv.conf ]; then
        if lsattr /etc/resolv.conf 2>/dev/null | grep -q "i----"; then
            chattr -i /etc/resolv.conf
        fi
        rm -f /etc/resolv.conf
    fi
    if [ -e "$RESOLV_CONF_BACKUP" ]; then
        mv "$RESOLV_CONF_BACKUP" /etc/resolv.conf || log "WARN" "无法恢复原始 resolv.conf"
    else
        ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf 2>/dev/null || log "WARN" "无法恢复默认 DNS 配置"
    fi

    sysctl -w net.ipv4.ip_forward=0 > /dev/null 2>&1 || log "WARN" "禁用 IPv4 转发失败"
    sysctl -w net.ipv6.conf.all.forwarding=0 > /dev/null 2>&1 || log "WARN" "禁用 IPv6 转发失败"
    sed -i '/net.ipv4.ip_forward=1/d' /etc/sysctl.conf
    sed -i '/net.ipv6.conf.all.forwarding=1/d' /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1 || log "WARN" "应用 sysctl 配置失败"

    if [ "$USE_NFTABLES" = "yes" ]; then
        nft flush ruleset && rm -f /etc/nftables.conf && systemctl disable nftables 2>/dev/null || log "WARN" "清理 nftables 失败"
    else
        iptables -F && iptables -t nat -F || log "WARN" "清理 IPv4 规则失败"
        [ -x /sbin/ip6tables ] && ip6tables -F || log "WARN" "清理 IPv6 规则失败"
        rm -rf /etc/iptables && apt remove -y iptables-persistent > /dev/null 2>&1 || log "WARN" "清理 iptables 配置失败"
    fi

    if [ -f /etc/netplan/01-netcfg.yaml ]; then
        INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
        if [ -n "$INTERFACE" ]; then
            rm -f /etc/netplan/01-netcfg.yaml
            cat << EOF > /etc/netplan/01-netcfg.yaml
network:
  version: 2
  ethernets:
    $INTERFACE:
      dhcp4: yes
EOF
            chmod 600 /etc/netplan/01-netcfg.yaml
            netplan apply || log "WARN" "恢复 DHCP 失败"
        fi
    fi

    systemctl enable systemd-resolved 2>/dev/null && systemctl start systemd-resolved 2>/dev/null || log "WARN" "恢复 systemd-resolved 失败"
    log "INFO" "卸载完成，系统已恢复"
}

# 主执行流程
main() {
    check_system
    if [ "$1" = "uninstall" ]; then
        uninstall
    else
        get_network_info
        check_network
        update_and_install
        install_singbox
        setup_update_script
        download_config
        configure_network  # 先配置网络和 DNS
        release_port_53   # 释放 53 端口
        setup_service     # 最后启动 sing-box
        setup_firewall
        check_status
        log "INFO" "部署完成！请将其他设备的网关和 DNS 指向: $IP_ADDR"
    fi
}

main "$1"
