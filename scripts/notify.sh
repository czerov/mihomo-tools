#!/bin/bash
# scripts/notify.sh
# 用法: bash notify.sh "标题" "内容"

# 1. 导入环境变量
if [ -f "/etc/mihomo/.env" ]; then
    source /etc/mihomo/.env
else
    exit 0
fi

# 2. 获取参数
TITLE="$1"
RAW_CONTENT="$2"
TIME=$(date "+%Y-%m-%d %H:%M:%S")

# 3. 格式化内容 (增加时间戳)
MSG_TEXT="[${TIME}] ${RAW_CONTENT}"

# --- 发送逻辑 ---

# [通道 A] Telegram
# 逻辑：开关必须为 true，且 Token 和 ChatID 不能为空
if [[ "$NOTIFY_TG" == "true" && -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]]; then
    # Telegram 使用 HTML 格式，需要简单的换行符处理
    TG_MSG="<b>${TITLE}</b>%0A${MSG_TEXT}"
    
    curl -s -o /dev/null -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TG_CHAT_ID}" \
        -d text="${TG_MSG}" \
        -d parse_mode="HTML"
fi

# [通道 B] 自定义 Webhook API
# 逻辑：开关必须为 true，且 URL 不能为空
if [[ "$NOTIFY_API" == "true" && -n "$NOTIFY_API_URL" ]]; then
    # 简单的 JSON 转义处理 (防止内容里的双引号破坏 JSON 结构)
    # 将内容中的 " 替换为 \"
    SAFE_TITLE=$(echo "$TITLE" | sed 's/"/\\"/g')
    SAFE_CONTENT=$(echo "$MSG_TEXT" | sed 's/"/\\"/g')

    curl -s -o /dev/null -X POST \
        -H "Content-Type: application/json" \
        -d "{\"title\": \"${SAFE_TITLE}\", \"message\": \"${SAFE_CONTENT}\"}" \
        "$NOTIFY_API_URL"
fi
