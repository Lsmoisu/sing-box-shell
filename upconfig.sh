#!/bin/bash

# 定义变量
REMOTE_URL="https://sub.aaa.team/config-66ca38b4bd8d"
LOCAL_CONFIG="/etc/sing-box/config.json"
TEMP_CONFIG="/tmp/sing-box-config.json.new"
LOG_FILE="/var/log/sing-box-config-update.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

# 确保日志目录存在
[ ! -d "/var/log" ] && mkdir -p /var/log

# 函数：记录日志
log() {
    echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
}

# 检查必要命令是否存在
if ! command -v curl &> /dev/null; then
    log "错误：curl 未安装"
    exit 1
fi

if ! command -v systemctl &> /dev/null; then
    log "错误：systemctl 未安装"
    exit 1
fi

# 下载远程配置文件到临时文件
if ! curl -s -m 30 "$REMOTE_URL" -o "$TEMP_CONFIG"; then
    log "错误：无法下载远程配置文件"
    exit 1
fi

# 检查本地配置文件是否存在
if [ ! -f "$LOCAL_CONFIG" ]; then
    log "警告：本地配置文件不存在，将使用新配置文件"
    mv "$TEMP_CONFIG" "$LOCAL_CONFIG"
    if systemctl restart sing-box &> /dev/null; then
        log "成功：初始化配置文件并重启 sing-box"
    else
        log "错误：初始化后重启 sing-box 失败"
    fi
    exit 0
fi

# 比较配置文件差异
if ! cmp -s "$TEMP_CONFIG" "$LOCAL_CONFIG"; then
    # 有差异，替换配置文件并重启服务
    if cp "$TEMP_CONFIG" "$LOCAL_CONFIG"; then
        # 验证配置文件格式（假设 sing-box 支持 config 检查）
        if sing-box check -c "$LOCAL_CONFIG" &> /dev/null; then
            if systemctl restart sing-box &> /dev/null; then
                log "成功：配置文件已更新并重启 sing-box"
            else
                log "错误：配置文件更新后重启 sing-box 失败"
                # 回滚到旧配置文件
                cp "$LOCAL_CONFIG.bak" "$LOCAL_CONFIG" 2>/dev/null
            fi
        else
            log "错误：新配置文件格式无效，不执行更新"
        fi
    else
        log "错误：替换配置文件失败"
    fi
else
    log "信息：配置文件无变化，跳过更新"
fi

# 清理临时文件
[ -f "$TEMP_CONFIG" ] && rm -f "$TEMP_CONFIG"

exit 0
