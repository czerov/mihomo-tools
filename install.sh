#!/bin/bash

# ==========================================
# Mihomo 一键部署脚本
# ==========================================

# 1. 自动获取脚本所在目录
SCRIPT_ROOT=$(dirname "$(readlink -f "$0")")

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# 目标路径
INSTALL_DIR="/etc/mihomo-tools"
MIHOMO_DIR="/etc/mihomo"
SCRIPTS_DIR="${MIHOMO_DIR}/scripts"
BIN_PATH="/usr/bin/mihomo-cli"
UI_DIR="${MIHOMO_DIR}/ui"

echo -e "${GREEN}>>> 开始安装 Mihomo 管理工具...${NC}"
echo "资源目录锁定为: ${SCRIPT_ROOT}"

# 2. 安装系统依赖
echo -e "${YELLOW}[1/7] 安装系统基础依赖...${NC}"
apt update -qq
apt install -y git curl tar gzip nano cron ca-certificates iptables unzip > /dev/null 2>&1
echo "✅ 依赖安装完成。"

# 3. 部署/更新 脚本文件
echo -e "${YELLOW}[2/7] 部署脚本文件...${NC}"
mkdir -p "${SCRIPTS_DIR}"
mkdir -p "${MIHOMO_DIR}/data"
mkdir -p "${UI_DIR}"

cp -rf "${SCRIPT_ROOT}/scripts/"* "${SCRIPTS_DIR}/"
cp -f "${SCRIPT_ROOT}/main.sh" "${BIN_PATH}"

chmod +x "${BIN_PATH}"
chmod +x "${SCRIPTS_DIR}"/*.sh

echo "✅ 脚本已部署。"

# 3.1 修复 LXC 日志缺失问题 (兼容模式 - 修复报错)
echo -e "${YELLOW}[3/7] 优化系统日志 (Fix Journald)...${NC}"
# 1. 手动创建目录
mkdir -p /var/log/journal

# 2. 修改配置文件强制开启 (比 systemd-tmpfiles 更稳)
if ! grep -q "^Storage=persistent" /etc/systemd/journald.conf; then
    # 先注释掉已有的 Storage 设置 (防止冲突)
    sed -i 's/^Storage=/#Storage=/' /etc/systemd/journald.conf
    # 添加强制持久化
    echo "Storage=persistent" >> /etc/systemd/journald.conf
fi

# 3. 尝试重启服务 (如果不成功则忽略，重启容器后会自动生效)
systemctl restart systemd-journald >/dev/null 2>&1 || echo -e "ℹ️  日志配置生效中 (将在容器重启后完全就绪)"
echo "✅ 日志配置已完成。"

# 4. 生成默认配置 (.env)
echo -e "${YELLOW}[4/7] 初始化环境配置...${NC}"
cat > "${MIHOMO_DIR}/.env" <<EOF
MIHOMO_PATH="/etc/mihomo"
DATA_PATH="/etc/mihomo/data"
SCRIPT_PATH="/etc/mihomo/scripts"
GH_PROXY="https://gh-proxy.com/"
SUB_URL=""
EOF
echo "✅ 配置文件 .env 已生成。"

# 5. 初始化网关网络
echo -e "${YELLOW}[5/7] 初始化网关网络环境...${NC}"
bash "${SCRIPTS_DIR}/gateway_init.sh"

# 6. 下载资源 (Geo + 内核 + UI)
echo -e "${YELLOW}[6/7] 下载核心组件...${NC}"

echo "--> [1/3] 更新 GeoIP/GeoSite..."
bash "${SCRIPTS_DIR}/update_geo.sh" > /dev/null

echo "--> [2/3] 安装 Mihomo 内核..."
bash "${SCRIPTS_DIR}/install_kernel.sh" "auto"

echo "--> [3/3] 下载 Web 面板 (Zashboard)..."
UI_URL="https://gh-proxy.com/https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip"

curl -L -o /tmp/ui.zip "$UI_URL"
if [ $? -eq 0 ]; then
    rm -rf "${UI_DIR:?}"/*
    unzip -o -q /tmp/ui.zip -d /tmp/ui_extract
    cp -rf /tmp/ui_extract/*/* "${UI_DIR}/"
    rm -rf /tmp/ui.zip /tmp/ui_extract
    echo "✅ Zashboard 面板已安装到 ${UI_DIR}"
else
    echo "❌ 面板下载失败，请检查网络或稍后重试。"
fi

# 7. 注册 Systemd 服务
echo -e "${YELLOW}[7/7] 注册系统服务...${NC}"
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
echo "✅ 服务已注册。"

echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}   Mihomo 全自动部署完成！ ${NC}"
echo -e "${GREEN}=============================================${NC}"
echo -e "下一步操作："
echo -e "1. 输入 ${YELLOW}mihomo-cli${NC} 打开菜单"
echo -e "2. 选择 [3] 配置与订阅 -> 填入你的机场链接"
echo -e "3. 选择 [2] 管理服务 -> 启动服务"
echo -e "4. 访问面板: http://<IP>:9090/ui"
echo -e "============================================="
