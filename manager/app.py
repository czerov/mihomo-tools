from flask import Flask, render_template, request, jsonify
import subprocess
import os
import shutil
import tempfile

app = Flask(__name__)

MIHOMO_DIR = "/etc/mihomo"
SCRIPT_DIR = "/etc/mihomo/scripts"
ENV_FILE = f"{MIHOMO_DIR}/.env"
CONFIG_FILE = f"{MIHOMO_DIR}/config.yaml"

# --- 核心工具函数 ---

def run_cmd(cmd):
    """执行 Shell 命令并返回结果"""
    try:
        # 使用 shell=True 允许执行 bash 脚本和复合命令
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return result.returncode == 0, result.stdout + result.stderr
    except Exception as e:
        return False, str(e)

def read_env():
    """读取 .env 文件，返回字典"""
    env_data = {}
    if os.path.exists(ENV_FILE):
        try:
            with open(ENV_FILE, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    # 跳过注释和空行
                    if not line or line.startswith('#'):
                        continue
                    if '=' in line:
                        key, value = line.split('=', 1)
                        # 去除 key 周围空格，去除 value 周围引号和空格
                        env_data[key.strip()] = value.strip().strip('"').strip("'")
        except Exception as e:
            print(f"Error reading .env: {e}")
    return env_data

def update_env_file(updates):
    """
    [核心优化] 原子化更新 .env 文件
    1. 读取原文件保留注释
    2. 写入临时文件
    3. 备份原文件
    4. 移动临时文件覆盖 (Atomic Move)
    """
    lines = []
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    
    new_lines = []
    updated_keys = set()
    
    # 1. 遍历旧行，更新已知 Key
    for line in lines:
        stripped = line.strip()
        # 保留空行和注释
        if not stripped or stripped.startswith('#'):
            new_lines.append(line)
            continue
            
        if '=' in line:
            key = line.split('=', 1)[0].strip()
            if key in updates:
                # 写入新值：强制双引号包裹，并转义值中的双引号
                safe_val = str(updates[key]).replace('"', '\\"')
                new_lines.append(f'{key}="{safe_val}"\n')
                updated_keys.add(key)
            else:
                # 未修改的 key 原样保留
                new_lines.append(line)
        else:
            new_lines.append(line)
            
    # 2. 追加原文件中不存在的新 Key
    for k, v in updates.items():
        if k not in updated_keys:
            safe_val = str(v).replace('"', '\\"')
            new_lines.append(f'{k}="{safe_val}"\n')
    
    # 3. 原子写入流程
    temp_path = None
    try:
        # 创建临时文件 (在该目录下创建，确保跨文件系统移动也是原子的)
        fd, temp_path = tempfile.mkstemp(dir=os.path.dirname(ENV_FILE), text=True)
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            f.writelines(new_lines)
            
        # 赋予读写权限 (防止 root 创建后其他用户读不了)
        os.chmod(temp_path, 0o644)

        # 备份 (如果原文件存在)
        if os.path.exists(ENV_FILE):
            shutil.copy2(ENV_FILE, f"{ENV_FILE}.bak")
            
        # 覆盖 (Atomic Replace)
        shutil.move(temp_path, ENV_FILE)
        return True, "配置已保存 (已自动备份)"
    except Exception as e:
        # 清理垃圾
        if temp_path and os.path.exists(temp_path):
            os.remove(temp_path)
        return False, f"保存失败: {str(e)}"

def update_cron(job_id, schedule, command, enabled):
    """Crontab 管理函数"""
    try:
        res = subprocess.run("crontab -l", shell=True, capture_output=True, text=True)
        # 如果当前没有 crontab，stdout 可能为空，这里做个容错
        current_cron = res.stdout.strip().split('\n') if res.stdout else []
        
        new_cron = []
        # 过滤掉包含 job_id 的旧任务
        for line in current_cron:
            if job_id not in line and line.strip() != "":
                new_cron.append(line)
                
        if enabled:
            # 添加新任务
            new_cron.append(f"{schedule} {command} {job_id}")
            
        # 写入新的 Crontab (一定要加换行符)
        cron_str = "\n".join(new_cron) + "\n"
        # 使用 input 参数传入 stdin
        subprocess.run("crontab -", shell=True, input=cron_str, text=True)
    except Exception as e:
        print(f"Cron Error: {e}")

# --- 辅助函数 ---
def is_true(val):
    if isinstance(val, bool):
        return val
    return str(val).lower() == 'true'

# --- 路由定义 ---

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/status')
def get_status():
    service_active = subprocess.run("systemctl is-active mihomo", shell=True).returncode == 0
    return jsonify({"running": service_active})

@app.route('/api/control', methods=['POST'])
def control_service():
    action = request.json.get('action')
    
    cmds = {
        'start': 'systemctl start mihomo',
        'stop': 'systemctl stop mihomo',
        'restart': 'systemctl restart mihomo',
        'update_geo': f'bash {SCRIPT_DIR}/update_geo.sh',
        'update_sub': f'bash {SCRIPT_DIR}/update_subscription.sh',
        'net_init': f'bash {SCRIPT_DIR}/gateway_init.sh',
        'fix_logs': 'systemctl restart mihomo',
        'test_notify': f'bash {SCRIPT_DIR}/notify.sh "🔔 通知测试" "恭喜！如果你收到这条消息，说明通知配置正确。"'
    }
    
    if action in cmds:
        success, msg = run_cmd(cmds[action])
        return jsonify({"success": success, "message": msg})
    return jsonify({"success": False, "message": "未知指令"})

@app.route('/api/config', methods=['GET', 'POST'])
def handle_config():
    if request.method == 'GET':
        content = ""
        if os.path.exists(CONFIG_FILE):
            try:
                with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                    content = f.read()
            except:
                content = "# 读取配置文件失败"
        env = read_env()
        return jsonify({"content": content, "sub_url": env.get('SUB_URL', '')})
        
    if request.method == 'POST':
        content = request.json.get('content')
        try:
            # 写入 Config.yaml 也可以考虑加个临时文件机制，但这里先保持简单
            with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
                f.write(content)
            return jsonify({"success": True, "message": "配置文件已保存"})
        except Exception as e:
            return jsonify({"success": False, "message": str(e)})

@app.route('/api/settings', methods=['GET', 'POST'])
def handle_settings():
    if request.method == 'GET':
        env = read_env()
        return jsonify({
            # 通知
            "notify_tg": env.get('NOTIFY_TG') == 'true',
            "tg_token": env.get('TG_BOT_TOKEN', ''),
            "tg_id": env.get('TG_CHAT_ID', ''),
            "notify_api": env.get('NOTIFY_API') == 'true',
            "api_url": env.get('NOTIFY_API_URL', ''),
            # 订阅 & 任务
            "sub_url": env.get('SUB_URL', ''),
            "cron_sub_enabled": env.get('CRON_SUB_ENABLED') == 'true',
            "cron_sub_sched": env.get('CRON_SUB_SCHED', '0 5 * * *'), 
            "cron_geo_enabled": env.get('CRON_GEO_ENABLED') == 'true',
            "cron_geo_sched": env.get('CRON_GEO_SCHED', '0 4 * * *')
        })

    if request.method == 'POST':
        d = request.json
        
        # 1. 准备更新数据
        updates = {
            "NOTIFY_TG": str(is_true(d.get('notify_tg'))).lower(),
            "TG_BOT_TOKEN": d.get('tg_token', ''),
            "TG_CHAT_ID": d.get('tg_id', ''),
            "NOTIFY_API": str(is_true(d.get('notify_api'))).lower(),
            "NOTIFY_API_URL": d.get('api_url', ''),
            "SUB_URL": d.get('sub_url', ''),
            # 自动化任务配置
            "CRON_SUB_ENABLED": str(is_true(d.get('cron_sub_enabled'))).lower(),
            "CRON_SUB_SCHED": d.get('cron_sub_sched', '0 5 * * *'),
            "CRON_GEO_ENABLED": str(is_true(d.get('cron_geo_enabled'))).lower(),
            "CRON_GEO_SCHED": d.get('cron_geo_sched', '0 4 * * *')
        }
        
        # 2. 调用原子更新函数
        success, msg = update_env_file(updates)
        if not success:
            return jsonify({"success": False, "message": msg})

        # 3. 应用 Crontab (只有保存成功才应用)
        update_cron(
            "# JOB_SUB", 
            updates['CRON_SUB_SCHED'], 
            f"bash {SCRIPT_DIR}/update_subscription.sh >/dev/null 2>&1", 
            updates['CRON_SUB_ENABLED'] == 'true'
        )
        
        update_cron(
            "# JOB_GEO", 
            updates['CRON_GEO_SCHED'], 
            f"bash {SCRIPT_DIR}/update_geo.sh >/dev/null 2>&1", 
            updates['CRON_GEO_ENABLED'] == 'true'
        )

        return jsonify({"success": True, "message": msg})

@app.route('/api/logs')
def get_logs():
    LOG_FILE = "/var/log/mihomo.log"
    if not os.path.exists(LOG_FILE):
        return jsonify({"logs": "⚠️ 日志文件尚未生成..."})
    try:
        # 使用 run_cmd 避免权限问题 (虽然这里读的是 666 权限的文件)
        success, logs = run_cmd(f"tail -n 100 {LOG_FILE}")
        return jsonify({"logs": logs if logs else "日志为空"})
    except:
        return jsonify({"logs": "读取失败"})

if __name__ == '__main__':
    # 监听所有 IP，端口 8080
    app.run(host='0.0.0.0', port=8080)
