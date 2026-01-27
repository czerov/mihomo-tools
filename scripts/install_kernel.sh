#!/bin/bash

# 1. 加载环境
if [ -f "/etc/mihomo/.env" ]; then source /etc/mihomo/.env; fi

# 架构检测 (只做 amd64 和 arm64 的简单判断)
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    PLATFORM="linux-amd64-compatible"
elif [[ "$ARCH" == "aarch64" ]]; then
    PLATFORM="linux-arm64"
else
    echo "不支持的架构: $ARCH"
    exit 1
fi

# ==========================================
# 核心改动：自动 vs 手动模式判断
# ==========================================
MODE=$1  # 接收第一个参数

if [[ "$MODE" == "auto" ]]; then
    # --- 自动模式 (一键脚本调用) ---
    echo "🤖 检测到自动安装模式，正在获取最新版本..."
    # 自动去 GitHub API 抓取最新 Release 的 Tag (例如 v1.18.3)
    TAG=$(curl -s "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" | grep -oP '"tag_name": "\K(.*)(?=")')
    
    if [ -z "$TAG" ]; then
        echo "❌ 无法获取最新版本号，请检查网络。"
        exit 1
    fi
    echo "✅ 锁定最新版本: ${TAG}"

else
    # --- 手动模式 (菜单调用) ---
    echo "正在获取版本列表..."
    # 这里为了简单，手动模式也默认推荐最新版，或者你可以保留原来的列表逻辑
    # 这里演示最简化的逻辑：直接询问是否安装最新版
    LATEST_TAG=$(curl -s "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" | grep -oP '"tag_name": "\K(.*)(?=")')
    
    echo "当前最新版本: ${LATEST_TAG}"
    read -p "是否安装此版本? (y/n): " choice
    if [[ "$choice" != "y" ]]; then
        echo "已取消。"
        exit 0
    fi
    TAG=$LATEST_TAG
fi
# ==========================================

# 2. 构建下载链接
# 这里的 GH_PROXY 来自 .env，如果没有就为空
DOWNLOAD_URL="${GH_PROXY}https://github.com/MetaCubeX/mihomo/releases/download/${TAG}/mihomo-${PLATFORM}-${TAG}.gz"

echo "⬇️  正在下载内核..."
echo "地址: $DOWNLOAD_URL"

# 3. 下载并安装
curl -L -o /tmp/mihomo.gz "$DOWNLOAD_URL"

if [ $? -ne 0 ]; then
    echo "❌ 下载失败！请检查网络或代理设置。"
    rm -f /tmp/mihomo.gz
    exit 1
fi

echo "📦 正在解压并安装..."
gunzip -f /tmp/mihomo.gz
mv /tmp/mihomo ${MIHOMO_PATH}/mihomo
chmod +x ${MIHOMO_PATH}/mihomo

# 4. 只有在服务已存在时才尝试重启，防止报错
if systemctl list-units --full -all | grep -q "mihomo.service"; then
    echo "🔄 重启服务..."
    systemctl restart mihomo
fi

echo "✅ Mihomo 内核 (${TAG}) 安装/更新 成功！"
