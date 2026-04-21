#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Dict, Optional

from _qieman_skill_common import ensure_project_dir, print_json, project_file, resolve_project_dir


DEFAULT_PID_FILE = Path("/tmp/qieman_alpha_dashboard.pid")
DEFAULT_LOG_FILE = Path("/tmp/qieman_alpha_dashboard.log")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="一键管理且慢项目运行（含前端页面）")
    parser.add_argument("--action", choices=("start", "status", "stop", "restart"), default="start", help="运行动作")
    parser.add_argument("--host", default="127.0.0.1", help="Dashboard 监听 host")
    parser.add_argument("--port", type=int, default=8765, help="Dashboard 监听端口")
    parser.add_argument("--open-browser", action="store_true", help="启动时自动打开浏览器")
    parser.add_argument("--foreground", action="store_true", help="前台运行（阻塞当前进程）")
    parser.add_argument("--startup-timeout", type=float, default=15.0, help="后台启动健康检查超时秒数")
    parser.add_argument("--pid-file", default=str(DEFAULT_PID_FILE), help="PID 文件路径")
    parser.add_argument("--log-file", default=str(DEFAULT_LOG_FILE), help="日志文件路径")
    parser.add_argument("--project-dir", default="", help="可选，项目目录")
    parser.add_argument("--json", action="store_true", help="输出 JSON")
    return parser


def is_pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def process_command(pid: int) -> str:
    if pid <= 0:
        return ""
    try:
        output = subprocess.check_output(
            ["ps", "-p", str(pid), "-o", "command="],
            text=True,
        )
        return output.strip()
    except Exception:
        return ""


def is_managed_dashboard_process(pid: int, project_dir: Path) -> bool:
    command = process_command(pid)
    if not command:
        return False
    if "dashboard_server.py" not in command:
        return False
    return str(project_dir) in command


def read_pid(pid_file: Path) -> int:
    if not pid_file.exists():
        return 0
    try:
        return int(pid_file.read_text(encoding="utf-8").strip())
    except Exception:
        return 0


def write_pid(pid_file: Path, pid: int) -> None:
    pid_file.parent.mkdir(parents=True, exist_ok=True)
    pid_file.write_text(str(pid), encoding="utf-8")


def remove_pid_file(pid_file: Path) -> None:
    try:
        if pid_file.exists():
            pid_file.unlink()
    except Exception:
        pass


def status_url(host: str, port: int) -> str:
    return f"http://{host}:{port}/api/status"


def app_url(host: str, port: int) -> str:
    return f"http://{host}:{port}/"


def fetch_api_status(host: str, port: int, timeout: float = 2.0) -> Optional[Dict[str, Any]]:
    url = status_url(host, port)
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            if response.status != 200:
                return None
            payload = response.read().decode("utf-8", errors="ignore")
    except (urllib.error.URLError, TimeoutError, ConnectionError):
        return None
    try:
        import json

        data = json.loads(payload)
        if isinstance(data, dict):
            return data
    except Exception:
        return None
    return None


def wait_ready(host: str, port: int, timeout: float) -> bool:
    deadline = time.time() + max(1.0, timeout)
    while time.time() < deadline:
        if fetch_api_status(host, port, timeout=2.0) is not None:
            return True
        time.sleep(0.35)
    return False


def build_dashboard_command(project_dir: Path, host: str, port: int, open_browser: bool) -> list[str]:
    dashboard_file = project_file(project_dir, "dashboard_server.py")
    command = [
        sys.executable,
        str(dashboard_file),
        "--host",
        host,
        "--port",
        str(port),
    ]
    if open_browser:
        command.append("--open")
    return command


def do_status(args: argparse.Namespace, pid_file: Path, project_dir: Path) -> Dict[str, Any]:
    pid = read_pid(pid_file)
    managed_running = is_pid_alive(pid) and is_managed_dashboard_process(pid, project_dir)
    if pid and not managed_running:
        remove_pid_file(pid_file)
        pid = 0
    api = fetch_api_status(args.host, args.port, timeout=1.8)
    external_running = bool(api) and not managed_running
    return {
        "running": bool(managed_running or api),
        "pid": pid if managed_running else 0,
        "url": app_url(args.host, args.port),
        "api_ready": bool(api),
        "managed_running": bool(managed_running),
        "external_running": bool(external_running),
        "api_status": api or {},
        "pid_file": str(pid_file),
        "log_file": args.log_file,
    }


def do_stop(pid_file: Path, timeout: float = 8.0) -> Dict[str, Any]:
    pid = read_pid(pid_file)
    if not is_pid_alive(pid):
        remove_pid_file(pid_file)
        return {
            "stopped": False,
            "message": "未发现运行中的进程",
            "pid": 0,
        }

    try:
        os.kill(pid, signal.SIGTERM)
    except Exception as exc:
        return {
            "stopped": False,
            "message": f"发送 SIGTERM 失败: {exc}",
            "pid": pid,
        }

    deadline = time.time() + max(1.0, timeout)
    while time.time() < deadline:
        if not is_pid_alive(pid):
            remove_pid_file(pid_file)
            return {
                "stopped": True,
                "message": "已停止",
                "pid": pid,
            }
        time.sleep(0.2)

    try:
        os.kill(pid, signal.SIGKILL)
    except Exception:
        pass
    time.sleep(0.2)
    remove_pid_file(pid_file)
    return {
        "stopped": not is_pid_alive(pid),
        "message": "超时后已尝试强制停止",
        "pid": pid,
    }


def do_start(args: argparse.Namespace, project_dir: Path, pid_file: Path, log_file: Path) -> Dict[str, Any]:
    existing = do_status(args, pid_file, project_dir)
    if existing.get("managed_running"):
        return {
            "started": False,
            "already_running": True,
            "external_running": False,
            "pid": existing.get("pid", 0),
            "url": app_url(args.host, args.port),
            "api_ready": existing.get("api_ready", False),
            "pid_file": str(pid_file),
            "log_file": str(log_file),
            "command": [],
        }
    if existing.get("external_running"):
        return {
            "started": False,
            "already_running": True,
            "external_running": True,
            "pid": 0,
            "url": app_url(args.host, args.port),
            "api_ready": True,
            "pid_file": str(pid_file),
            "log_file": str(log_file),
            "command": [],
            "message": "目标端口已有外部服务运行，未重复拉起。",
        }

    command = build_dashboard_command(project_dir, args.host, args.port, args.open_browser)

    if args.foreground:
        run = subprocess.run(command, cwd=str(project_dir))
        return {
            "started": run.returncode == 0,
            "already_running": False,
            "pid": 0,
            "url": app_url(args.host, args.port),
            "api_ready": False,
            "pid_file": str(pid_file),
            "log_file": str(log_file),
            "command": command,
            "return_code": int(run.returncode),
        }

    log_file.parent.mkdir(parents=True, exist_ok=True)
    with log_file.open("ab") as log_handle:
        proc = subprocess.Popen(
            command,
            cwd=str(project_dir),
            stdout=log_handle,
            stderr=log_handle,
            start_new_session=True,
        )

    write_pid(pid_file, proc.pid)
    time.sleep(0.25)
    return_code = proc.poll()
    if return_code is not None:
        remove_pid_file(pid_file)
        return {
            "started": False,
            "already_running": False,
            "external_running": False,
            "pid": 0,
            "url": app_url(args.host, args.port),
            "api_ready": False,
            "pid_file": str(pid_file),
            "log_file": str(log_file),
            "command": command,
            "return_code": int(return_code),
            "message": "dashboard 进程启动后立即退出，可能是端口被占用或环境异常。",
        }
    ready = wait_ready(args.host, args.port, args.startup_timeout)

    return {
        "started": True,
        "already_running": False,
        "external_running": False,
        "pid": proc.pid,
        "url": app_url(args.host, args.port),
        "api_ready": ready,
        "pid_file": str(pid_file),
        "log_file": str(log_file),
        "command": command,
    }


def render_text(payload: Dict[str, Any], action: str) -> None:
    if action == "status":
        print(
            f"running={payload.get('running')} | pid={payload.get('pid')} | "
            f"api_ready={payload.get('api_ready')} | managed={payload.get('managed_running')} "
            f"| external={payload.get('external_running')} | url={payload.get('url')}"
        )
        return
    if action == "stop":
        print(f"stopped={payload.get('stopped')} | pid={payload.get('pid')} | {payload.get('message')}")
        return
    if action in {"start", "restart"}:
        print(
            f"started={payload.get('started')} | already_running={payload.get('already_running')} | "
            f"external_running={payload.get('external_running')} | pid={payload.get('pid')} "
            f"| api_ready={payload.get('api_ready')} | url={payload.get('url')}"
        )
        if payload.get("message"):
            print(f"message={payload.get('message')}")
        print(f"log_file={payload.get('log_file')}")
        return


def run(args: argparse.Namespace) -> int:
    project_dir = ensure_project_dir(resolve_project_dir(args.project_dir))
    pid_file = Path(args.pid_file).expanduser().resolve()
    log_file = Path(args.log_file).expanduser().resolve()

    if args.action == "status":
        payload = do_status(args, pid_file, project_dir)
    elif args.action == "stop":
        payload = do_stop(pid_file)
    elif args.action == "restart":
        _ = do_stop(pid_file)
        payload = do_start(args, project_dir, pid_file, log_file)
    else:
        payload = do_start(args, project_dir, pid_file, log_file)

    if args.json:
        print_json(payload)
    else:
        render_text(payload, args.action)
    return 0


def main() -> int:
    return run(build_parser().parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
