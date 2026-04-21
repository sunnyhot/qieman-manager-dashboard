#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import asdict
from typing import Any, Dict, List

from _qieman_skill_common import ensure_project_dir, load_public_module, print_json, resolve_project_dir


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="查询且慢公开内容（非登录态）")
    parser.add_argument("--query", required=True, help="搜索关键词")
    parser.add_argument("--author", default="", help="按作者过滤")
    parser.add_argument("--limit", type=int, default=40, help="最多扫描多少篇")
    parser.add_argument("--latest-guess", type=int, default=18000, help="最近 itemId 猜测值")
    parser.add_argument("--probe-window", type=int, default=400, help="探测窗口")
    parser.add_argument("--step", type=int, default=6, help="itemId 步长")
    parser.add_argument("--sleep", type=float, default=0.6, help="请求间隔秒")
    parser.add_argument("--cookie", default="", help="可选 cookie")
    parser.add_argument("--preview", type=int, default=20, help="返回上限")
    parser.add_argument("--project-dir", default="", help="可选，项目目录")
    parser.add_argument("--json", action="store_true", help="输出 JSON")
    parser.add_argument("--include-content", action="store_true", help="包含正文")
    return parser


def run(args: argparse.Namespace) -> int:
    project_dir = ensure_project_dir(resolve_project_dir(args.project_dir))
    qps = load_public_module(project_dir)

    opener = qps.build_opener(cookie_header=args.cookie or None)
    articles = qps.crawl_recent_items(
        query=args.query,
        author=args.author or None,
        opener=opener,
        latest_guess=max(100, args.latest_guess),
        probe_window=max(20, args.probe_window),
        max_pages=max(1, args.limit),
        step=max(1, args.step),
        sleep_seconds=max(0.0, args.sleep),
    )

    rows: List[Dict[str, Any]] = []
    for article in articles[: max(1, args.preview)]:
        item = asdict(article)
        row: Dict[str, Any] = {
            "query": item.get("query"),
            "title": item.get("title"),
            "author": item.get("author"),
            "publish_date": item.get("publish_date"),
            "url": item.get("url"),
            "source": item.get("source"),
            "snippet": item.get("snippet"),
        }
        if args.include_content:
            row["content"] = item.get("content")
        rows.append(row)

    payload = {
        "count": len(rows),
        "items": rows,
    }
    if args.json:
        print_json(payload)
    else:
        print(f"count={payload['count']}")
        for item in rows:
            print(f"[{item.get('publish_date')}] {item.get('author') or '未知'} | {item.get('title') or '无标题'}")
    return 0


def main() -> int:
    return run(build_parser().parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
