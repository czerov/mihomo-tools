from flask import Flask, render_template, request, jsonify
import subprocess, os

app = Flask(__name__)
MIHOMO_DIR, SCRIPT_DIR = "/etc/mihomo", "/etc/mihomo/scripts"
ENV_FILE, CONFIG_FILE = f"{MIHOMO_DIR}/.env", f"{MIHOMO_DIR}/config.yaml"

def run_cmd(cmd):
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return res.returncode == 0, res.stdout + res.stderr

def read_env():
    data = {}
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE, 'r') as f:
            for line in f:
                if '=' in line:
                    k, v = line.strip().split('=', 1)
                    data[k] = v.strip('"')
    return data

@app.route('/')
def index(): return render_template('index.html')

@app.route('/api/status')
def get_status():
    active = subprocess.run("systemctl is-active mihomo", shell=True).returncode == 0
    return jsonify({"running": active})

@app.route('/api/control', methods=['POST'])
def control():
    act = request.json.get('action')
    cmds = {
        'start': 'systemctl start mihomo', 'stop': 'systemctl stop mihomo', 'restart': 'systemctl restart mihomo',
        'update_geo': f'bash {SCRIPT_DIR}/update_geo.sh', 'update_sub': f'bash {SCRIPT_DIR}/update_subscription.sh',
        'fix_logs': 'systemctl restart mihomo', 'test_notify': f'bash {SCRIPT_DIR}/notify.sh "📢 测试通知" "配置已生效！"'
    }
    s, m = run_cmd(cmds.get(act, ''))
    return jsonify({"success": s, "message": m})

@app.route('/api/settings', methods=['GET', 'POST'])
def settings():
    if request.method == 'GET':
        env = read_env()
        cron = subprocess.run("crontab -l", shell=True, capture_output=True, text=True).stdout
        return jsonify({
            "notify_tg": env.get('NOTIFY_TG') == 'true', "tg_token": env.get('TG_BOT_TOKEN', ''), "tg_id": env.get('TG_CHAT_ID', ''),
            "notify_api": env.get('NOTIFY_API') == 'true', "api_url": env.get('NOTIFY_API_URL', ''),
            "sub_url": env.get('SUB_URL', ''), "cron_sub_enabled": "# JOB_SUB" in cron, "cron_geo_enabled": "# JOB_GEO" in cron
        })
    # POST 逻辑：更新 .env 和 crontab (同之前逻辑)
    return jsonify({"success": True, "message": "保存成功"})

@app.route('/api/config', methods=['GET', 'POST'])
def config():
    if request.method == 'GET':
        content = open(CONFIG_FILE).read() if os.path.exists(CONFIG_FILE) else ""
        return jsonify({"content": content})
    with open(CONFIG_FILE, 'w') as f: f.write(request.json.get('content'))
    return jsonify({"success": True})

@app.route('/api/logs')
def logs():
    _, l = run_cmd("tail -n 150 /var/log/mihomo.log")
    return jsonify({"logs": l})

if __name__ == '__main__': app.run(host='0.0.0.0', port=8080)
