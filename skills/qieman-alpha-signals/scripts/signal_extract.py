#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any, Dict, List

from _qieman_skill_common import (
    ensure_project_dir,
    load_dashboard_module,
    parse_json_file,
    print_json,
    resolve_project_dir,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="从 JSON 文件提取高置信交易信号")
    parser.add_argument("--json-path", default="", help="直接指定 JSON 文件路径")
    parser.add_argument("--limit-items", type=int, default=20, help="返回信号条目上限")
    parser.add_argument("--limit-assets", type=int, default=12, help="返回时间线标的上限")
    parser.add_argument("--project-dir", default="", help="可选，项目目录")
    parser.add_argument("--json", action="store_true", help="输出 JSON")
    return parser


def normalize_public_records(raw_items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    records: List[Dict[str, Any]] = []
    for index, item in enumerate(raw_items, start=1):
        if not isinstance(item, dict):
            continue
        records.append(
            {
                "post_id": item.get("post_id") or index,
                "title": item.get("title") or item.get("intro") or "",
                "intro": item.get("snippet") or item.get("intro") or "",
                "content_text": item.get("content") or item.get("content_text") or "",
                "created_at": item.get("created_at") or item.get("publish_date") or "",
                "detail_url": item.get("detail_url") or item.get("url") or "",
                "user_name": item.get("user_name") or item.get("author") or "",
                "like_count": item.get("like_count") or 0,
                "comment_count": item.get("comment_count") or 0,
            }
        )
    return records


def load_records(dashboard, args: argparse.Namespace) -> tuple[List[Dict[str, Any]], str]:
    if args.json_path.strip():
        path = Path(args.json_path).expanduser().resolve()
        raw = parse_json_file(path)
        if isinstance(raw, dict) and isinstance(raw.get("posts"), list):
            return [item for item in raw.get("posts") if isinstance(item, dict)], str(path)
        if isinstance(raw, list):
            return normalize_public_records([item for item in raw if isinstance(item, dict)]), str(path)
        raise SystemExit(f"不支持的 JSON 结构: {path}")

    raise SystemExit("请提供 --json-path")


def run(args: argparse.Namespace) -> int:
    project_dir = ensure_project_dir(resolve_project_dir(args.project_dir))
    dashboard = load_dashboard_module(project_dir)

    records, source = load_records(dashboard, args)
    signals = dashboard.build_signal_stats(records)

    payload = {
        "source": source,
        "record_count": len(records),
        "signal_count": dashboard.safe_int(signals.get("count")),
        "event_count": dashboard.safe_int(signals.get("event_count")),
        "counts": signals.get("counts") or {},
        "top_actions": (signals.get("top_actions") or [])[:6],
        "top_assets": (signals.get("top_assets") or [])[:8],
        "latest": signals.get("latest") or {},
        "items": (signals.get("items") or [])[: max(1, args.limit_items)],
        "timeline": (signals.get("timeline") or [])[: max(1, args.limit_assets)],
    }

    if args.json:
        print_json(payload)
    else:
        print(
            f"source={payload['source']} | records={payload['record_count']} | "
            f"signals={payload['signal_count']} | events={payload['event_count']}"
        )
        for item in payload["items"][:10]:
            print(f"[{item.get('created_at')}] {item.get('action')} | {item.get('title')}")
    return 0


def main() -> int:
    return run(build_parser().parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
