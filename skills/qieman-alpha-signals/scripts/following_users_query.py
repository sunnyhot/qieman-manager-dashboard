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
    parser = argparse.ArgumentParser(description="读取关注用户列表（主理人列表）")
    parser.add_argument("--pages", type=int, default=5, help="抓取页数")
    parser.add_argument("--page-size", type=int, default=50, help="每页数量")
    parser.add_argument("--user-name", default="", help="按昵称过滤")
    parser.add_argument("--broker-user-id", default="", help="按 brokerUserId 过滤")
    parser.add_argument("--space-user-id", default="", help="按 spaceUserId 过滤")
    parser.add_argument("--limit", type=int, default=100, help="返回上限")
    parser.add_argument("--cookie", default="", help="可选，原始 cookie")
    parser.add_argument("--cookie-file", default="", help="可选，cookie 文件")
    parser.add_argument("--cookie-env", default="QIEMAN_COOKIE", help="cookie 环境变量")
    parser.add_argument("--access-token", default="", help="可选，access token")
    parser.add_argument("--access-token-env", default="QIEMAN_ACCESS_TOKEN", help="access token 环境变量")
    parser.add_argument("--project-dir", default="", help="可选，项目目录")
    parser.add_argument("--json", action="store_true", help="输出 JSON")
    return parser


def filter_users(args: argparse.Namespace, users: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    user_name = args.user_name.strip().lower()
    broker_user_id = args.broker_user_id.strip()
    space_user_id = args.space_user_id.strip()
    results: List[Dict[str, Any]] = []
    for user in users:
        if user_name and user_name not in str(user.get("user_name") or "").lower():
            continue
        if broker_user_id and broker_user_id != str(user.get("broker_user_id") or ""):
            continue
        if space_user_id and space_user_id != str(user.get("space_user_id") or ""):
            continue
        results.append(user)
        if len(results) >= max(1, args.limit):
            break
    return results


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
    qcs.ensure_auth_available(client, "following-users")
    users = qcs.fetch_following_users(
        client=client,
        page_size=max(1, args.page_size),
        pages=max(1, args.pages),
    )
    rows = filter_users(args, [asdict(user) for user in users])

    payload = {
        "count": len(rows),
        "items": rows,
    }
    if args.json:
        print_json(payload)
    else:
        print(f"count={payload['count']}")
        for item in rows:
            print(
                f"{item.get('user_name') or '未知'} | broker={item.get('broker_user_id') or '未知'} "
                f"| space={item.get('space_user_id') or '未知'} | {item.get('user_label') or '无标签'}"
            )
    return 0


def main() -> int:
    return run(build_parser().parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
