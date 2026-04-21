#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


DEFAULT_PROJECT_DIR = Path("/Users/xufan65/Documents/Codex/2026-04-17-new-chat")


def resolve_project_dir() -> Path:
    raw = os.environ.get("QIEMAN_PROJECT_DIR", "").strip()
    target = Path(raw).expanduser() if raw else DEFAULT_PROJECT_DIR
    return target.resolve()


def run_command(command: list[str], cwd: Path) -> int:
    process = subprocess.run(command, cwd=str(cwd))
    return int(process.returncode)


def ensure_project_files(project_dir: Path) -> dict[str, Path]:
    files = {
        "dashboard": project_dir / "dashboard_server.py",
        "public": project_dir / "qieman_scraper.py",
        "community": project_dir / "qieman_community_scraper.py",
        "cookie": project_dir / "qieman.cookie",
    }
    missing = [str(path) for key, path in files.items() if key != "cookie" and not path.exists()]
    if missing:
        raise FileNotFoundError("Missing project files: " + ", ".join(missing))
    return files


def main() -> int:
    parser = argparse.ArgumentParser(description="Qieman project launcher for the local skill.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    dashboard = subparsers.add_parser("dashboard", help="Launch dashboard_server.py")
    dashboard.add_argument("--open", action="store_true", help="Open the browser after launch")
    dashboard.add_argument("extra", nargs=argparse.REMAINDER, help="Extra arguments passed to dashboard_server.py")

    public = subparsers.add_parser("public", help="Run qieman_scraper.py")
    public.add_argument("extra", nargs=argparse.REMAINDER, help="Arguments passed after -- to qieman_scraper.py")

    community = subparsers.add_parser("community", help="Run qieman_community_scraper.py")
    community.add_argument("extra", nargs=argparse.REMAINDER, help="Arguments passed after -- to qieman_community_scraper.py")

    auth_check = subparsers.add_parser("auth-check", help="Validate local Qieman cookie using qieman_community_scraper.py")
    auth_check.add_argument("--cookie-file", default="", help="Optional cookie file path")

    repo_path = subparsers.add_parser("repo-path", help="Print the resolved Qieman project path")
    repo_path.add_argument("--json", action="store_true", help="Print only the path without extra prose")

    args = parser.parse_args()
    project_dir = resolve_project_dir()

    if args.command == "repo-path":
        print(project_dir if args.json else f"QIEMAN_PROJECT_DIR={project_dir}")
        return 0

    try:
        files = ensure_project_files(project_dir)
    except FileNotFoundError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    if args.command == "dashboard":
        command = [sys.executable, str(files["dashboard"])]
        if args.open:
            command.append("--open")
        extra = list(args.extra or [])
        if extra and extra[0] == "--":
            extra = extra[1:]
        command.extend(extra)
        return run_command(command, project_dir)

    if args.command == "public":
        extra = list(args.extra or [])
        if extra and extra[0] == "--":
            extra = extra[1:]
        return run_command([sys.executable, str(files["public"]), *extra], project_dir)

    if args.command == "community":
        extra = list(args.extra or [])
        if extra and extra[0] == "--":
            extra = extra[1:]
        return run_command([sys.executable, str(files["community"]), *extra], project_dir)

    if args.command == "auth-check":
        cookie_file = Path(args.cookie_file).expanduser().resolve() if args.cookie_file else files["cookie"]
        command = [
            sys.executable,
            str(files["community"]),
            "--mode",
            "auth-check",
            "--cookie-file",
            str(cookie_file),
        ]
        return run_command(command, project_dir)

    print(f"Unknown command: {args.command}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
