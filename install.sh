#!/bin/bash

# ==========================================
# Mihomo 一键部署脚本 (All-in-One)
# ==========================================

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# 路径定义
INSTALL_DIR="/etc/mihomo-tools"
MIHOMO_DIR="/etc/mihomo"
SCRIPTS_DIR="${MIHOMO_DIR}/scripts"
BIN_PATH="/usr/bin/mihomo-cli"

echo -e "${GREEN}>>> 开始安装 Mihomo 管理工具...${NC}"

# 1. 安装系统依赖 (防止新 LXC 缺组件)
echo -e "${YELLOW}[1/6] 安装系统基础依赖...${NC}"
apt update -qq
apt install -y git curl tar gzip nano cron ca-certificates > /dev/null 2>&1
echo "✅ 依赖安装完成。"

# 2. 部署/更新 脚本文件
echo -e "${YELLOW}[2/6] 部署脚本文件...${NC}"
# 如果是初次运行（通常是 git clone 下来后运行），文件就在当前目录下
# 我们假设当前就在 /etc/mihomo-tools 下，或者用户手动 clone 的位置

mkdir -p "${SCRIPTS_DIR}"
mkdir -p "${MIHOMO_DIR}/data"

# 复制脚本 (假设 install.sh 和 scripts 目录同级)
# 使用 -r 递归复制，-f 强制覆盖
cp -rf scripts/* "${SCRIPTS_DIR}/"
cp -f main.sh "${BIN_PATH}"

# 赋予权限
chmod +x "${BIN_PATH}"
chmod +x "${SCRIPTS_DIR}"/*.sh

echo "✅ 脚本已部署到 ${MIHOMO_DIR}"

# 3. 生成默认配置 (.env)
echo -e "${YELLOW}[3/6] 初始化环境配置...${NC}"
cat > "${MIHOMO_DIR}/.env" <<EOF
MIHOMO_PATH="/etc/mihomo"
DATA_PATH="/etc/mihomo/data"
SCRIPT_PATH="/etc/mihomo/scripts"
GH_PROXY="https://gh-proxy.com/"
SUB_URL=""
EOF
echo "✅ 配置文件 .env 已生成。"

# 4. 初始化网关网络 (TUN 前置)
echo -e "${YELLOW}[4/6] 初始化网关网络环境 (Forward/NAT)...${NC}"
# 直接调用模块脚本
bash "${SCRIPTS_DIR}/gateway_init.sh"

# 5. 下载资源 (Geo + 内核)
echo -e "${YELLOW}[5/6] 下载核心组件...${NC}"

# 5.1 更新 Geo 数据库
echo "--> 正在下载 GeoIP/GeoSite..."
bash "${SCRIPTS_DIR}/update_geo.sh" > /dev/null

# 5.2 安装 Mihomo 内核 (默认安装最新版)
echo "--> 正在下载 Mihomo 内核..."
# 注意：你需要确保 install_kernel.sh 支持无交互运行，或者这里简单调用
# 如果 install_kernel.sh 里有 read 交互，这里会被卡住。
# 建议修改 install_kernel.sh 让它支持参数，或者这里直接写简单的下载逻辑
bash "${SCRIPTS_DIR}/install_kernel.sh" "latest" 

# 6. 注册 Systemd 服务
echo -e "${YELLOW}[6/6] 注册系统服务...${NC}"
# 调用 service_ctl.sh 里的生成逻辑，或者直接在这里写
cat > /etc/systemd/system/mihomo.service <<EOF
[Unit]
Description=Mihomo Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${MIHOMO_DIR}
ExecStartPre=/bin/bash ${SCRIPTS_DIR}/gateway_init.sh
ExecStart=${MIHOMO_DIR}/mihomo -d ${MIHOMO_DIR}
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
echo "✅ 服务已注册 (未启动)。"

echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}   Mihomo 全自动部署完成！ ${NC}"
echo -e "${GREEN}=============================================${NC}"
echo -e "下一步操作："
echo -e "1. 输入 ${YELLOW}mihomo-cli${NC} 打开菜单"
echo -e "2. 选择 [3] 配置与订阅 -> 填入你的机场链接"
echo -e "3. 选择 [2] 管理服务 -> 启动服务"
echo -e "============================================="
