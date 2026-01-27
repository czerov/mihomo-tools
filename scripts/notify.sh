#!/bin/bash
# scripts/notify.sh

if [ -f "/etc/mihomo/.env" ]; then source /etc/mihomo/.env; fi

TITLE="$1"
CONTENT="$2"
FULL_TIME=$(date "+%Y-%m-%d %H:%M:%S")

# 1. Telegram
if [[ "$NOTIFY_TG" == "true" && -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]]; then
    # 格式：标题 -> 内容 -> 时间
    TG_MSG="<b>${TITLE}</b>%0A${CONTENT}%0A📅 ${FULL_TIME}"
    curl -s -o /dev/null -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TG_CHAT_ID}" -d text="${TG_MSG}" -d parse_mode="HTML"
fi

# 2. Webhook API
if [[ "$NOTIFY_API" == "true" && -n "$NOTIFY_API_URL" ]]; then
    SAFE_TITLE=$(echo "$TITLE" | sed 's/"/\\"/g')
    SAFE_CONTENT=$(echo "${CONTENT}\n📅 ${FULL_TIME}" | sed 's/"/\\"/g')
    curl -s -o /dev/null -X POST -H "Content-Type: application/json" \
        -d "{\"title\": \"${SAFE_TITLE}\", \"message\": \"${SAFE_CONTENT}\"}" \
        "$NOTIFY_API_URL"
fi
