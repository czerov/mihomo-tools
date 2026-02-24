#!/bin/bash
# install.sh - v1.0.7 智能指令集兼容版

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

# --- 核心修改：指令集自动检测 ---
LATEST_VER=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep "tag_name" | cut -d '"' -f 4)
LATEST_VER=${LATEST_VER:-v1.18.1}
ARCH=$(uname -m)

case $ARCH in
    x86_64)
        # 检测是否支持 AVX2 和 BMI2 (v3 标准)
        if grep -q "avx2" /proc/cpuinfo && grep -q "bmi2" /proc/cpuinfo; then
            echo "🚀 检测到 CPU 支持 v3 指令集 (AVX2)，正在下载高性能版..."
            URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_VER}/mihomo-linux-amd64-v3-${LATEST_VER}.gz"
        else
            echo "🐢 CPU 不支持 v3 指令集，正在下载通用兼容版 (amd64)..."
            URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_VER}/mihomo-linux-amd64-${LATEST_VER}.gz"
        fi
        ;;
    aarch64)
        URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_VER}/mihomo-linux-arm64-${LATEST_VER}.gz"
        ;;
    *) echo "❌ 不支持的架构"; exit 1 ;;
esac

wget -O /tmp/mihomo.gz "$URL" >/dev/null 2>&1 && gzip -d -f /tmp/mihomo.gz && mv /tmp/mihomo /usr/bin/mihomo-core && chmod +x /usr/bin/mihomo-core

# 下载面板
rm -rf "${UI_DIR}/*"
wget -O /tmp/ui.zip "https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip" >/dev/null 2>&1 && unzip -q -o /tmp/ui.zip -d /tmp/ && cp -r /tmp/zashboard-gh-pages/* "${UI_DIR}/" && rm -rf /tmp/ui*

# === 配置向导 ===
echo "🔑 4. 配置账户..."
if [ -f "${ENV_FILE}" ]; then
    eval $(grep -E '^[A-Z_]+=' "${ENV_FILE}" | sed 's/^/export /') >/dev/null 2>&1
    CUR_USER=${WEB_USER:-admin}
    CUR_PORT=${WEB_PORT:-7838}
    echo "检测到配置: 用户=$CUR_USER, 端口=$CUR_PORT"
    read -p "是否保留现有配置？(Y/n) [默认: Y]: " KEEP
    KEEP=${KEEP:-Y}
else
    KEEP="n"
fi

if [[ "$KEEP" =~ ^[Nn]$ ]]; then
    read -p "用户名 [admin]: " IN_USER; WEB_USER=${IN_USER:-admin}
    read -p "密码 [admin]: " IN_PASS; WEB_SECRET=${IN_PASS:-admin}
    read -p "端口 [7838]: " IN_PORT; WEB_PORT=${IN_PORT:-7838}
else
    WEB_USER=${WEB_USER:-admin}
    WEB_SECRET=${WEB_SECRET:-admin}
    WEB_PORT=${WEB_PORT:-7838}
fi

# 写入配置
cat > "${ENV_FILE}" <<EOF
WEB_USER="${WEB_USER}"
WEB_SECRET="${WEB_SECRET}"
WEB_PORT="${WEB_PORT}"
CONFIG_MODE="${CONFIG_MODE:-airport}"
SUB_URL_RAW="${SUB_URL_RAW:-}"
SUB_URL_AIRPORT="${SUB_URL_AIRPORT:-}"
LOCAL_CIDR="${LOCAL_CIDR:-}"
NOTIFY_API="${NOTIFY_API:-false}"
NOTIFY_API_URL="${NOTIFY_API_URL:-}"
CRON_SUB_ENABLED="${CRON_SUB_ENABLED:-false}"
CRON_SUB_SCHED="${CRON_SUB_SCHED:-0 5 * * *}"
CRON_GEO_ENABLED="${CRON_GEO_ENABLED:-false}"
CRON_GEO_SCHED="${CRON_GEO_SCHED:-0 4 * * *}"
EOF

# === 注册服务 ===
echo "⚙️ 5. 注册服务..."
cat > /etc/systemd/system/mihomo-manager.service <<EOF
[Unit]
Description=Mihomo Web Manager
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /etc/mihomo/manager/app.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF

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

cat > /etc/systemd/system/force-ip-forward.service <<EOF
[Unit]
Description=Force Enable IPv4 Forwarding for Mihomo
After=network.target
[Service]
Type=oneshot
ExecStart=/sbin/sysctl -w net.ipv4.ip_forward=1
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF

# === 系统初始化 ===
echo "🔧 6. 系统网络优化..."
systemctl daemon-reload
systemctl enable mihomo-manager mihomo force-ip-forward

if [ -f "${SCRIPT_DIR}/gateway_init.sh" ]; then
    bash "${SCRIPT_DIR}/gateway_init.sh" || echo "⚠️ 警告：网络初始化遇到非致命错误。"
fi

systemctl restart mihomo-manager mihomo force-ip-forward

IP=$(hostname -I | awk '{print $1}')
echo "========================================"
echo "🎉 安装完成！面板地址: http://${IP}:${WEB_PORT}"
echo "========================================"
