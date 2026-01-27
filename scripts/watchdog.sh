#!/bin/bash

# 1. 导入环境
if [ -f "/etc/mihomo/.env" ]; then source /etc/mihomo/.env; else exit 1; fi

# 检测目标 (建议用国内访问畅通的地址，或者你代理能通的地址)
TEST_URL="https://www.google.com/generate_204"

check_and_fix() {
    # A. 进程守护：如果进程没了
    if ! systemctl is-active --quiet mihomo; then
        echo "$(date): 进程丢失，正在启动..." >> ${MIHOMO_PATH}/watchdog.log
        systemctl start mihomo
        
        # --- 埋点：发送进程重启通知 ---
        bash ${SCRIPT_PATH}/notify.sh "Mihomo 警报" "检测到进程异常退出，已尝试自动重启服务。"
        return
    fi

    # B. 网络守护：如果连不上网了
    # 使用 --max-time 10 防止卡死
    curl -s --head --request GET "$TEST_URL" --max-time 10 > /dev/null
    
    if [ $? -ne 0 ]; then
        echo "$(date): 网络连接检测失败，尝试重启..." >> ${MIHOMO_PATH}/watchdog.log
        systemctl restart mihomo
        
        # --- 埋点：发送网络重启通知 ---
        bash ${SCRIPT_PATH}/notify.sh "Mihomo 警报" "网络连接检测失败，已执行服务重启以尝试修复连接。"
    fi
}

check_and_fix
