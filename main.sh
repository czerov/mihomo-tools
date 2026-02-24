#!/bin/bash
# main.sh - Mihomo 命令行管理工具

MIHOMO_DIR="/etc/mihomo"
ENV_FILE="${MIHOMO_DIR}/.env"
LOG_FILE="/var/log/mihomo.log"
SVC_CORE="mihomo.service"
CORE_BIN="/usr/bin/mihomo-core"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
if [ -f "$ENV_FILE" ]; then source "$ENV_FILE"; fi

check_status() {
    if systemctl is-active --quiet $SVC_CORE; then c="${GREEN}运行中${NC}"; else c="${RED}已停止${NC}"; fi
    echo -e "内核状态: ${c}"
}

get_version() {
    if [ -f "$CORE_BIN" ]; then $CORE_BIN -v | head -n 1 | awk '{print $3}'; else echo "未安装"; fi
}

update_kernel() {
    echo "🔍 正在检查 GitHub 最新版本..."
    LATEST_VER=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep "tag_name" | cut -d '"' -f 4)
    LATEST_VER=${LATEST_VER:-v1.18.1}

    echo -e "发现版本: ${GREEN}${LATEST_VER}${NC}"
    echo "------------------------------------------------"
    echo -e "请选择下载规格 (PVE LXC 报错请选 1):"
    echo -e "1. ${GREEN}amd64 (通用兼容版)${NC} - 推荐"
    echo -e "2. ${BLUE}amd64-v3 (高性能版)${NC}"
    echo "------------------------------------------------"
    read -p "选择 [1-2]: " K_TYPE
    
    if [ "$K_TYPE" == "2" ]; then 
        PLATFORM="amd64-v3"
    else 
        PLATFORM="amd64"
    fi
    
    URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_VER}/mihomo-linux-${PLATFORM}-${LATEST_VER}.gz"
    
    echo "⬇️  正在下载..."
    wget -O /tmp/mihomo.gz "$URL"
    if [ $? -eq 0 ]; then
        systemctl stop $SVC_CORE
        gzip -d -f /tmp/mihomo.gz
        mv /tmp/mihomo "$CORE_BIN"
        chmod +x "$CORE_BIN"
        systemctl start $SVC_CORE
        echo -e "${GREEN}✅ 内核已成功更换为 ${PLATFORM}${NC}"
    else
        echo -e "${RED}❌ 下载失败${NC}"
    fi
}

while true; do
    clear
    echo -e "${BLUE}=== Mihomo 管理助手 ===${NC}"
    echo -e " 运行状态: $(check_status)"
    echo -e " 内核版本: $(get_version)"
    echo "-------------------------------------------"
    echo " 1. 更新/修复 Mihomo 内核 (解决v3报错)"
    echo " 2. 服务管理 (启动/停止/重启)"
    echo " 0. 退出"
    read -p "请输入选项: " CHOICE
    case $CHOICE in
        1) update_kernel; read -p "按回车继续..." ;;
        2) systemctl restart $SVC_CORE; echo "服务已重启"; sleep 1 ;;
        0) exit 0 ;;
        *) echo "无效选项"; sleep 1 ;;
    esac
done
