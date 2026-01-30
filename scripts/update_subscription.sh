#!/bin/bash
# update_subscription.sh - 智能订阅更新 (仅变更时通知)

MIHOMO_DIR="/etc/mihomo"
ENV_FILE="${MIHOMO_DIR}/.env"
CONFIG_FILE="${MIHOMO_DIR}/config.yaml"
BACKUP_DIR="${MIHOMO_DIR}/backup"
NOTIFY_SCRIPT="${MIHOMO_DIR}/scripts/notify.sh"
TEMP_FILE="/tmp/config_new.yaml"

# 1. 加载环境变量
if [ -f "$ENV_FILE" ]; then source "$ENV_FILE"; fi

# 2. 检查订阅链接
if [ -z "$SUB_URL" ]; then
    echo "❌ 未配置订阅链接 (SUB_URL)，跳过更新。"
    exit 0
fi

mkdir -p "$BACKUP_DIR"

# 3. 下载新配置
echo "⬇️  正在下载订阅: $SUB_URL"
wget --no-check-certificate -O "$TEMP_FILE" "$SUB_URL" >/dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "❌ 下载失败，请检查网络或链接。"
    # 下载失败通常建议保留通知，或者您也可以注释掉下面这行
    bash "$NOTIFY_SCRIPT" "❌ 订阅更新失败" "无法连接到订阅服务器，请检查网络。"
    rm -f "$TEMP_FILE"
    exit 1
fi

# 4. 简单校验 (防止下载到空文件或报错页面)
if [ ! -s "$TEMP_FILE" ] || ! grep -qE "port:|mixed-port:|proxies:" "$TEMP_FILE"; then
    echo "❌ 下载的文件格式不正确，跳过更新。"
    rm -f "$TEMP_FILE"
    exit 1
fi

# 5. 【核心逻辑】比对文件差异
FILE_CHANGED=0
if [ -f "$CONFIG_FILE" ]; then
    # 使用 cmp 比较文件内容，-s 表示静默模式
    if cmp -s "$TEMP_FILE" "$CONFIG_FILE"; then
        echo "✅ 配置未发生变更，跳过更新。"
        FILE_CHANGED=0
    else
        echo "⚠️  检测到配置变更，准备覆盖..."
        FILE_CHANGED=1
    fi
else
    echo "⚠️  配置文件不存在，准备初始化..."
    FILE_CHANGED=1
fi

# 6. 执行更新 (仅在有变更时)
if [ "$FILE_CHANGED" -eq 1 ]; then
    # 备份旧文件
    cp "$CONFIG_FILE" "${BACKUP_DIR}/config_$(date +%Y%m%d%H%M).yaml" 2>/dev/null
    
    # 覆盖新文件
    mv "$TEMP_FILE" "$CONFIG_FILE"
    
    # 重启服务
    systemctl restart mihomo
    
    # ✅ 发送通知 (仅变更时)
    echo "🎉 订阅已更新并重启服务。"
    bash "$NOTIFY_SCRIPT" "♻️ 订阅已更新" "检测到配置变更，Mihomo 已自动重启加载新配置。"
else
    # ❌ 无变更，清理临时文件，不发通知
    rm -f "$TEMP_FILE"
fi
