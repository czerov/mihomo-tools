#!/bin/bash

# 1. 导入基础环境配置
if [ -f "/etc/mihomo/.env" ]; then
    source /etc/mihomo/.env
else
    echo "错误：未找到 /etc/mihomo/.env 配置文件！"
    exit 1
fi

# 2. 定义颜色（让界面好看一点）
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 3. 权限检查
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}请以 root 权限运行此脚本${NC}"
    exit 1
fi

# 4. 主菜单函数
show_menu() {
    clear
    echo -e "${GREEN}====================================${NC}"
    echo -e "${GREEN}    Mihomo 模块化管理工具 (2026版)   ${NC}"
    echo -e "${GREEN}====================================${NC}"
    echo -e "1. 安装/更新 内核 (install_kernel)"
    echo -e "2. 管理服务 (启动/停止/重启) - [待开发]"
    echo -e "3. 更新配置 (Sub-Store/本地) - [待开发]"
    echo -e "4. 查看实时日志 - [待开发]"
    echo -e "5. 设置自动更新与自修复 - [待开发]"
    echo -e "0. 退出脚本"
    echo -e "${GREEN}====================================${NC}"
    read -p "请输入选项 [0-5]: " choice
}

# 5. 逻辑分发
while true; do
    show_menu
    case $choice in
        1)
            # 调用我们上一拍写好的脚本
            bash ${SCRIPT_PATH}/install_kernel.sh
            read -n 1 -s -r -p "按任意键返回菜单..."
            ;;
        0)
            echo "退出脚本。"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请重新选择${NC}"
            sleep 1
            ;;
    esac
done
