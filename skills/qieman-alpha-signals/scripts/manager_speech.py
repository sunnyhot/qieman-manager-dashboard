#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

from _qieman_skill_common import ensure_project_dir, load_project_module, project_file, resolve_project_dir


JSON_LINE_RE = re.compile(r"^JSON:\s*(.+)$", re.M)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="主理人言论抓取（关注动态 / 公开主理人流 / 个人空间 / 公开内容）")
    parser.add_argument("--mode", choices=("following-posts", "group-manager", "space-items", "public"), default="following-posts")
    parser.add_argument("--prod-code", default="LONG_WIN", help="产品代码，group-manager 默认用它定位小组")
    parser.add_argument("--manager-name", default="", help="主理人名，group-manager/public 可用")
    parser.add_argument("--user-name", default="", help="用户昵称过滤")
    parser.add_argument("--broker-user-id", default="", help="按 brokerUserId 过滤")
    parser.add_argument("--space-user-id", default="", help="space-items 模式可直接传")
    parser.add_argument("--group-id", default="", help="group-manager 模式可直接传")
    parser.add_argument("--group-url", default="", help="group-manager 模式可传 group-detail URL")
    parser.add_argument("--keyword", default="", help="关键词过滤")
    parser.add_argument("--query", default="", help="public 模式查询词；不传则回落到 keyword")
    parser.add_argument("--since", default="", help="起始日期 YYYY-MM-DD")
    parser.add_argument("--until", default="", help="结束日期 YYYY-MM-DD")
    parser.add_argument("--pages", type=int, default=5, help="抓取页数")
    parser.add_argument("--page-size", type=int, default=10, help="每页数量")
    parser.add_argument("--only-manager", action="store_true", help="group-manager 只保留主理人帖子")
    parser.add_argument("--cookie", default="", help="可选，直接传 Cookie")
    parser.add_argument("--cookie-file", default="", help="可选，Cookie 文件")
    parser.add_argument("--output-dir", default="", help="输出目录，默认项目 output/")
    parser.add_argument("--markdown", action="store_true", help="同时导出 markdown")
    parser.add_argument("--extract-signals", action="store_true", help="提取发车/减仓等高置信动作")
    parser.add_argument("--preview", type=int, default=5, help="返回前几条摘要")
    parser.add_argument("--json", action="store_true", help="输出 JSON")
    parser.add_argument("--project-dir", default="", help="可选，项目目录；默认读 QIEMAN_PROJECT_DIR")
    return parser


def parse_json_path(output: str) -> Optional[str]:
    matches = JSON_LINE_RE.findall(output or "")
    if not matches:
        return None
    return matches[-1].strip()


def run_command(command: List[str], cwd: Path) -> subprocess.CompletedProcess:
    return subprocess.run(command, cwd=str(cwd), capture_output=True, text=True)


def build_community_command(args: argparse.Namespace, project_dir: Path, output_dir: Path) -> List[str]:
    script = project_file(project_dir, "qieman_community_scraper.py")
    command = [
        sys.executable,
        str(script),
        "--mode",
        args.mode,
        "--pages",
        str(max(1, args.pages)),
        "--page-size",
        str(max(1, args.page_size)),
        "--output-dir",
        str(output_dir),
    ]

    if args.prod_code:
        command.extend(["--prod-code", args.prod_code])
    if args.manager_name:
        command.extend(["--manager-name", args.manager_name])
    if args.user_name:
        command.extend(["--user-name", args.user_name])
    if args.broker_user_id:
        command.extend(["--broker-user-id", args.broker_user_id])
    if args.space_user_id:
        command.extend(["--space-user-id", args.space_user_id])
    if args.group_id:
        command.extend(["--group-id", args.group_id])
    if args.group_url:
        command.extend(["--group-url", args.group_url])
    if args.keyword:
        command.extend(["--keyword", args.keyword])
    if args.since:
        command.extend(["--since", args.since])
    if args.until:
        command.extend(["--until", args.until])
    if args.only_manager and args.mode == "group-manager":
        command.append("--only-manager")
    if args.markdown:
        command.append("--markdown")

    if args.cookie:
        command.extend(["--cookie", args.cookie])
    elif args.cookie_file:
        command.extend(["--cookie-file", args.cookie_file])
    else:
        default_cookie = project_dir / "qieman.cookie"
        if args.mode in {"following-posts", "space-items"} and default_cookie.exists():
            command.extend(["--cookie-file", str(default_cookie)])
    return command


def build_public_command(args: argparse.Namespace, project_dir: Path, output_dir: Path) -> List[str]:
    script = project_file(project_dir, "qieman_scraper.py")
    query = args.query or args.keyword or "长赢计划"
    command = [
        sys.executable,
        str(script),
        "--query",
        query,
        "--limit",
        str(max(20, args.pages * args.page_size)),
        "--output-dir",
        str(output_dir),
    ]
    author = args.manager_name or args.user_name
    if author:
        command.extend(["--author", author])
    if args.markdown:
        command.append("--markdown")
    return command


def normalize_public_posts(raw_items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    records: List[Dict[str, Any]] = []
    for index, item in enumerate(raw_items, start=1):
        if not isinstance(item, dict):
            continue
        records.append(
            {
                "post_id": index,
                "title": str(item.get("title") or "").strip(),
                "intro": str(item.get("snippet") or "").strip(),
                "content_text": str(item.get("content") or "").strip(),
                "created_at": str(item.get("publish_date") or "").strip(),
                "detail_url": str(item.get("url") or "").strip(),
                "user_name": str(item.get("author") or "").strip(),
                "comment_count": 0,
                "like_count": 0,
            }
        )
    return records


def load_posts_from_json(json_path: Path) -> List[Dict[str, Any]]:
    payload = json.loads(json_path.read_text(encoding="utf-8"))
    if isinstance(payload, dict) and isinstance(payload.get("posts"), list):
        return [item for item in payload.get("posts") if isinstance(item, dict)]
    if isinstance(payload, list):
        return normalize_public_posts([item for item in payload if isinstance(item, dict)])
    return []


def build_preview(posts: List[Dict[str, Any]], limit: int) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    for post in posts[: max(1, limit)]:
        rows.append(
            {
                "post_id": int(post.get("post_id") or 0),
                "created_at": str(post.get("created_at") or "").strip(),
                "user_name": str(post.get("user_name") or "").strip(),
                "title": str(post.get("title") or post.get("intro") or "").strip(),
                "detail_url": str(post.get("detail_url") or "").strip(),
            }
        )
    return rows


def run(args: argparse.Namespace) -> int:
    project_dir = ensure_project_dir(resolve_project_dir(args.project_dir))
    output_dir = Path(args.output_dir).expanduser().resolve() if args.output_dir else (project_dir / "output")
    output_dir.mkdir(parents=True, exist_ok=True)

    if args.mode == "public":
        command = build_public_command(args, project_dir, output_dir)
    else:
        command = build_community_command(args, project_dir, output_dir)

    process = run_command(command, project_dir)
    combined_output = "\n".join(part for part in [process.stdout, process.stderr] if part)
    if process.returncode != 0:
        raise SystemExit(
            "主理人言论抓取失败。\n"
            f"command: {' '.join(command)}\n"
            f"output:\n{combined_output.strip()}"
        )

    json_path_text = parse_json_path(process.stdout)
    if not json_path_text:
        raise SystemExit(f"抓取命令成功但没有解析到 JSON 输出路径。\n输出:\n{process.stdout.strip()}")

    json_path = Path(json_path_text).expanduser().resolve()
    posts = load_posts_from_json(json_path)
    preview = build_preview(posts, args.preview)

    payload: Dict[str, Any] = {
        "mode": args.mode,
        "json_path": str(json_path),
        "post_count": len(posts),
        "preview": preview,
    }

    if args.extract_signals:
        dashboard = load_project_module(project_dir, "dashboard_server")
        signals = dashboard.build_signal_stats(posts)
        payload["signals"] = {
            "count": dashboard.safe_int(signals.get("count")),
            "event_count": dashboard.safe_int(signals.get("event_count")),
            "counts": signals.get("counts") or {},
            "top_actions": signals.get("top_actions") or [],
            "top_assets": signals.get("top_assets") or [],
            "latest": signals.get("latest") or {},
        }

    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0

    print(f"mode={args.mode} | posts={payload['post_count']} | json={payload['json_path']}")
    for row in preview:
        print(
            f"[{row['created_at']}] {row['user_name'] or '未知用户'} | "
            f"{row['title'] or '无标题'} | {row['detail_url']}"
        )
    if args.extract_signals:
        signals = payload.get("signals") or {}
        counts = signals.get("counts") or {}
        print(
            f"signals={signals.get('count', 0)} | events={signals.get('event_count', 0)} | "
            f"buy={counts.get('buy', 0)} | sell={counts.get('sell', 0)}"
        )
    return 0


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return run(args)


if __name__ == "__main__":
    raise SystemExit(main())
