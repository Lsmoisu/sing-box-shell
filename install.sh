#!/bin/sh

# 日志级别设置 (DEBUG/INFO)，全局变量
LOG_LEVEL="INFO"  # 默认设置为 INFO

# 日志函数，使用 printf 替代 echo -e
log() {
    level="$1"
    msg="$2"
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 颜色定义（使用转义序列）
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

# 获取默认网络接口和IP地址
get_network_info() {
    log "DEBUG" "开始检测网络接口和 IP 地址..."
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [ -z "$INTERFACE" ]; then
        log "ERROR" "无法检测到默认网络接口"
        exit 1
    fi
    IP_ADDR=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
    if [ -z "$IP_ADDR" ]; then
        log "ERROR" "无法获取 IP 地址"
        exit 1
    fi
    log "INFO" "检测到网络接口: $INTERFACE, IP 地址: $IP_ADDR"
}

# 检查网络连接
check_network() {
    log "INFO" "检查网络连接..."
    log "DEBUG" "执行 ping 测试到 8.8.8.8..."
    if ! ping -c 3 8.8.8.8 > /dev/null 2>&1; then
        log "ERROR" "无法连接到网络，请检查网络状态"
        exit 1
    fi
    log "DEBUG" "网络连接测试成功"
}

# 更新系统和安装工具
update_and_install() {
    log "INFO" "是否快速安装以跳过系统更新？(若安装失败请不要跳过，默认 N) [Y/N]: "
    read FAST_INSTALL
    case "$FAST_INSTALL" in
        [Yy]*)
            log "INFO" "用户选择快速安装，跳过 apt upgrade..."
            ;;
        *)
            log "INFO" "用户选择完整安装，将执行 apt upgrade..."
            FAST_INSTALL="N"
            ;;
    esac

    log "INFO" "更新软件源..."
    log "DEBUG" "执行 apt update..."
    apt update > /dev/null 2>&1 || { log "ERROR" "apt update 失败"; exit 1; }
    
    if [ "$FAST_INSTALL" != "Y" ] && [ "$FAST_INSTALL" != "y" ]; then
        log "INFO" "执行系统更新（此过程可能较耗时）..."
        log "DEBUG" "执行 apt upgrade..."
        apt upgrade -y > /dev/null 2>&1 || log "WARN" "apt upgrade 失败，继续执行..."
    fi
    
    log "INFO" "安装必要工具..."
    log "DEBUG" "安装 wget、tar、iptables..."
    apt install -y wget tar iptables > /dev/null 2>&1 || { log "ERROR" "安装基本工具失败"; exit 1; }
    log "DEBUG" "尝试安装 ip6tables..."
    apt install -y ip6tables > /dev/null 2>&1 || log "WARN" "无法安装 ip6tables，IPv6 支持可能受限，继续执行..."
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
    log "INFO" "检测到系统: $OS-$ARCH"

    SINGBOX_VERSION="1.11.4"
    DEFAULT_SINGBOX_URL="https://gh.aaa.team/github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-${OS}-${ARCH}.tar.gz"
    
    # 提示用户是否使用自定义下载地址
    log "INFO" "是否使用自定义 sing-box 下载地址？(默认 N，使用 ${DEFAULT_SINGBOX_URL}) [Y/N]: "
    read USE_CUSTOM_URL
    case "$USE_CUSTOM_URL" in
        [Yy]*)
            log "INFO" "请输入自定义 sing-box 下载地址（需为 .tar.gz 格式）:"
            read SINGBOX_URL
            [ -z "$SINGBOX_URL" ] && { log "ERROR" "下载地址不能为空"; exit 1; }
            log "INFO" "使用自定义下载地址: $SINGBOX_URL"
            ;;
        *)
            SINGBOX_URL="$DEFAULT_SINGBOX_URL"
            log "INFO" "使用默认下载地址: $SINGBOX_URL"
            ;;
    esac

    log "INFO" "正在下载 sing-box..."
    log "DEBUG" "执行 wget 下载 sing-box..."
    wget -q -O sing-box.tar.gz "$SINGBOX_URL" || { log "ERROR" "下载 sing-box 失败"; exit 1; }
    log "INFO" "解压 sing-box..."
    log "DEBUG" "执行 tar 解压..."
    tar -xzf sing-box.tar.gz || { log "ERROR" "解压 sing-box 失败"; exit 1; }
    [ -f "sing-box-${SINGBOX_VERSION}-${OS}-${ARCH}/sing-box" ] || { log "ERROR" "未找到 sing-box 可执行文件"; exit 1; }
    mv "sing-box-${SINGBOX_VERSION}-${OS}-${ARCH}/sing-box" /usr/local/bin/
    chmod +x /usr/local/bin/sing-box
    rm -rf sing-box.tar.gz "sing-box-${SINGBOX_VERSION}-${OS}-${ARCH}"
    
    command -v sing-box > /dev/null 2>&1 || { log "ERROR" "sing-box 安装失败"; exit 1; }
    log "INFO" "sing-box 安装成功"
}

# 配置自动更新脚本
setup_update_script() {
    log "INFO" "设置自动更新脚本..."
    UP_CONFIG_URL="https://gh.aaa.team/https://raw.githubusercontent.com/Lsmoisu/sing-box-shell/refs/heads/main/upconfig.sh"
    log "INFO" "正在下载更新脚本..."
    log "DEBUG" "执行 wget 下载 upconfig.sh..."
    wget -q -O /usr/local/bin/upconfig.sh "$UP_CONFIG_URL" || { log "ERROR" "下载 upconfig.sh 失败"; exit 1; }
    chmod +x /usr/local/bin/upconfig.sh
    [ -x /usr/local/bin/upconfig.sh ] || { log "ERROR" "upconfig.sh 设置权限失败"; exit 1; }
    
    log "DEBUG" "配置 crontab 任务..."
    (crontab -l 2>/dev/null | grep -v "upconfig.sh"; echo "* * * * * /usr/local/bin/upconfig.sh") | crontab - || log "WARN" "crontab 配置失败"
}

# 下载配置文件
download_config() {
    DEFAULT_CONFIG_URL="https://sub.aaa.team/config-zz-realip-route"
    log "INFO" "请输入配置文件 URL（回车使用默认: $DEFAULT_CONFIG_URL）:"
    read CONFIG_URL
    [ -z "$CONFIG_URL" ] && CONFIG_URL="$DEFAULT_CONFIG_URL" && log "INFO" "使用默认配置文件: $CONFIG_URL"
    
    mkdir -p /etc/sing-box
    log "INFO" "正在下载配置文件: $CONFIG_URL"
    log "DEBUG" "执行 wget 下载配置文件..."
    wget -q -O /etc/sing-box/config.json "$CONFIG_URL" || { log "ERROR" "下载配置文件失败"; exit 1; }
}

# 配置服务
setup_service() {
    log "INFO" "配置 sing-box 服务..."
    log "DEBUG" "创建 systemd 服务文件..."
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

    log "DEBUG" "启动 sing-box 服务..."
    systemctl daemon-reload && systemctl enable sing-box && systemctl start sing-box || { log "ERROR" "服务配置失败"; exit 1; }
}

# 配置网络
configure_network() {
    log "INFO" "配置网络设置..."
    log "DEBUG" "停止 systemd-resolved 服务..."
    systemctl stop systemd-resolved 2>/dev/null && systemctl disable systemd-resolved 2>/dev/null || log "WARN" "systemd-resolved 未运行"
    
    log "DEBUG" "检查并配置 /etc/resolv.conf..."
    if [ -e /etc/resolv.conf ]; then
        # 检查是否为符号链接并移除
        [ -L /etc/resolv.conf ] && rm -f /etc/resolv.conf && log "DEBUG" "已移除 /etc/resolv.conf 符号链接"
        # 检查 immutable 属性并移除
        if lsattr /etc/resolv.conf 2>/dev/null | grep -q "i----"; then
            log "DEBUG" "检测到 /etc/resolv.conf 为 immutable，正在移除该属性..."
            chattr -i /etc/resolv.conf || { log "ERROR" "无法移除 /etc/resolv.conf 的 immutable 属性，请手动检查"; exit 1; }
        fi
    fi
    
    # 写入新的 resolv.conf
    log "DEBUG" "写入 nameserver 127.0.0.1 到 /etc/resolv.conf..."
    echo "nameserver 127.0.0.1" > /etc/resolv.conf || { log "ERROR" "无法写入 /etc/resolv.conf，请检查权限或文件系统"; exit 1; }
    
    # 设置 immutable 属性
    log "DEBUG" "设置 /etc/resolv.conf 为 immutable..."
    chattr +i /etc/resolv.conf || log "WARN" "无法锁定 /etc/resolv.conf，可能被其他进程覆盖"
    
    log "DEBUG" "启用 IP 转发..."
    sysctl -w net.ipv4.ip_forward=1 > /dev/null || { log "ERROR" "启用 IPv4 转发失败"; exit 1; }
    sysctl -w net.ipv6.conf.all.forwarding=1 > /dev/null 2>&1 || log "WARN" "启用 IPv6 转发失败，可能不支持 IPv6"
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
}

# 配置 iptables 和 ip6tables
setup_firewall() {
    log "INFO" "配置防火墙规则..."
    log "DEBUG" "清理 IPv4 防火墙规则..."
    iptables -F && iptables -t nat -F || { log "ERROR" "清理 IPv4 规则失败"; exit 1; }
    
    # IPv4 规则
    iptables -A INPUT -p udp --dport 53 -j ACCEPT
    iptables -A FORWARD -i "$INTERFACE" -j ACCEPT
    iptables -t nat -A POSTROUTING -o "$INTERFACE" -j MASQUERADE
    
    # 检查 ip6tables 是否可用
    if command -v ip6tables > /dev/null 2>&1; then
        log "DEBUG" "清理并配置 IPv6 防火墙规则..."
        ip6tables -F || { log "ERROR" "清理 IPv6 规则失败"; exit 1; }
        ip6tables -A INPUT -p udp --dport 53 -j ACCEPT
        ip6tables -A FORWARD -i "$INTERFACE" -j ACCEPT
    else
        log "WARN" "ip6tables 未安装，跳过 IPv6 防火墙配置"
    fi
    
    mkdir -p /etc/iptables
    log "DEBUG" "保存防火墙规则..."
    iptables-save > /etc/iptables/rules.v4 || { log "ERROR" "保存 IPv4 规则失败"; exit 1; }
    [ -x /sbin/ip6tables ] && ip6tables-save > /etc/iptables/rules.v6 || log "WARN" "无法保存 IPv6 规则，IPv6 支持可能不可用"
    
    echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
    echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
    log "DEBUG" "安装 iptables-persistent..."
    apt install -y iptables-persistent > /dev/null 2>&1 || { log "ERROR" "安装 iptables-persistent 失败"; exit 1; }
}

# 检查状态
check_status() {
    log "INFO" "检查服务状态..."
    log "DEBUG" "检查 sing-box 服务状态..."
    systemctl status sing-box > /dev/null 2>&1 && log "INFO" "sing-box 服务运行正常" || log "ERROR" "sing-box 服务未运行"
}

# 卸载函数
uninstall() {
    log "INFO" "开始卸载 sing-box 及相关配置..."

    # 停止并禁用 sing-box 服务
    log "INFO" "停止并禁用 sing-box 服务..."
    systemctl stop sing-box 2>/dev/null
    systemctl disable sing-box 2>/dev/null
    rm -f /etc/systemd/system/sing-box.service
    systemctl daemon-reload
    log "DEBUG" "已移除 sing-box 服务文件"

    # 移除 sing-box 可执行文件
    log "INFO" "移除 sing-box 可执行文件..."
    rm -f /usr/local/bin/sing-box && log "DEBUG" "已移除 /usr/local/bin/sing-box" || log "WARN" "未找到 /usr/local/bin/sing-box"

    # 移除自动更新脚本和 crontab 任务
    log "INFO" "移除自动更新脚本和 crontab 任务..."
    rm -f /usr/local/bin/upconfig.sh && log "DEBUG" "已移除 /usr/local/bin/upconfig.sh" || log "WARN" "未找到 /usr/local/bin/upconfig.sh"
    (crontab -l 2>/dev/null | grep -v "upconfig.sh") | crontab - || log "WARN" "清理 crontab 任务失败"

    # 移除配置文件
    log "INFO" "移除 sing-box 配置文件..."
    rm -rf /etc/sing-box && log "DEBUG" "已移除 /etc/sing-box 目录" || log "WARN" "未找到 /etc/sing-box 目录"

    # 还原 /etc/resolv.conf
    log "INFO" "还原 /etc/resolv.conf..."
    if [ -e /etc/resolv.conf ]; then
        if lsattr /etc/resolv.conf 2>/dev/null | grep -q "i----"; then
            log "DEBUG" "检测到 /etc/resolv.conf 为 immutable，正在移除该属性..."
            chattr -i /etc/resolv.conf || log "WARN" "无法移除 /etc/resolv.conf 的 immutable 属性"
        fi
        # 恢复默认 DNS（这里假设使用 8.8.8.8，可根据系统调整）
        echo "nameserver 8.8.8.8" > /etc/resolv.conf && log "DEBUG" "已还原 /etc/resolv.conf" || log "WARN" "无法写入 /etc/resolv.conf"
    fi

    # 禁用 IP 转发并清理 sysctl 配置
    log "INFO" "禁用 IP 转发..."
    sysctl -w net.ipv4.ip_forward=0 > /dev/null 2>&1
    sysctl -w net.ipv6.conf.all.forwarding=0 > /dev/null 2>&1
    sed -i '/net.ipv4.ip_forward=1/d' /etc/sysctl.conf
    sed -i '/net.ipv6.conf.all.forwarding=1/d' /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1 && log "DEBUG" "已清理 /etc/sysctl.conf 中的 IP 转发配置" || log "WARN" "清理 sysctl 配置失败"

    # 清理防火墙规则
    log "INFO" "清理防火墙规则..."
    iptables -F && iptables -t nat -F && log "DEBUG" "已清理 IPv4 规则" || log "WARN" "清理 IPv4 规则失败"
    if command -v ip6tables > /dev/null 2>&1; then
        ip6tables -F && log "DEBUG" "已清理 IPv6 规则" || log "WARN" "清理 IPv6 规则失败"
    fi
    rm -rf /etc/iptables && log "DEBUG" "已移除 /etc/iptables 目录" || log "WARN" "未找到 /etc/iptables 目录"

    # 移除 iptables-persistent（可选，因为可能是系统原有组件）
    log "INFO" "卸载 iptables-persistent（可选）..."
    apt remove -y iptables-persistent > /dev/null 2>&1 && log "DEBUG" "已卸载 iptables-persistent" || log "WARN" "卸载 iptables-persistent 失败或未安装"

    # 恢复 systemd-resolved（如果之前被禁用）
    log "INFO" "尝试恢复 systemd-resolved 服务..."
    systemctl enable systemd-resolved 2>/dev/null && systemctl start systemd-resolved 2>/dev/null && log "DEBUG" "已恢复 systemd-resolved" || log "WARN" "恢复 systemd-resolved 失败，可能未安装"

    log "INFO" "卸载完成！系统已尽可能恢复到安装前的状态。"
}

# 主执行流程
main() {
    if [ "$1" = "uninstall" ]; then
        log "DEBUG" "检测到 uninstall 参数，开始执行卸载..."
        uninstall
    else
        log "DEBUG" "脚本开始执行安装流程..."
        get_network_info
        check_network
        update_and_install
        install_singbox
        setup_update_script
        download_config
        setup_service
        configure_network
        setup_firewall
        check_status
        log "INFO" "部署完成！请将其他设备的网关和 DNS 指向: $IP_ADDR"
        log "DEBUG" "脚本执行完成"
    fi
}

main "$1"
