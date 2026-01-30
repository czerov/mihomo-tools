#!/bin/bash
# update_subscription.sh - 订阅更新 (修复多机场分隔符问题)

MIHOMO_DIR="/etc/mihomo"
ENV_FILE="${MIHOMO_DIR}/.env"
CONFIG_FILE="${MIHOMO_DIR}/config.yaml"
TEMPLATE_FILE="${MIHOMO_DIR}/templates/default.yaml"
BACKUP_DIR="${MIHOMO_DIR}/backup"
NOTIFY_SCRIPT="${MIHOMO_DIR}/scripts/notify.sh"
TEMP_NEW="/tmp/config_generated.yaml"

# 1. 加载环境变量
if [ -f "$ENV_FILE" ]; then source "$ENV_FILE"; fi

mkdir -p "$BACKUP_DIR"
mkdir -p "${MIHOMO_DIR}/providers"

# --------------------------------------------------------
# 模式 A: Raw 直连模式
# --------------------------------------------------------
if [ "$CONFIG_MODE" == "raw" ]; then
    if [ -z "$SUB_URL_RAW" ]; then
        echo "❌ [Raw模式] 未配置订阅链接，跳过。"
        exit 0
    fi
    
    echo "⬇️  [Raw模式] 正在下载完整配置..."
    wget --no-check-certificate -O "$TEMP_NEW" "$SUB_URL_RAW" >/dev/null 2>&1
    
    if [ $? -ne 0 ] || [ ! -s "$TEMP_NEW" ]; then
        echo "❌ 下载失败。"
        bash "$NOTIFY_SCRIPT" "❌ 更新失败" "无法下载 Raw 配置文件。"
        rm -f "$TEMP_NEW"
        exit 1
    fi

# --------------------------------------------------------
# 模式 B: Airport 机场模式 (注入模板)
# --------------------------------------------------------
else
    if [ ! -f "$TEMPLATE_FILE" ]; then
        echo "❌ 模板文件缺失: $TEMPLATE_FILE"
        exit 1
    fi
    
    if [ -z "$SUB_URL_AIRPORT" ]; then
        echo "❌ [Airport模式] 未配置机场链接。"
        exit 0
    fi
    
    echo "🔨 [Airport模式] 正在生成配置文件..."
    export SUB_URL_AIRPORT
    
    # 使用 Python 动态注入 Proxy Providers
    python3 -c "
import sys, yaml, os

template_path = '$TEMPLATE_FILE'
output_path = '$TEMP_NEW'

# 【核心修复】将前端传来的管道符 '|' 和转义换行符都统一替换为标准换行符
urls_raw = os.environ.get('SUB_URL_AIRPORT', '').replace('|', '\n').replace('\\\\n', '\\n')

def load_yaml(path):
    if not os.path.exists(path): return {}
    with open(path, 'r', encoding='utf-8') as f:
        return yaml.safe_load(f) or {}

try:
    config = load_yaml(template_path)
    
    # 按换行符分割，生成列表
    url_list = [line.strip() for line in urls_raw.split('\n') if line.strip()]
    
    if not url_list:
        print('Error: No valid URLs found')
        sys.exit(1)

    # 动态生成多个 Provider
    providers = {}
    
    for index, url in enumerate(url_list):
        # 生成 Airport_01, Airport_02 ...
        name = f'Airport_{index+1:02d}'
        providers[name] = {
            'type': 'http',
            'url': url,
            'interval': 86400,
            'path': f'./providers/airport_{index+1:02d}.yaml',
            'health-check': {
                'enable': True,
                'interval': 600,
                'url': 'https://www.gstatic.com/generate_204'
            }
        }
    
    # 覆盖模板中的 proxy-providers
    config['proxy-providers'] = providers
    
    with open(output_path, 'w', encoding='utf-8') as f:
        yaml.dump(config, f, allow_unicode=True, sort_keys=False)

except Exception as e:
    print(f'Error: {e}')
    sys.exit(1)
"
    
    if [ $? -ne 0 ]; then
        echo "❌ 生成配置失败。"
        bash "$NOTIFY_SCRIPT" "❌ 生成失败" "YAML 处理错误，请检查模板。"
        rm -f "$TEMP_NEW"
        exit 1
    fi
fi

# --------------------------------------------------------
# 通用步骤
# --------------------------------------------------------
if [ ! -s "$TEMP_NEW" ]; then
    rm -f "$TEMP_NEW"
    exit 1
fi

FILE_CHANGED=0
if [ -f "$CONFIG_FILE" ]; then
    if cmp -s "$TEMP_NEW" "$CONFIG_FILE"; then
        echo "✅ 配置无变更。"
        FILE_CHANGED=0
    else
        echo "⚠️  配置有变更。"
        FILE_CHANGED=1
    fi
else
    FILE_CHANGED=1
fi

if [ "$FILE_CHANGED" -eq 1 ]; then
    cp "$CONFIG_FILE" "${BACKUP_DIR}/config_$(date +%Y%m%d%H%M).yaml" 2>/dev/null
    mv "$TEMP_NEW" "$CONFIG_FILE"
    systemctl restart mihomo
    echo "🎉 更新完成并重启。"
    bash "$NOTIFY_SCRIPT" "♻️ 订阅更新成功" "模式: ${CONFIG_MODE:-airport}"
else
    rm -f "$TEMP_NEW"
fi
