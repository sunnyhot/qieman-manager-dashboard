#!/usr/bin/env python3
from __future__ import annotations

import argparse
from typing import Any, Dict, List

from _qieman_skill_common import ensure_project_dir, load_dashboard_module, print_json, resolve_project_dir


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="读取单个快照详情")
    parser.add_argument("--name", default="", help="快照文件名")
    parser.add_argument("--latest", action="store_true", help="读取最新快照")
    parser.add_argument("--preview", type=int, default=10, help="预览记录数量")
    parser.add_argument("--with-signals", action="store_true", help="返回 signals 摘要")
    parser.add_argument("--project-dir", default="", help="可选，项目目录")
    parser.add_argument("--json", action="store_true", help="输出 JSON")
    return parser


def pick_snapshot_name(dashboard, args: argparse.Namespace) -> str:
    if args.name.strip():
        return args.name.strip()
    if args.latest:
        history = dashboard.history_summaries()
        if not history:
            raise SystemExit("没有可用快照")
        return dashboard.normalize_text(history[0].get("file_name"))
    raise SystemExit("请提供 --name 或 --latest")


def build_preview_records(snapshot: Dict[str, Any], limit: int) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    records = [item for item in list(snapshot.get("records") or []) if isinstance(item, dict)]
    for record in records[: max(1, limit)]:
        rows.append(
            {
                "post_id": record.get("post_id") or record.get("id"),
                "created_at": record.get("created_at") or record.get("publish_date"),
                "user_name": record.get("user_name") or record.get("author"),
                "title": record.get("title") or record.get("intro"),
                "detail_url": record.get("detail_url") or record.get("url"),
            }
        )
    return rows


def run(args: argparse.Namespace) -> int:
    project_dir = ensure_project_dir(resolve_project_dir(args.project_dir))
    dashboard = load_dashboard_module(project_dir)

    name = pick_snapshot_name(dashboard, args)
    path = dashboard.snapshot_path_from_name(name)
    snapshot = dashboard.normalize_snapshot(path, include_records=True)

    payload: Dict[str, Any] = {
        "file_name": snapshot.get("file_name"),
        "file_path": snapshot.get("file_path"),
        "snapshot_type": snapshot.get("snapshot_type"),
        "mode": snapshot.get("mode"),
        "title": snapshot.get("title"),
        "subtitle": snapshot.get("subtitle"),
        "created_at": snapshot.get("created_at"),
        "count": snapshot.get("count"),
        "filters": snapshot.get("filters") or {},
        "stats": snapshot.get("stats") or {},
        "preview": build_preview_records(snapshot, args.preview),
    }
    if args.with_signals:
        payload["signals"] = snapshot.get("signals") or {}

    if args.json:
        print_json(payload)
    else:
        print(
            f"{payload.get('file_name')} | {payload.get('snapshot_type')} | {payload.get('mode')} "
            f"| count={payload.get('count')} | created={payload.get('created_at')}"
        )
        for item in payload["preview"]:
            print(f"[{item.get('created_at')}] {item.get('user_name') or '未知'} | {item.get('title') or '无标题'}")
    return 0


def main() -> int:
    return run(build_parser().parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
