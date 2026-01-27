#!/bin/bash

# 1. 导入基础环境
if [ -f "/etc/mihomo/.env" ]; then
    source /etc/mihomo/.env
else
    echo "错误：未找到 .env 配置文件！"
    exit 1
fi

CONFIG_FILE="${MIHOMO_PATH}/config.yaml"
BACKUP_FILE="${MIHOMO_PATH}/config.yaml.bak"
TEMP_FILE="/tmp/mihomo_config_new.yaml"

# 2. 核心函数：安全校验与应用
apply_config() {
    local target_file=$1
    echo "正在校验配置文件有效性..."
    
    # 校验
    ${MIHOMO_PATH}/mihomo -t -d ${MIHOMO_PATH} -f "$target_file"
    
    if [ $? -eq 0 ]; then
        echo "✅ 配置校验通过！"
        if [ -f "$CONFIG_FILE" ]; then
            cp "$CONFIG_FILE" "$BACKUP_FILE"
        fi
        cp "$target_file" "$CONFIG_FILE"
        
        # 热重载配置
        curl -X PUT -H "Content-Type: application/json" -d '{"path": "'$CONFIG_FILE'"}' "http://127.0.0.1:9090/configs?force=true" -s > /dev/null
        
        # 重启服务确保万无一失
        systemctl restart mihomo
        echo "配置已应用并重启服务。"
    else
        echo "❌ 配置文件校验失败！更新已取消。"
        rm -f "$target_file"
        exit 1
    fi
}

# --- 新增：保存订阅链接到 .env ---
save_url_to_env() {
    local url=$1
    local env_file="/etc/mihomo/.env"
    
    # 使用 sed 替换或追加 SUB_URL (使用 | 作为分隔符避免 URL 中的 / 冲突)
    if grep -q "^SUB_URL=" "$env_file"; then
        sed -i "s|^SUB_URL=.*|SUB_URL=\"$url\"|" "$env_file"
    else
        echo "" >> "$env_file"
        echo "SUB_URL=\"$url\"" >> "$env_file"
    fi
    echo "✅ 订阅链接已保存到系统配置(.env)，下次可自动更新。"
}

# 3. 从 URL 更新
update_from_url() {
    local url=$1
    
    # 场景A：没有传参 -> 尝试读取 .env 里的 SUB_URL
    if [ -z "$url" ]; then
        url=$SUB_URL
    fi
    
    # 场景B：.env 里也没有 -> 必须手动输入
    if [ -z "$url" ]; then
        echo "未检测到已保存的订阅链接。"
        read -p "请输入订阅链接: " input_url
        if [ -z "$input_url" ]; then echo "输入为空，取消操作。"; exit 1; fi
        url=$input_url
        
        # 询问是否保存
        read -p "是否保存此链接以便自动更新？(y/n): " save_choice
        if [ "$save_choice" == "y" ]; then
            save_url_to_env "$url"
        fi
    else
        # 场景C：虽然有链接（可能是参数传的，也可能是 .env 读的）
        # 如果是手动输入的场景（判断逻辑：当前url不等于.env里的url），也可以顺手存一下
        # 这里为了简化，我们只在脚本被手动调用且参数不为空时，如果是新链接可以提示保存（逻辑略复杂，暂且略过，保持简单）
        # 简单逻辑：如果用户是在菜单里选了“手动输入”，main.sh 会传参进来。
        # 我们在这里判断一下：如果 .env 里的链接 和 当前用的链接 不一样，问一句要不要更新保存
        if [ "$url" != "$SUB_URL" ] && [ ! -z "$SUB_URL" ]; then
             read -p "检测到使用的新链接，是否覆盖保存旧链接？(y/n): " update_choice
             if [ "$update_choice" == "y" ]; then
                save_url_to_env "$url"
             fi
        elif [ -z "$SUB_URL" ]; then
             # 如果以前没存过，直接存
             save_url_to_env "$url"
        fi
    fi
    
    echo "正在下载配置: $url"
    curl -L -o "$TEMP_FILE" "$url"
    
    if [ $? -ne 0 ]; then
        echo "❌ 下载失败，请检查网络。"
        exit 1
    fi
    
    apply_config "$TEMP_FILE"
    rm -f "$TEMP_FILE"
}

# 4. 本地编辑模式
edit_local() {
    if [ ! -f "$CONFIG_FILE" ]; then touch "$CONFIG_FILE"; fi
    cp "$CONFIG_FILE" "$TEMP_FILE"
    
    if command -v nano >/dev/null 2>&1; then nano "$TEMP_FILE"; else vi "$TEMP_FILE"; fi
    
    read -p "是否应用修改？(y/n): " confirm
    if [ "$confirm" == "y" ]; then
        apply_config "$TEMP_FILE"
    else
        echo "修改已丢弃。"
    fi
    rm -f "$TEMP_FILE"
}

case "$1" in
    update) update_from_url "$2" ;;
    edit) edit_local ;;
    *) echo "用法: $0 {update [url] | edit}" ;;
esac
