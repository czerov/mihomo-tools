#!/bin/bash
# install.sh - v1.0.8 智能指令集兼容修复版

MIHOMO_DIR="/etc/mihomo"
SCRIPT_DIR="${MIHOMO_DIR}/scripts"
MANAGER_DIR="${MIHOMO_DIR}/manager"
UI_DIR="${MIHOMO_DIR}/ui"
ENV_FILE="${MIHOMO_DIR}/.env"
SCRIPT_ROOT=$(cd "$(dirname "$0")"; pwd)

if [ "$(id -u)" != "0" ]; then echo "❌ 必须使用 Root 权限"; exit 1; fi

echo "📦 1. 准备环境与网络依赖检测..."
apt update
apt install -y curl wget tar gzip unzip python3 python3-pip python3-flask python3-yaml iptables dnsutils iproute2

# 停止旧服务
systemctl stop mihomo >/dev/null 2>&1
systemctl stop mihomo-manager >/dev/null 2>&1
rm -f /usr/bin/mihomo /usr/bin/mihomo-core

echo "📂 2. 部署文件..."
mkdir -p "${MIHOMO_DIR}" "${SCRIPT_DIR}" "${MANAGER_DIR}" "${UI_DIR}" "${MIHOMO_DIR}/templates"
cp -rf "${SCRIPT_ROOT}/scripts/"* "${SCRIPT_DIR}/" && chmod +x "${SCRIPT_DIR}"/*.sh
cp -rf "${SCRIPT_ROOT}/manager/"* "${MANAGER_DIR}/"
[ -d "${SCRIPT_ROOT}/templates" ] && cp -rf "${SCRIPT_ROOT}/templates/"* "${MIHOMO_DIR}/templates/"

echo "⬇️  3. 安装核心组件..."
# 安装菜单
if [ -f "${SCRIPT_ROOT}/main.sh" ]; then
    cp "${SCRIPT_ROOT}/main.sh" /usr/bin/mihomo && chmod +x /usr/bin/mihomo
    echo "✅ 管理菜单已安装"
fi

# --- 指令集检测与手动选择 ---
LATEST_VER=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep "tag_name" | cut -d '"' -f 4)
LATEST_VER=${LATEST_VER:-v1.19.0}
ARCH=$(uname -m)

if [ "$ARCH" == "x86_64" ]; then
    if grep -q "avx2" /proc/cpuinfo && grep -q "bmi2" /proc/cpuinfo; then
        echo "🚀 硬件检测：支持 v3 指令集"
        DEF_K=1
    else
        echo "🐢 硬件检测：不支持 v3 指令集"
        DEF_K=2
    fi
    echo "------------------------------------------------"
    echo "请选择内核版本 (PVE LXC 报错请务必选 2):"
    echo "1) 高性能版 (amd64-v3)"
    echo "2) 通用兼容版 (amd64) - 最推荐"
    echo "------------------------------------------------"
    read -p "请输入选项 [默认 $DEF_K]: " K_CHOICE
    K_CHOICE=${K_CHOICE:-$DEF_K}
    [ "$K_CHOICE" == "1" ] && PLAT="amd64-v3" || PLAT="amd64"
    URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_VER}/mihomo-linux-${PLAT}-${LATEST_VER}.gz"
else
    URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_VER}/mihomo-linux-arm64-${LATEST_VER}.gz"
fi

wget -O /tmp/mihomo.gz "$URL" && gzip -d -f /tmp/mihomo.gz && mv /tmp/mihomo /usr/bin/mihomo-core && chmod +x /usr/bin/mihomo-core

# 下载面板
rm -rf "${UI_DIR}/*"
wget -O /tmp/ui.zip "https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip" >/dev/null 2>&1 && unzip -q -o /tmp/ui.zip -d /tmp/ && cp -r /tmp/zashboard-gh-pages/* "${UI_DIR}/" && rm -rf /tmp/ui*

# === 4. 配置账户 (静默默认) ===
WEB_USER="admin"
WEB_SECRET="admin"
WEB_PORT="7838"

cat > "${ENV_FILE}" <<EOF
WEB_USER="${WEB_USER}"
WEB_SECRET="${WEB_SECRET}"
WEB_PORT="${WEB_PORT}"
CONFIG_MODE="airport"
EOF

# === 5. 注册并强制生成服务文件 ===
echo "⚙️ 5. 注册服务..."

# 创建管理面板服务
cat > /etc/systemd/system/mihomo-manager.service <<EOF
[Unit]
Description=Mihomo Web Manager
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=${MANAGER_DIR}
ExecStart=/usr/bin/python3 ${MANAGER_DIR}/app.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# 创建核心服务
cat > /etc/systemd/system/mihomo.service <<EOF
[Unit]
Description=Mihomo Core
After=network.target
[Service]
Type=simple
User=root
ExecStart=/bin/bash -c "/usr/bin/mihomo-core -d /etc/mihomo > /var/log/mihomo.log 2>&1"
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# === 6. 系统初始化与启动 ===
echo "🔧 6. 系统网络优化..."
systemctl daemon-reload
systemctl enable mihomo-manager mihomo
systemctl restart mihomo-manager mihomo

IP=$(hostname -I | awk '{print $1}')
echo "========================================"
echo "🎉 安装完成！面板地址: http://${IP}:${WEB_PORT}"
echo "========================================"
