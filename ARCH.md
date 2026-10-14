# 技术说明

## LaunchAgent 更新与重启

- Mac 后台入口是 `~/Library/LaunchAgents/com.user.airqueue.plist`，由它指定已安装的 Python 可执行文件和 `~/bin/airqueue_watcher.py`。
- watcher 的代码模板位于 `install_airqueue.sh` 的 Python heredoc 中，安装后的运行文件是 `~/bin/airqueue_watcher.py`。只更新 watcher 时，部署更新后的运行文件并重启现有 LaunchAgent；不要为了重启而重跑安装器，也不要擅自替换 plist 中已安装的 Python 路径。
- 在此前已成功运行 AirQueue、并具有其 iCloud 目录访问能力的 Terminal 中执行：

  ```bash
  launchctl kickstart -k gui/$(id -u)/com.user.airqueue
  sleep 2
  tail -n 5 ~/.airqueue.log
  ```

- 新的 `watcher started` 日志用于确认启动。LaunchAgent 会按需运行 watcher，`KeepAlive` 为 `false`，所以任务处理后服务显示为未运行不一定表示启动失败。
- 从其他宿主应用或执行上下文观察到 iCloud `PermissionError`，只能说明该上下文的访问失败，不能据此推断此前的 Python 授权已失效。先使用原有 Terminal 重启并查看 AirQueue 日志；不要因此要求重复授权或更改 Python 路径。
- 当前已安装配置使用 `/usr/bin/python3`。安装器后续重新安装时会使用当时解析出的 Python 路径；这属于安装行为，不是普通代码更新或重启步骤。
