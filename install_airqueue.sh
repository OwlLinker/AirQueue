#!/bin/bash
# ═══════════════════════════════════════════════════════════
#  AirQueue（隔空随达）安装脚本 / Installer
#  用法 / Usage: bash install_airqueue.sh
# ═══════════════════════════════════════════════════════════

set -e

MSG_START="📦 AirQueue（隔空随达）安装开始 / Installation started..."
MSG_NO_PYTHON="❌ 找不到 Python 3，请先安装 / Python 3 not found. Install Python 3 first."
MSG_STEP1="📁 [1/3] 创建目录 / Creating directories..."
MSG_STEP2="🔐 [2/3] 检查权限 / Checking permissions..."
MSG_STEP3="🐍 [3/3] 安装服务 / Installing service..."
MSG_NO_QUEUE="❌ 未找到 iCloud 队列目录 / iCloud queue directory not found. 请先开启 iCloud Drive 并运行一次快捷指令 / Enable iCloud Drive and run the Shortcut once."
MSG_NO_LOAD="❌ 服务注册失败 / Failed to register service"
MSG_SUCCESS="✅ AirQueue（隔空随达）安装完成 / Installation complete!"
MSG_SOURCE="⚡ 请执行以下命令让终端命令立即生效 / Run this to activate the commands in the current terminal:"
MSG_PERM_CANCEL="❌ 用户取消权限设置，安装中止 / Permission setup cancelled. Installation aborted."
MSG_PERM_RETRY="⚠️ 权限尚未开启，请完成设置后按 Enter / Permission is not enabled yet. Complete the setup, then press Enter..."
CANCEL_LABEL="取消 / Cancel"
SETTINGS_LABEL="前往设置 / Open Settings"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  $MSG_START"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  👤 用户 / User: $(whoami)"
echo "  🏠 主目录 / Home: $HOME"

# 获取 python3 真实路径：优先用 realpath 解析 symlink
PYTHON_PATH=$(realpath "$(which python3)" 2>/dev/null)
# 如果 realpath 失败或文件不存在，退回 which python3
if [ -z "$PYTHON_PATH" ] || [ ! -f "$PYTHON_PATH" ]; then
    PYTHON_PATH=$(which python3 2>/dev/null)
fi
# 最终验证
if [ -z "$PYTHON_PATH" ] || [ ! -f "$PYTHON_PATH" ]; then
    echo "  $MSG_NO_PYTHON"; exit 1
fi
echo "  🐍 Python: $PYTHON_PATH"
echo ""

# ── 1. 创建目录 / 检查 iCloud 队列目录 ──────────────────
echo "$MSG_STEP1"
mkdir -p "$HOME/bin"
mkdir -p "$HOME/Library/LaunchAgents"

QUEUE_PATH="$HOME/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/AirQueue/pending"
if [ ! -d "$QUEUE_PATH" ]; then
    echo ""
    echo "  $MSG_NO_QUEUE"
    echo "  请确认 / Check:"
    echo "  1. iCloud Drive 已开启 / iCloud Drive is enabled"
    echo "  2. 快捷指令 App 已在 iPhone 上运行过一次（触发文件夹创建） / The Shortcut has run once on iPhone (to create the folder)"
    exit 1
fi
echo "   ✓ iCloud 队列目录已就绪 / iCloud queue directory is ready"
echo "   ✓ 其他目录就绪 / Other directories are ready"

# ── 2. 检测并引导完全磁盘访问权限 ────────────────────────
echo "$MSG_STEP2"

# 需要授权的两个程序：
#   - Terminal（运行安装脚本用）
#   - python3 真实路径（LaunchAgent 后台运行用）
TERMINAL_APP=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || echo "Terminal")

check_fda() {
    # ~/Library/Safari/ 是强制受 TCC 保护的路径，可靠检测 Terminal 是否有 FDA
    ls "$HOME/Library/Safari/" > /dev/null 2>&1
}

check_python_fda() {
    python3 -c "import os; os.listdir(os.path.expanduser('~/Library/Safari'))" > /dev/null 2>&1
}

guide_fda() {
    local target_name="$1"
    local target_path="$2"

    # 用变量拼接避免 heredoc 中文乱码
    local msg="需要为「${target_name}」开启完全磁盘访问权限 / Full Disk Access is required for ${target_name}.
"
    msg+="系统设置即将打开，请按以下步骤操作 / System Settings will open. Please:
"
    msg+="  1. 点击左下角「+」号 / Click the + button at the bottom left
"
    msg+="  2. 按 Command+Shift+G 输入路径 / Press Command+Shift+G and enter: ${target_path}
"
    msg+="  3. 点击「打开」，然后开启右侧开关 / Click Open, then enable the switch
"
    msg+="  4. 回到此终端按 Enter 继续 / Return to this terminal and press Enter"

    RESULT=$(osascript -e "tell application \"System Events\" to activate"                        -e "set btn to button returned of (display dialog \"${msg}\" with title \"AirQueue（隔空随达）权限 / Permissions\" buttons {\"${CANCEL_LABEL}\", \"${SETTINGS_LABEL}\"} default button \"${SETTINGS_LABEL}\" with icon caution)"                        -e "return btn" 2>/dev/null)

    if [ "$RESULT" != "$SETTINGS_LABEL" ]; then
        echo "$MSG_PERM_CANCEL"
        exit 1
    fi

    open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
}

# —— ① Terminal：可靠检测（Terminal 不是自身子进程）——
if check_fda; then
    echo "   ✓ Terminal 完全磁盘访问权限已就绪 / Full Disk Access is ready"
else
    echo "   ⚠️  需要为「$TERMINAL_APP」开启完全磁盘访问权限 / Full Disk Access is required for $TERMINAL_APP"
    guide_fda "$TERMINAL_APP" "/System/Applications/Utilities/Terminal.app"
    while true; do
        read -p "   完成后请按 [Enter] 继续 / Press [Enter] when complete..." </dev/tty
        if check_fda; then
            echo "   ✓ Terminal 权限验证通过 / Terminal permission verified"
            break
        else
            echo "   $MSG_PERM_RETRY"
        fi
    done
fi

# —— ② Python3：后台运行需要独立 FDA ——
if check_python_fda; then
    echo "   ✓ Python3 完全磁盘访问权限已就绪 / Full Disk Access is ready for Python 3"
else
    echo "   ⚠️  需要为 Python3 开启完全磁盘访问权限（后台服务独立运行时使用） / Full Disk Access is required for the background Python service"
    echo "      路径 / Path: $PYTHON_PATH"
    guide_fda "python3" "$PYTHON_PATH"
    while true; do
        read -p "   完成后请按 [Enter] 继续 / Press [Enter] when complete..." </dev/tty
        if check_python_fda; then
            echo "   ✓ Python3 权限验证通过 / Python 3 permission verified"
            break
        else
            echo "   $MSG_PERM_RETRY"
        fi
    done
fi
echo "   ✓ Python3 权限设置完成 / Python 3 permissions are ready"

# ── 3. 安装 watcher.py + LaunchAgent ─────────────────────
echo "$MSG_STEP3"

cat > "$HOME/bin/airqueue_watcher.py" << 'PYEOF'
#!/usr/bin/env python3
import json, time, subprocess, re, os
from pathlib import Path
from datetime import datetime

QUEUE_DIR        = Path.home() / "Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/AirQueue/pending"
LOG_FILE         = Path.home() / ".airqueue.log"
ERROR_COUNT_FILE = Path.home() / ".airqueue_errors.json"   # FIX: 持久化错误计数

def smart_sleep():
    try:
        boot_raw = subprocess.check_output(['sysctl', '-n', 'kern.boottime']).decode()
        boot_time = float(re.search(r'sec = (\d+)', boot_raw).group(1))
        if (time.time() - boot_time) < 300:
            log("系统刚启动，执行 30s 避峰延迟 / Startup cooldown: waiting 30s...")
            time.sleep(30)
    except Exception:
        pass

smart_sleep()
QUEUE_DIR.mkdir(parents=True, exist_ok=True)

MAX_ERRORS = 3

# ── FIX: 错误计数持久化，跨进程累计 ──────────────────────
def load_error_counts():
    try:
        return json.loads(ERROR_COUNT_FILE.read_text(encoding='utf-8'))
    except Exception:
        return {}

def save_error_counts(counts):
    try:
        ERROR_COUNT_FILE.write_text(json.dumps(counts), encoding='utf-8')
    except Exception:
        pass

error_counts = load_error_counts()

def log(msg):
    with open(LOG_FILE, "a") as f:
        f.write(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] {msg}\n")

def notify(title, body):
    subprocess.run(["osascript", "-e", f'display notification "{body}" with title "{title}"'])

def notify_error(title, body):
    notify(title, body)

def safe_filename(text):
    text = text.replace('\\n', ' ').replace('\\r', ' ').strip()
    has_chinese = bool(re.search(r'[\u4e00-\u9fff]', text))
    has_english = bool(re.search(r'[a-zA-Z]', text))
    if not has_chinese and has_english:
        name = ' '.join(re.findall(r'[a-zA-Z]+', text)[:20])
    else:
        cn_count = 0; i = 0
        while i < len(text) and cn_count < 20:
            if re.match(r'[\u4e00-\u9fff]', text[i]): cn_count += 1
            i += 1
        while i < len(text) and re.match(r'[a-zA-Z]', text[i]): i += 1
        name = text[:i].strip()
    name = re.sub(r'[/\\:*?"<>|\n\r\t]', '', name).strip(' .')
    return name or datetime.now().strftime("%Y%m%d%H%M%S")

def wait_for_icloud(f, timeout=30, binary=False):
    subprocess.run(["brctl", "download", str(f)], capture_output=True)
    for _ in range(timeout):
        try:
            if binary:
                with open(f, 'rb') as fp: fp.read(1)
            else:
                f.read_text(encoding='utf-8')
            return True
        except OSError: time.sleep(1)
        except Exception: return True
    return False

# ── FIX: 兼容 Python < 3.5（无 json.JSONDecodeError）；
#         fallback 时用正则抢救真实 content，避免文件名乱码 ──
def read_task(f):
    raw = f.read_text(encoding='utf-8').strip()
    try:
        return json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        # 尝试从损坏的 JSON 中提取 type / content 字段
        type_m    = re.search(r'"type"\s*:\s*"(\w+)"', raw)
        content_m = re.search(r'"content"\s*:\s*"((?:[^"\\]|\\.)*)"', raw, re.DOTALL)
        if content_m:
            content = content_m.group(1).replace('\\"', '"').replace('\\n', '\n')
            task_type = type_m.group(1) if type_m else "text"
            log(f"Error / JSON 解析失败，已抢救字段 / recovered fields (type={task_type}): {f.name}")
            return {"type": task_type, "content": content}
        # 完全无法解析，当作纯文本
        log(f"Error / JSON 解析失败，按纯文本处理 / processing as plain text: {f.name}")
        return {"type": "text", "content": raw}

def handle_url(task):
    subprocess.run(["open", task["content"]])
    log(f"Opened URL / 已打开链接: {task['content']}")

def handle_file(task):
    import shutil
    src = QUEUE_DIR / task["filename"]
    dst = Path.home() / "Downloads" / task["filename"]
    if not src.exists():
        log(f"Warning / 文件不存在，跳过 / file missing, skipped: {src.name}"); return
    if not wait_for_icloud(src, binary=True):
        raise OSError(f"iCloud sync timeout / iCloud 文件同步超时: {src.name}")
    shutil.copy(src, dst); src.unlink()
    subprocess.run(["open", str(dst.parent)])
    log(f"Saved file / 已保存文件: {dst}")

def handle_task_to_file(task):
    content  = task.get("content", "")
    base     = "airqueue_" + safe_filename(task.get("content", ""))   # FIX: 提前提取，避免 f-string 嵌套引号问题
    filename = base + ".txt"
    dst      = Path.home() / "Downloads" / filename
    counter  = 1
    while dst.exists():
        dst = Path.home() / "Downloads" / f"{base}_{counter}.txt"   # FIX: 内层改用单引号
        counter += 1
    dst.write_text(content, encoding="utf-8")
    log(f"Saved task file / 已保存任务文件: {dst}")
    return dst

def handle_text_to_clipboard(content):
    subprocess.run(["pbcopy"], input=content.encode("utf-8"), check=True)
    log("Copied text to clipboard / 文本已写入剪贴板")

def cleanup_old_logs(days=7):
    if not LOG_FILE.exists(): return
    cutoff = datetime.now().timestamp() - days * 86400
    lines  = LOG_FILE.read_text(encoding='utf-8').splitlines()
    kept   = []
    for l in lines:
        try:
            if datetime.strptime(l[1:20], "%Y-%m-%d %H:%M:%S").timestamp() < cutoff: continue
        except Exception: pass
        kept.append(l)
    LOG_FILE.write_text('\n'.join(kept) + '\n', encoding='utf-8')

def process_queue():
    if not QUEUE_DIR.exists(): return
    files     = sorted([f for f in os.listdir(str(QUEUE_DIR))
                        if not f.startswith('.') and f.startswith('task_')])
    all_files = [QUEUE_DIR / f for f in files]
    url_files, file_files, text_files = [], [], []

    for f in all_files:
        try:
            if not wait_for_icloud(f, binary=False):
                log(f"Warning / 等待 iCloud 同步超时，跳过 / sync timeout, skipped: {f.name}"); continue
            task = read_task(f)
            t = task.get("type")
            if t == "url":    url_files.append((f, task))
            elif t == "file": file_files.append((f, task))
            elif t == "text": text_files.append((f, task))
        except Exception as e:
            name = f.name
            error_counts[name] = error_counts.get(name, 0) + 1
            save_error_counts(error_counts)   # FIX: 立即持久化
            if error_counts[name] >= MAX_ERRORS:
                log(f"Error / 放弃处理 / giving up on {name}: {e}")
                notify_error("AirQueue（隔空随达）❌", f"任务解析失败 / Task parsing failed: {name}")
                try: f.unlink()
                except: pass
                error_counts.pop(name, None)
                save_error_counts(error_counts)
            else:
                log(f"Error / 读取失败 / read failed {name} (attempt {error_counts[name]}): {e}")

    for f, task in url_files:
        try:
            handle_url(task); f.unlink(); error_counts.pop(f.name, None)
            save_error_counts(error_counts)
        except Exception as e:
            log(f"Error / 错误: {e}"); notify_error("AirQueue（隔空随达）❌", f"链接打开失败 / Failed to open URL: {f.name}")

    for f, task in file_files:
        try:
            handle_file(task); f.unlink(); error_counts.pop(f.name, None)
            save_error_counts(error_counts)
        except Exception as e:
            name = f.name
            error_counts[name] = error_counts.get(name, 0) + 1
            save_error_counts(error_counts)
            if error_counts[name] >= MAX_ERRORS:
                log(f"Error / 放弃处理 / giving up on {name}: {e}"); notify_error("AirQueue（隔空随达）❌", f"文件保存失败 / File save failed: {name}")
                try: f.unlink()
                except: pass
                error_counts.pop(name, None)
                save_error_counts(error_counts)
            else:
                log(f"Error / 错误 {name} (attempt {error_counts[name]}): {e}")

    if text_files:
        copied_count = 0
        for f, task in text_files:
            name = f.name
            try:
                c = task.get("content", "").replace('\\n', '\n').strip()
                if re.match(r'^https?://\S+$', c):
                    try: handle_url({**task, "content": c})
                    except Exception as e: log(f"Error / 链接打开失败 / failed to open URL: {e}")
                handle_text_to_clipboard(c)
                copied_count += 1; f.unlink()
                error_counts.pop(name, None)
                save_error_counts(error_counts)
            except Exception as e:
                error_counts[name] = error_counts.get(name, 0) + 1
                save_error_counts(error_counts)
                if error_counts[name] >= MAX_ERRORS:
                    log(f"Error / 放弃处理 / giving up on {name}: {e}"); notify_error("AirQueue（隔空随达）❌", f"任务处理失败 / Task processing failed: {name}")
                    try: f.unlink()
                    except: pass
                    error_counts.pop(name, None)
                    save_error_counts(error_counts)
                else:
                    log(f"Error / 错误 {name} (attempt {error_counts[name]}): {e}")
                    if error_counts[name] == 1:
                        notify_error("AirQueue（隔空随达）⚠️", f"处理出错，正在重试 / Error; retrying: {name}")
        if copied_count:
            notify("AirQueue（隔空随达）✅", f"已写入剪贴板 / Written to clipboard: {copied_count} task(s)")
            log(f"Copied {copied_count} text task(s) to clipboard / 已复制 {copied_count} 个文本任务")

if __name__ == "__main__":
    cleanup_old_logs()
    log("AirQueue（隔空随达）watcher started / 后台服务已启动")
    process_queue()
PYEOF

chmod +x "$HOME/bin/airqueue_watcher.py"
echo "   ✓ airqueue_watcher.py"

# 写入 zshrc 管理命令
ZSHRC="$HOME/.zshrc"
if grep -q "# >>> AIRQUEUE_START >>>" "$ZSHRC" 2>/dev/null; then
    sed -i '' '/^# >>> AIRQUEUE_START >>>/,/^# <<< AIRQUEUE_END <<</d' "$ZSHRC"
fi
cat >> "$ZSHRC" << 'ZSHEOF'
# >>> AIRQUEUE_START >>>
airqueue_status() {
    local info=$(launchctl list | grep "com.user.airqueue")
    if [ -n "$info" ]; then
        local pid=$(echo "$info" | awk '{print $1}')
        [ "$pid" = "-" ] && echo "🟢 AirQueue（隔空随达）: [等待队列任务 / Waiting for tasks]" || echo "🔵 AirQueue（隔空随达）: [运行中 / Running] (PID: $pid)"
    else
        echo "🔴 AirQueue（隔空随达）: [未安装或未启动 / Not installed or not running]"
    fi
}
airqueue_stop() {
    echo "🛑 停止 AirQueue（隔空随达） / Stopping AirQueue..."
    launchctl bootout gui/$(id -u) "$HOME/Library/LaunchAgents/com.user.airqueue.plist" 2>/dev/null || true
    pkill -f airqueue_watcher.py 2>/dev/null || true
    sleep 0.5; airqueue_status
}
airqueue_start() {
    echo "🚀 启动 AirQueue（隔空随达） / Starting AirQueue..."
    launchctl bootstrap gui/$(id -u) "$HOME/Library/LaunchAgents/com.user.airqueue.plist" 2>/dev/null
    launchctl kickstart -p gui/$(id -u)/com.user.airqueue 2>/dev/null
    sleep 1; airqueue_status
}
airqueue_uninstall() {
    echo "🗑️  卸载 AirQueue（隔空随达） / Uninstalling AirQueue..."
    launchctl bootout gui/$(id -u) "$HOME/Library/LaunchAgents/com.user.airqueue.plist" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/com.user.airqueue.plist"
    rm -f "$HOME/bin/airqueue_watcher.py"
    rm -f "$HOME/.airqueue.log"
    rm -f "$HOME/.airqueue_errors.json"
    [ -f "$HOME/.zshrc" ] && sed -i '' '/^# >>> AIRQUEUE_START >>>/,/^# <<< AIRQUEUE_END <<</d' "$HOME/.zshrc"
    echo "✅ 卸载完成！iCloud 队列文件夹已保留，如需可手动删除。 / Uninstalled; the iCloud queue was kept."
    echo "请重开终端或执行 source ~/.zshrc 生效 / Reopen the terminal or run source ~/.zshrc."
}
airqueue_log() {
    if [ -f "$HOME/.airqueue.log" ]; then
        cat "$HOME/.airqueue.log"
    else
        echo "日志文件不存在 / Log file not found"
    fi
}
airqueue_errors() {
    if [ -f "$HOME/.airqueue.log" ]; then
        grep -Ei "error|错误|失败|放弃" "$HOME/.airqueue.log" || echo "无错误日志 / No errors logged"
    else
        echo "日志文件不存在 / Log file not found"
    fi
}
# <<< AIRQUEUE_END <<<
ZSHEOF
echo "   ✓ ~/.zshrc 管理命令已写入 / Management commands added"

# 注册 LaunchAgent（直接用 python3 真实路径）
if launchctl list | grep -q "com.user.airqueue"; then
    launchctl bootout gui/$(id -u) "$HOME/Library/LaunchAgents/com.user.airqueue.plist" 2>/dev/null || true
    pkill -f airqueue_watcher.py 2>/dev/null || true
    sleep 1
fi

cat > "$HOME/Library/LaunchAgents/com.user.airqueue.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.user.airqueue</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PYTHON_PATH</string>
    <string>$HOME/bin/airqueue_watcher.py</string>
  </array>
  <key>WorkingDirectory</key><string>$HOME</string>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>WatchPaths</key>
  <array>
    <string>/Library/Preferences/SystemConfiguration/com.apple.PowerManagement.plist</string>
    <string>$HOME/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/AirQueue/pending</string>
  </array>
  <key>KeepAlive</key><false/>
  <key>StandardOutPath</key><string>/tmp/airqueue.stdout</string>
  <key>StandardErrorPath</key><string>/tmp/airqueue.stderr</string>
</dict>
</plist>
PLIST

launchctl bootstrap gui/$(id -u) "$HOME/Library/LaunchAgents/com.user.airqueue.plist" \
    || { echo "  $MSG_NO_LOAD"; cat /tmp/airqueue.stderr 2>/dev/null | tail -5; exit 1; }

sleep 2
SVC=$(launchctl list | grep "com.user.airqueue")
PID=$(echo "$SVC" | awk '{print $1}')

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  $MSG_SUCCESS"
[ "$PID" = "-" ] && echo "  🟢 服务状态: 等待队列任务" || echo "  🔵 服务状态: 运行中 (PID: $PID)"
echo ""
echo "  常用命令 / Commands:"
echo "  airqueue_status     查看状态 / Check status"
echo "  airqueue_stop       停止服务 / Stop service"
echo "  airqueue_start      启动服务 / Start service"
echo "  airqueue_uninstall  卸载 / Uninstall"
echo "  airqueue_log        查看运行日志 / View runtime log"
echo "  airqueue_errors     查看错误日志 / View error log"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "$MSG_SOURCE"
echo "   source ~/.zshrc"
echo ""
