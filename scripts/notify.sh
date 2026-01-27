#!/bin/bash
# scripts/notify.sh

# 引入环境变量
if [ -f "/etc/mihomo/.env" ]; then source /etc/mihomo/.env; fi

TITLE="$1"
CONTENT="$2"
# 获取完整日期时间 (例如: 2026-01-27 12:30:59)
CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S")

# --- 发送逻辑 ---

# 1. Telegram (HTML 格式)
if [[ "$NOTIFY_TG" == "true" && -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]]; then
    # 构造消息结构:
    # 标题 (加粗)
    # 内容
    # 📅 YYYY-MM-DD HH:MM:SS (紧接在内容下一行)
    TG_MSG="<b>${TITLE}</b>%0A${CONTENT}%0A📅 ${CURRENT_TIME}"
    
    curl -s -o /dev/null -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TG_CHAT_ID}" \
        -d text="${TG_MSG}" \
        -d parse_mode="HTML"
fi

# 2. Webhook API (JSON 格式)
if [[ "$NOTIFY_API" == "true" && -n "$NOTIFY_API_URL" ]]; then
    # 构造内容: 内容 [换行] 时间
    # 注意：很多 JSON 接收端（如飞书/钉钉）支持 \n 换行
    API_MSG="${CONTENT}\n📅 ${CURRENT_TIME}"
    
    # JSON 转义处理 (防止双引号破坏 JSON)
    SAFE_TITLE=$(echo "$TITLE" | sed 's/"/\\"/g')
    SAFE_MSG=$(echo "$API_MSG" | sed 's/"/\\"/g')

    # 部分环境 bash 对 \n 处理不同，这里确保它是转义过的
    # 如果对方 API 不支持换行，这行会显示在同一行
    curl -s -o /dev/null -X POST \
        -H "Content-Type: application/json" \
        -d "{\"title\": \"${SAFE_TITLE}\", \"message\": \"${SAFE_MSG}\"}" \
        "$NOTIFY_API_URL"
fi
