#!/bin/bash
# install.sh - Mihomo 一键安装脚本

MIHOMO_DIR="/etc/mihomo"
SCRIPT_DIR="${MIHOMO_DIR}/scripts"
MANAGER_DIR="${MIHOMO_DIR}/manager"

SCRIPT_ROOT=$(cd "$(dirname "$0")"; pwd)

# 检查 Root
if [ "$(id -u)" != "0" ]; then
    echo "请使用 root 权限运行此脚本。"
    exit 1
fi

# 1. 安装依赖
echo "📦 安装系统依赖..."
# 【新增】python3-yaml 用于后续的多机场合并脚本
apt update
apt install -y curl wget tar gzip unzip python3 python3-pip python3-flask python3-yaml

# 2. 停止旧服务
if systemctl is-active --quiet mihomo; then
    systemctl stop mihomo
fi

# 3. 创建目录结构
echo "📂 创建目录..."
mkdir -p "${MIHOMO_DIR}"
mkdir -p "${SCRIPT_DIR}"
mkdir -p "${MANAGER_DIR}"
mkdir -p "${MIHOMO_DIR}/templates"
mkdir -p "${MIHOMO_DIR}/providers" # 【新增】存放本地聚合后的节点文件

# 4. 下载/复制文件
echo "📥 安装脚本和核心文件..."
cp -rf "${SCRIPT_ROOT}/scripts/"* "${SCRIPT_DIR}/"
chmod +x "${SCRIPT_DIR}"/*.sh

# 安装 Web 管理器
echo "📥 安装 Web 管理器..."
cp -rf "${SCRIPT_ROOT}/manager/"* "${MANAGER_DIR}/"

# 安装预置模板
# ----------------------------------------------------------------
if [ -d "${SCRIPT_ROOT}/templates" ]; then
    echo "📄 安装配置模板..."
    cp -rf "${SCRIPT_ROOT}/templates/"* "${MIHOMO_DIR}/templates/"
else
    echo "⚠️ 警告：未找到 templates 文件夹，模板模式可能无法使用！"
fi
# ----------------------------------------------------------------

# 5. 安装主程序 CLI
if [ ! -f "${SCRIPT_ROOT}/main.sh" ]; then
    echo "❌ 错误：找不到 main.sh，无法安装 CLI。"
else
    cp "${SCRIPT_ROOT}/main.sh" /usr/bin/mihomo-cli
    chmod +x /usr/bin/mihomo-cli
    echo "✅ CLI 工具已安装: 输入 mihomo-cli 即可使用"
fi

# 6. 配置 Systemd 服务
echo "⚙️ 配置 Systemd 服务..."
cat > /etc/systemd/system/mihomo.service <<EOF
[Unit]
Description=Mihomo Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/mihomo
ExecStart=/etc/mihomo/manager/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mihomo
systemctl start mihomo

echo "🎉 安装完成！Web 面板已启动。"
echo "🌍 访问地址: http://$(hostname -I | awk '{print $1}'):7838"
