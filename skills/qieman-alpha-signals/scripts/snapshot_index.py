#!/usr/bin/env python3
from __future__ import annotations

import argparse
from typing import Any, Dict, List

from _qieman_skill_common import ensure_project_dir, load_dashboard_module, print_json, resolve_project_dir


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="列出本地 output 快照索引")
    parser.add_argument("--search", default="", help="文件名/标题/模式关键字")
    parser.add_argument("--snapshot-type", default="", help="按 snapshot_type 过滤，如 posts/users/groups/items")
    parser.add_argument("--mode", default="", help="按 mode 过滤")
    parser.add_argument("--limit", type=int, default=50, help="返回上限")
    parser.add_argument("--project-dir", default="", help="可选，项目目录")
    parser.add_argument("--json", action="store_true", help="输出 JSON")
    return parser


def filter_rows(args: argparse.Namespace, rows: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    search = args.search.strip().lower()
    snapshot_type = args.snapshot_type.strip()
    mode = args.mode.strip()

    results: List[Dict[str, Any]] = []
    for row in rows:
        if snapshot_type and snapshot_type != str(row.get("snapshot_type") or ""):
            continue
        if mode and mode != str(row.get("mode") or ""):
            continue
        if search:
            hay = "\n".join(
                str(row.get(key) or "")
                for key in ["file_name", "title", "subtitle", "mode", "snapshot_type"]
            ).lower()
            if search not in hay:
                continue
        results.append(
            {
                "file_name": row.get("file_name"),
                "snapshot_type": row.get("snapshot_type"),
                "mode": row.get("mode"),
                "title": row.get("title"),
                "subtitle": row.get("subtitle"),
                "created_at": row.get("created_at"),
                "count": row.get("count"),
            }
        )
        if len(results) >= max(1, args.limit):
            break
    return results


def run(args: argparse.Namespace) -> int:
    project_dir = ensure_project_dir(resolve_project_dir(args.project_dir))
    dashboard = load_dashboard_module(project_dir)
    rows = dashboard.history_summaries()
    items = filter_rows(args, rows)
    payload = {"count": len(items), "items": items}

    if args.json:
        print_json(payload)
    else:
        print(f"count={payload['count']}")
        for item in items:
            print(
                f"{item.get('file_name')} | {item.get('snapshot_type')} | {item.get('mode')} "
                f"| {item.get('count')} 条 | {item.get('created_at')}"
            )
    return 0


def main() -> int:
    return run(build_parser().parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
