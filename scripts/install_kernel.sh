#!/bin/bash

# 1. 加载环境
if [ -f "/etc/mihomo/.env" ]; then source /etc/mihomo/.env; fi

MODE=$1

# 架构检测与 V3 自检
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    # 核心检测逻辑
    if grep -q "avx2" /proc/cpuinfo; then
        V3_SUPPORT=true
        DEFAULT_PLATFORM="linux-amd64"
    else
        V3_SUPPORT=false
        DEFAULT_PLATFORM="linux-amd64-compatible"
    fi

    # 如果是自动静默升级模式，直接应用最适合的版本
    if [[ "$MODE" == "auto" ]]; then
        PLATFORM=$DEFAULT_PLATFORM
    else
        echo "🔍 检测 CPU 指令集支持..."
        if $V3_SUPPORT; then
            echo "✅ 支持 x86_64-v3 (推荐: 高性能版)"
            DEFAULT_V="1"
        else
            echo "⚠️ 不支持 x86_64-v3 (推荐: 兼容版)"
            DEFAULT_V="2"
        fi
        echo "1) 高性能版 (linux-amd64)"
        echo "2) 兼容版 (linux-amd64-compatible)"
        read -p "请选择内核版本 [默认: $DEFAULT_V]: " CPU_CHOICE
        CPU_CHOICE=${CPU_CHOICE:-$DEFAULT_V}
        if [ "$CPU_CHOICE" == "1" ]; then
            PLATFORM="linux-amd64"
        else
            PLATFORM="linux-amd64-compatible"
        fi
    fi
elif [[ "$ARCH" == "aarch64" ]]; then
    PLATFORM="linux-arm64"
else
    echo "不支持的架构: $ARCH"
    exit 1
fi

# ==========================================
# 自动/手动模式判断 (获取版本号)
# ==========================================
if [[ "$MODE" == "auto" ]]; then
    echo "🤖 自动安装模式..."
    TAG=$(curl -s "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" | grep -oP '"tag_name": "\K(.*)(?=")')
    if [ -z "$TAG" ]; then
        echo "❌ 无法获取最新版本号，请检查网络。"
        exit 1
    fi
else
    echo "正在获取版本列表..."
    LATEST_TAG=$(curl -s "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" | grep -oP '"tag_name": "\K(.*)(?=")')
    echo "最新版本: ${LATEST_TAG}"
    read -p "是否安装此版本? (y/n): " choice
    if [[ "$choice" != "y" ]]; then
        echo "已取消。"
        exit 0
    fi
    TAG=$LATEST_TAG
fi
# ==========================================

# 2. 构建下载链接
DOWNLOAD_URL="${GH_PROXY}https://github.com/MetaCubeX/mihomo/releases/download/${TAG}/mihomo-${PLATFORM}-${TAG}.gz"

echo "⬇️  正在下载内核..."
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

# ==========================================
# 核心修复：智能重启逻辑
# ==========================================
# 只有当服务当前是 "active" (正在运行) 状态时，才执行重启
# 初次安装时服务是停止的，所以会跳过这一步，避免报错
if systemctl is-active --quiet mihomo.service; then
    echo "🔄 检测到服务正在运行，正在重启以应用新内核..."
    systemctl restart mihomo
    echo "✅ 服务重启完成。"
else
    # 这一步是为了安抚用户，告诉他没启动是正常的
    echo "✅ 内核安装完成 (服务未启动，请在配置订阅后手动启动)。"
fi
