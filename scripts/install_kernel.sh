#!/bin/bash
# install_kernel.sh - 智能架构适配版

if [ -f "/etc/mihomo/.env" ]; then source /etc/mihomo/.env; fi

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    # 核心修改：检测指令集
    if grep -q "avx2" /proc/cpuinfo && grep -q "bmi2" /proc/cpuinfo; then
        PLATFORM="linux-amd64-v3"
    else
        PLATFORM="linux-amd64"
    fi
elif [[ "$ARCH" == "aarch64" ]]; then
    PLATFORM="linux-arm64"
else
    echo "不支持的架构: $ARCH"
    exit 1
fi

MODE=$1
if [[ "$MODE" == "auto" ]]; then
    TAG=$(curl -s "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" | grep -oP '"tag_name": "\K(.*)(?=")')
else
    TAG=$(curl -s "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" | grep -oP '"tag_name": "\K(.*)(?=")')
    read -p "发现版本 ${TAG}，是否安装? (y/n): " choice
    [[ "$choice" != "y" ]] && exit 0
fi

DOWNLOAD_URL="${GH_PROXY}https://github.com/MetaCubeX/mihomo/releases/download/${TAG}/mihomo-${PLATFORM}-${TAG}.gz"

echo "⬇️  正在下载内核 (${PLATFORM})..."
curl -L -o /tmp/mihomo.gz "$DOWNLOAD_URL"

if [ $? -ne 0 ]; then
    echo "❌ 下载失败！"
    exit 1
fi

gunzip -f /tmp/mihomo.gz
mv /tmp/mihomo /usr/bin/mihomo-core
chmod +x /usr/bin/mihomo-core

if systemctl is-active --quiet mihomo.service; then
    systemctl restart mihomo
fi
echo "✅ 安装完成。"
