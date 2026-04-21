#!/usr/bin/env python3
from __future__ import annotations

import argparse

from _qieman_skill_common import ensure_project_dir, load_dashboard_module, print_json, resolve_project_dir


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="查询单帖评论")
    parser.add_argument("--post-id", type=int, required=True, help="帖子 ID")
    parser.add_argument("--sort-type", choices=("hot", "latest"), default="hot", help="排序")
    parser.add_argument("--page-num", type=int, default=1, help="页码")
    parser.add_argument("--page-size", type=int, default=10, help="每页数量")
    parser.add_argument("--manager-broker-user-id", default="", help="只保留包含此主理人回复的评论线程")
    parser.add_argument("--project-dir", default="", help="可选，项目目录")
    parser.add_argument("--json", action="store_true", help="输出 JSON")
    return parser


def run(args: argparse.Namespace) -> int:
    project_dir = ensure_project_dir(resolve_project_dir(args.project_dir))
    dashboard = load_dashboard_module(project_dir)

    payload = dashboard.fetch_post_comments(
        post_id=args.post_id,
        page_size=max(1, args.page_size),
        sort_type=args.sort_type,
        page_num=max(1, args.page_num),
        manager_broker_user_id=args.manager_broker_user_id,
    )

    if args.json:
        print_json(payload)
    else:
        print(
            f"post={payload.get('post_id')} | page={payload.get('page_num')} | "
            f"count={len(payload.get('comments') or [])} | has_more={payload.get('has_more')}"
        )
        for item in (payload.get("comments") or [])[:10]:
            print(
                f"[{item.get('created_at')}] {item.get('user_name') or '未知'} | "
                f"赞{item.get('like_count')} | {str(item.get('content') or '')[:80]}"
            )
    return 0


def main() -> int:
    return run(build_parser().parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
