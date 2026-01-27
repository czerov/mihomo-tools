from flask import Flask, render_template, request, jsonify
import subprocess
import os

app = Flask(__name__)

# 配置路径
MIHOMO_DIR = "/etc/mihomo"
SCRIPT_DIR = "/etc/mihomo/scripts"
CONFIG_FILE = f"{MIHOMO_DIR}/config.yaml"

def run_script(script_name):
    """执行 Shell 脚本"""
    try:
        cmd = f"bash {SCRIPT_DIR}/{script_name}"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return result.returncode == 0, result.stdout + result.stderr
    except Exception as e:
        return False, str(e)

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/status')
def get_status():
    """获取服务状态"""
    service_active = subprocess.run("systemctl is-active mihomo", shell=True).returncode == 0
    return jsonify({"running": service_active})

@app.route('/api/config', methods=['GET', 'POST'])
def handle_config():
    """读取或保存配置文件"""
    if request.method == 'GET':
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                return jsonify({"content": f.read()})
        return jsonify({"content": ""})
    
    if request.method == 'POST':
        content = request.json.get('content')
        try:
            with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
                f.write(content)
            return jsonify({"success": True})
        except Exception as e:
            return jsonify({"success": False, "message": str(e)})

@app.route('/api/action', methods=['POST'])
def perform_action():
    """执行操作：重启、更新等"""
    action = request.json.get('action')
    success = False
    message = ""

    if action == 'start':
        subprocess.run("systemctl start mihomo", shell=True)
        success = True
        message = "服务已启动"
    elif action == 'stop':
        subprocess.run("systemctl stop mihomo", shell=True)
        success = True
        message = "服务已停止"
    elif action == 'restart':
        subprocess.run("systemctl restart mihomo", shell=True)
        success = True
        message = "服务已重启"
    elif action == 'update_geo':
        success, message = run_script("update_geo.sh")
    elif action == 'update_kernel':
        # 强制自动模式
        success, message = run_script("install_kernel.sh auto")
    
    return jsonify({"success": success, "message": message})

@app.route('/api/subscribe', methods=['POST'])
def update_sub():
    """更新订阅"""
    url = request.json.get('url')
    if not url:
        return jsonify({"success": False, "message": "链接为空"})
    
    # 这里我们简单覆写 config.yaml 的 providers 部分，或者你可以调用专门的脚本
    # 为了简单演示，这里我们假设你有一个专门处理订阅的脚本
    # 实际上，建议直接在 Config 编辑器里改，或者写一个复杂的解析逻辑
    # 这里暂时留空，建议用户直接用编辑器修改，或者后续我帮你写一个专门的 py 脚本处理 yaml
    return jsonify({"success": True, "message": "请直接在配置文件编辑器中修改 proxy-providers"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
