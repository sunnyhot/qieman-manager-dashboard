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
    parser = argparse.ArgumentParser(description="读取已加入小组列表")
    parser.add_argument("--group-name", default="", help="按小组名称模糊过滤")
    parser.add_argument("--manager-name", default="", help="按主理人名称模糊过滤")
    parser.add_argument("--group-id", default="", help="按 groupId 精确过滤")
    parser.add_argument("--limit", type=int, default=100, help="返回上限")
    parser.add_argument("--cookie", default="", help="可选，原始 cookie")
    parser.add_argument("--cookie-file", default="", help="可选，cookie 文件")
    parser.add_argument("--cookie-env", default="QIEMAN_COOKIE", help="cookie 环境变量")
    parser.add_argument("--access-token", default="", help="可选，access token")
    parser.add_argument("--access-token-env", default="QIEMAN_ACCESS_TOKEN", help="access token 环境变量")
    parser.add_argument("--project-dir", default="", help="可选，项目目录")
    parser.add_argument("--json", action="store_true", help="输出 JSON")
    return parser


def filter_groups(args: argparse.Namespace, groups: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    group_name = args.group_name.strip().lower()
    manager_name = args.manager_name.strip().lower()
    group_id = args.group_id.strip()

    results: List[Dict[str, Any]] = []
    for group in groups:
        if group_name and group_name not in str(group.get("group_name") or "").lower():
            continue
        if manager_name and manager_name not in str(group.get("manager_name") or "").lower():
            continue
        if group_id and group_id != str(group.get("group_id") or ""):
            continue
        results.append(group)
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
    qcs.ensure_auth_available(client, "my-groups")
    groups = qcs.fetch_my_groups(client)
    rows = filter_groups(args, [asdict(group) for group in groups])

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
                f"groupId={item.get('group_id')} | {item.get('group_name') or '未知小组'} "
                f"| manager={item.get('manager_name') or '未知'}"
            )
    return 0


def main() -> int:
    return run(build_parser().parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
