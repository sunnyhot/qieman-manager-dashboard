#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import asdict
from typing import Any, Dict, List

from _qieman_skill_common import (
    build_community_client,
    ensure_project_dir,
    print_json,
    resolve_project_dir,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="查询关注动态（following-posts）")
    parser.add_argument("--user-name", default="", help="按用户昵称过滤")
    parser.add_argument("--broker-user-id", default="", help="按 brokerUserId 过滤")
    parser.add_argument("--keyword", default="", help="关键词过滤")
    parser.add_argument("--since", default="", help="起始日期 YYYY-MM-DD")
    parser.add_argument("--until", default="", help="结束日期 YYYY-MM-DD")
    parser.add_argument("--pages", type=int, default=5, help="抓取页数")
    parser.add_argument("--page-size", type=int, default=20, help="每页数量")
    parser.add_argument("--limit", type=int, default=100, help="返回上限")
    parser.add_argument("--cookie", default="", help="可选，原始 cookie")
    parser.add_argument("--cookie-file", default="", help="可选，cookie 文件")
    parser.add_argument("--cookie-env", default="QIEMAN_COOKIE", help="cookie 环境变量")
    parser.add_argument("--access-token", default="", help="可选，access token")
    parser.add_argument("--access-token-env", default="QIEMAN_ACCESS_TOKEN", help="access token 环境变量")
    parser.add_argument("--project-dir", default="", help="可选，项目目录")
    parser.add_argument("--json", action="store_true", help="输出 JSON")
    parser.add_argument("--include-content", action="store_true", help="包含正文 content_text")
    return parser


def to_rows(posts: List[Any], include_content: bool, limit: int) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    for post in posts:
        item = asdict(post)
        row: Dict[str, Any] = {
            "post_id": item.get("post_id"),
            "group_id": item.get("group_id"),
            "group_name": item.get("group_name"),
            "broker_user_id": item.get("broker_user_id"),
            "user_name": item.get("user_name"),
            "user_label": item.get("user_label"),
            "created_at": item.get("created_at"),
            "title": item.get("title") or item.get("intro"),
            "like_count": item.get("like_count"),
            "comment_count": item.get("comment_count"),
            "detail_url": item.get("detail_url"),
        }
        if include_content:
            row["content_text"] = item.get("content_text")
        rows.append(row)
        if len(rows) >= max(1, limit):
            break
    return rows


def run(args: argparse.Namespace) -> int:
    project_dir = ensure_project_dir(resolve_project_dir(args.project_dir))
    qcs, client = build_community_client(
        project_dir=project_dir,
        cookie=args.cookie,
        cookie_file=args.cookie_file,
        cookie_env=args.cookie_env,
        access_token=args.access_token,
        access_token_env=args.access_token_env,
    )
    qcs.ensure_auth_available(client, "following-posts")
    since_date = qcs.parse_date_arg(args.since or None, "--since")
    until_date = qcs.parse_date_arg(args.until or None, "--until")

    posts = qcs.fetch_following_posts(
        client=client,
        page_size=max(1, args.page_size),
        pages=max(1, args.pages),
        broker_user_id=args.broker_user_id or None,
        user_name=args.user_name or None,
        keyword=args.keyword or None,
        since_date=since_date,
        until_date=until_date,
    )
    rows = to_rows(posts, include_content=args.include_content, limit=args.limit)
    payload = {
        "count": len(rows),
        "items": rows,
    }

    if args.json:
        print_json(payload)
    else:
        print(f"count={payload['count']}")
        for item in rows:
            print(f"[{item.get('created_at')}] {item.get('user_name') or '未知'} | {item.get('title') or '无标题'}")
    return 0


def main() -> int:
    return run(build_parser().parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
