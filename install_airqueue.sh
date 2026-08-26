#!/bin/bash
# ═══════════════════════════════════════════════════════════
#  AirQueue 安装脚本
#  用法：bash install_airqueue.sh
# ═══════════════════════════════════════════════════════════

set -e

# ── 语言检测 ──────────────────────────────────────────────
LANG_CODE=$(defaults read -g AppleLocale 2>/dev/null | cut -d'_' -f1)
if [ "$LANG_CODE" = "zh" ]; then
    MSG_START="📦 AirQueue 安装开始..."
    MSG_NO_PYTHON="❌ 找不到 python3，请先安装 Python3"
    MSG_STEP1="📁 [1/3] 创建目录..."
    MSG_STEP2="🔐 [2/3] 检查权限..."
    MSG_STEP3="🐍 [3/3] 安装服务..."
    MSG_NO_QUEUE="❌ 未找到 iCloud 队列目录，请确认 iCloud Drive 已开启并运行过快捷指令"
    MSG_NO_LOAD="❌ 服务注册失败"
    MSG_SUCCESS="✅ 安装完成！"
    MSG_SOURCE="⚡ 请执行以下命令让终端命令立即生效:"
    MSG_PERM_CANCEL="❌ 用户取消了权限设置，安装中止。"
    MSG_PERM_RETRY="⚠️  权限仍未开启，请确认已开启开关后按 Enter..."
else
    MSG_START="📦 Installing AirQueue..."
    MSG_NO_PYTHON="❌ python3 not found. Please install Python3 first."
    MSG_STEP1="📁 [1/3] Creating directories..."
    MSG_STEP2="🔐 [2/3] Checking permissions..."
    MSG_STEP3="🐍 [3/3] Installing service..."
    MSG_NO_QUEUE="❌ iCloud queue directory not found. Make sure iCloud Drive is enabled and Shortcuts has run once."
    MSG_NO_LOAD="❌ Failed to register service"
    MSG_SUCCESS="✅ Installation complete!"
    MSG_SOURCE="⚡ Run this to activate commands in current terminal:"
    MSG_PERM_CANCEL="❌ Permission setup cancelled. Installation aborted."
    MSG_PERM_RETRY="⚠️  Permission not yet granted. Please toggle on, then press Enter..."
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  $MSG_START"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  👤 用户  : $(whoami)"
echo "  🏠 主目录: $HOME"

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
    echo "  请确认："
    echo "  1. iCloud Drive 已开启"
    echo "  2. 快捷指令 App 已在 iPhone 上运行过一次（触发文件夹创建）"
    exit 1
fi
echo "   ✓ iCloud 队列目录已就绪"
echo "   ✓ 其他目录就绪"

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
    local msg="需要为「${target_name}」开启完全磁盘访问权限。
"
    msg+="接下来会自动打开系统设置，请：
"
    msg+="  1. 点击左下角「+」号
"
    msg+="  2. 按 Command+Shift+G 输入路径：${target_path}
"
    msg+="  3. 点击「打开」，然后开启右侧开关
"
    msg+="  4. 回到此终端按 Enter 继续"

    RESULT=$(osascript -e "tell application \"System Events\" to activate"                        -e "set btn to button returned of (display dialog \"${msg}\" with title \"AirQueue 权限设置\" buttons {\"取消\", \"前往设置\"} default button \"前往设置\" with icon caution)"                        -e "return btn" 2>/dev/null)

    if [ "$RESULT" != "前往设置" ]; then
        echo "$MSG_PERM_CANCEL"
        exit 1
    fi

    open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
}

# —— ① Terminal：可靠检测（Terminal 不是自身子进程）——
if check_fda; then
    echo "   ✓ Terminal 完全磁盘访问权限已就绪"
else
    echo "   ⚠️  需要为「$TERMINAL_APP」开启完全磁盘访问权限"
    guide_fda "$TERMINAL_APP" "/System/Applications/Utilities/Terminal.app"
    while true; do
        read -p "   完成后请按 [Enter] 继续..." </dev/tty
        if check_fda; then
            echo "   ✓ Terminal 权限验证通过！"
            break
        else
            echo "   $MSG_PERM_RETRY"
        fi
    done
fi

# —— ② Python3：后台运行需要独立 FDA ——
if check_python_fda; then
    echo "   ✓ Python3 完全磁盘访问权限已就绪"
else
    echo "   ⚠️  需要为 Python3 开启完全磁盘访问权限（后台服务独立运行时使用）"
    echo "      路径：$PYTHON_PATH"
    guide_fda "python3" "$PYTHON_PATH"
    while true; do
        read -p "   完成后请按 [Enter] 继续..." </dev/tty
        if check_python_fda; then
            echo "   ✓ Python3 权限验证通过！"
            break
        else
            echo "   $MSG_PERM_RETRY"
        fi
    done
fi
echo "   ✓ Python3 权限设置完成"

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
            log("系统刚启动，执行 30s 避峰延迟...")
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
            log(f"JSON 解析失败，已从残损内容中抢救字段 (type={task_type}): {f.name}")
            return {"type": task_type, "content": content}
        # 完全无法解析，当作纯文本
        log(f"JSON 解析失败，作为纯文本处理: {f.name}")
        return {"type": "text", "content": raw}

def handle_url(task):
    subprocess.run(["open", task["content"]])
    log(f"Opened URL: {task['content']}")

def handle_file(task):
    import shutil
    src = QUEUE_DIR / task["filename"]
    dst = Path.home() / "Downloads" / task["filename"]
    if not src.exists():
        log(f"文件已不存在，跳过: {src.name}"); return
    if not wait_for_icloud(src, binary=True):
        raise OSError(f"iCloud 文件同步超时: {src.name}")
    shutil.copy(src, dst); src.unlink()
    subprocess.run(["open", str(dst.parent)])
    log(f"Saved file: {dst}")

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
    log(f"Saved task file: {dst}")
    return dst

def handle_text_to_clipboard(content):
    subprocess.run(["pbcopy"], input=content.encode("utf-8"), check=True)
    log("Copied text to clipboard")

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
                log(f"等待 iCloud 同步超时，跳过: {f.name}"); continue
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
                log(f"放弃处理 {name}：{e}")
                notify_error("AirQueue ❌", f"任务解析失败: {name}")
                try: f.unlink()
                except: pass
                error_counts.pop(name, None)
                save_error_counts(error_counts)
            else:
                log(f"Error reading {name} (第{error_counts[name]}次): {e}")

    for f, task in url_files:
        try:
            handle_url(task); f.unlink(); error_counts.pop(f.name, None)
            save_error_counts(error_counts)
        except Exception as e:
            log(f"Error: {e}"); notify_error("AirQueue ❌", f"链接打开失败: {f.name}")

    for f, task in file_files:
        try:
            handle_file(task); f.unlink(); error_counts.pop(f.name, None)
            save_error_counts(error_counts)
        except Exception as e:
            name = f.name
            error_counts[name] = error_counts.get(name, 0) + 1
            save_error_counts(error_counts)
            if error_counts[name] >= MAX_ERRORS:
                log(f"放弃: {name}：{e}"); notify_error("AirQueue ❌", f"文件保存失败: {name}")
                try: f.unlink()
                except: pass
                error_counts.pop(name, None)
                save_error_counts(error_counts)
            else:
                log(f"Error {name} (第{error_counts[name]}次): {e}")

    if text_files:
        copied_count = 0
        for f, task in text_files:
            name = f.name
            try:
                c = task.get("content", "").replace('\\n', '\n').strip()
                if re.match(r'^https?://\S+$', c):
                    try: handle_url({**task, "content": c})
                    except Exception as e: log(f"链接打开失败: {e}")
                handle_text_to_clipboard(c)
                copied_count += 1; f.unlink()
                error_counts.pop(name, None)
                save_error_counts(error_counts)
            except Exception as e:
                error_counts[name] = error_counts.get(name, 0) + 1
                save_error_counts(error_counts)
                if error_counts[name] >= MAX_ERRORS:
                    log(f"放弃: {name}：{e}"); notify_error("AirQueue ❌", f"任务处理失败: {name}")
                    try: f.unlink()
                    except: pass
                    error_counts.pop(name, None)
                    save_error_counts(error_counts)
                else:
                    log(f"Error {name} (第{error_counts[name]}次): {e}")
                    if error_counts[name] == 1:
                        notify_error("AirQueue ⚠️", f"处理出错，正在重试: {name}")
        if copied_count:
            notify("AirQueue ✅", f"已写入剪贴板 {copied_count} 个任务")
            log(f"Copied {copied_count} text task(s) to clipboard")

if __name__ == "__main__":
    cleanup_old_logs()
    log("AirQueue watcher started")
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
        [ "$pid" = "-" ] && echo "🟢 AirQueue: [等待队列任务]" || echo "🔵 AirQueue: [运行中] (PID: $pid)"
    else
        echo "🔴 AirQueue: [未安装或未启动]"
    fi
}
airqueue_stop() {
    echo "🛑 停止 AirQueue..."
    launchctl bootout gui/$(id -u) "$HOME/Library/LaunchAgents/com.user.airqueue.plist" 2>/dev/null || true
    pkill -f airqueue_watcher.py 2>/dev/null || true
    sleep 0.5; airqueue_status
}
airqueue_start() {
    echo "🚀 启动 AirQueue..."
    launchctl bootstrap gui/$(id -u) "$HOME/Library/LaunchAgents/com.user.airqueue.plist" 2>/dev/null
    launchctl kickstart -p gui/$(id -u)/com.user.airqueue 2>/dev/null
    sleep 1; airqueue_status
}
airqueue_uninstall() {
    echo "🗑️  卸载 AirQueue..."
    launchctl bootout gui/$(id -u) "$HOME/Library/LaunchAgents/com.user.airqueue.plist" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/com.user.airqueue.plist"
    rm -f "$HOME/bin/airqueue_watcher.py"
    rm -f "$HOME/.airqueue.log"
    rm -f "$HOME/.airqueue_errors.json"
    [ -f "$HOME/.zshrc" ] && sed -i '' '/^# >>> AIRQUEUE_START >>>/,/^# <<< AIRQUEUE_END <<</d' "$HOME/.zshrc"
    echo "✅ 卸载完成！iCloud 队列文件夹已保留，如需可手动删除。"
    echo "请重开终端或执行 source ~/.zshrc 生效。"
}
airqueue_log() {
    if [ -f "$HOME/.airqueue.log" ]; then
        cat "$HOME/.airqueue.log"
    else
        echo "日志文件不存在"
    fi
}
airqueue_errors() {
    if [ -f "$HOME/.airqueue.log" ]; then
        grep -i "error" "$HOME/.airqueue.log" || echo "无错误日志"
    else
        echo "日志文件不存在"
    fi
}
# <<< AIRQUEUE_END <<<
ZSHEOF
echo "   ✓ ~/.zshrc 管理命令已写入"

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
echo "  常用命令:"
echo "  airqueue_status    查看状态"
echo "  airqueue_stop      停止服务"
echo "  airqueue_start     启动服务"
echo "  airqueue_uninstall 卸载"
echo "  airqueue_log       查看运行日志"
echo "  airqueue_errors    查看错误日志"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "$MSG_SOURCE"
echo "   source ~/.zshrc"
echo ""
