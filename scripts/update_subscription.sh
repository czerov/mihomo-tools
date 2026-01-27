#!/bin/bash
# scripts/update_subscription.sh

source /etc/mihomo/.env
CONFIG_FILE="/etc/mihomo/config.yaml"
BACKUP_FILE="/etc/mihomo/config.yaml.bak"

# 1. 获取订阅地址
if [ -z "$SUB_URL" ]; then
    bash /etc/mihomo/scripts/notify.sh "❌ 订阅更新失败" "未配置订阅链接 (.env SUB_URL 为空)"
    exit 1
fi

echo "正在下载订阅: $SUB_URL"

# 2. 下载到临时文件
curl -L -s -o /tmp/config_tmp.yaml "$SUB_URL"

# 3. 简单校验 (检查是否包含 'proxies' 关键字，防止下载到空文件或HTML)
if grep -q "proxies" /tmp/config_tmp.yaml || grep -q "proxy-providers" /tmp/config_tmp.yaml; then
    # 4. 备份并替换
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    mv /tmp/config_tmp.yaml "$CONFIG_FILE"
    
    # 5. 自动修补 external-ui (防止覆盖后面板打不开)
    if ! grep -q "external-ui" "$CONFIG_FILE"; then
        echo -e "\nexternal-ui: ui" >> "$CONFIG_FILE"
    fi
    
    # 6. 重载服务
    if systemctl is-active --quiet mihomo; then
        systemctl restart mihomo
        bash /etc/mihomo/scripts/notify.sh "✅ 订阅更新成功" "配置文件已更新并重载服务。"
    else
        bash /etc/mihomo/scripts/notify.sh "✅ 订阅更新成功" "配置文件已下载 (服务未运行)。"
    fi
else
    rm -f /tmp/config_tmp.yaml
    bash /etc/mihomo/scripts/notify.sh "❌ 订阅更新失败" "下载的文件格式不正确，已保留旧配置。"
    exit 1
fi
