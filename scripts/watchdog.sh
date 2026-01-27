#!/bin/bash

# 1. 导入基础环境
if [ -f "/etc/mihomo/.env" ]; then
    source /etc/mihomo/.env
else
    exit 1
fi

# 2. 定义检测目标 (建议用延迟低且稳定的地址)
# 如果你是国内环境，建议用 www.baidu.com 或 223.5.5.5
# 如果是访问外网环境，建议用 www.google.com 或 8.8.8.8
TEST_URL="https://www.google.com/generate_204"

# 3. 检查函数
check_and_fix() {
    # A. 检查进程存活
    if ! systemctl is-active --quiet mihomo; then
        echo "$(date): 服务未运行，正在启动..." >> ${MIHOMO_PATH}/watchdog.log
        systemctl start mihomo
        return
    fi

    # B. 检查网络连通性 (5秒超时)
    # 通过代理端口检查可能更准确，这里先检查全局
    curl -s --head --request GET "$TEST_URL" --max-time 5 > /dev/null
    
    if [ $? -ne 0 ]; then
        echo "$(date): 网络连接检测失败，尝试重启服务..." >> ${MIHOMO_PATH}/watchdog.log
        systemctl restart mihomo
        
        # 可选：如果这里接入了 notify.sh，可以发通知给你
        # bash ${SCRIPT_PATH}/notify.sh "检测到网络中断，Mihomo 已自动重启"
    fi
}

check_and_fix
