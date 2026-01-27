#!/bin/bash

# 1. 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}正在初始化网关网络环境...${NC}"

# 2. 自动识别网卡名 (防止不是 eth0 的情况)
IFACE=$(ip route show default | awk '/default/ {print $5}' | head -n 1)
if [ -z "$IFACE" ]; then
    IFACE="eth0"
    echo -e "${RED}未检测到默认路由，强制设定出口网卡为: $IFACE (可能出错)${NC}"
else
    echo -e "检测到出口网卡: ${GREEN}$IFACE${NC}"
fi

# 3. 开启内核转发 (IP Forwarding)
echo "正在开启 IPv4 转发..."
sysctl -w net.ipv4.ip_forward=1 > /dev/null
# 写入配置文件永久生效
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-mihomo-gateway.conf

# 4. 关闭反向路径过滤 (RP_Filter) - 解决“有去无回”的关键
# 很多时候 Forward 即使 ACCEPT 了，因为路由不对称，内核也会丢包
echo "正在放宽内核路径过滤限制..."
for i in /proc/sys/net/ipv4/conf/*/rp_filter; do
    echo 0 > "$i"
done

# 5. 清理并重置防火墙规则
echo "正在重置 iptables 规则..."

# 5.1 暴力放行转发链 (Forward Chain)
# 无论之前是 DROP 还是 REJECT，插队到第一行强制 ACCEPT
iptables -P FORWARD ACCEPT
iptables -F FORWARD  # 清空旧规则
iptables -I FORWARD -j ACCEPT

# 5.2 设置 NAT 伪装 (Masquerade)
# 先删掉旧的防止重复
iptables -t nat -D POSTROUTING -o "$IFACE" -j MASQUERADE 2>/dev/null
# 添加新的
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE

echo -e "${GREEN}✅ 网络初始化完成！${NC}"
echo -e "当前状态："
echo -e "  - IP Forward: $(sysctl -n net.ipv4.ip_forward)"
echo -e "  - NAT Rule:   [已添加] -> $IFACE"
echo -e "  - Forward:    [ACCEPT]"
