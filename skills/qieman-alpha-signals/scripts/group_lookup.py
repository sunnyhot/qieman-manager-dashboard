#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import asdict

from _qieman_skill_common import (
    build_community_client,
    ensure_project_dir,
    print_json,
    resolve_project_dir,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="按多种输入解析 groupId，并可拉取 group 信息")
    parser.add_argument("--group-id", type=int, default=0, help="直接指定 groupId")
    parser.add_argument("--group-url", default="", help="group-detail URL")
    parser.add_argument("--prod-code", default="", help="产品代码，例如 LONG_WIN")
    parser.add_argument("--manager-name", default="", help="主理人名字")
    parser.add_argument("--with-group-info", action="store_true", help="额外返回 group 概要")
    parser.add_argument("--cookie", default="", help="可选，原始 cookie")
    parser.add_argument("--cookie-file", default="", help="可选，cookie 文件")
    parser.add_argument("--cookie-env", default="QIEMAN_COOKIE", help="cookie 环境变量")
    parser.add_argument("--access-token", default="", help="可选，access token")
    parser.add_argument("--access-token-env", default="QIEMAN_ACCESS_TOKEN", help="access token 环境变量")
    parser.add_argument("--project-dir", default="", help="可选，项目目录")
    parser.add_argument("--json", action="store_true", help="输出 JSON")
    return parser


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

    source = ""
    group_id = 0
    if args.group_id:
        group_id = args.group_id
        source = "group-id"
    elif args.group_url.strip():
        group_id = int(qcs.resolve_group_id_from_url(args.group_url.strip()) or 0)
        source = "group-url"
    elif args.prod_code.strip():
        group_id = int(qcs.resolve_group_id_from_prod_code(client, args.prod_code.strip()) or 0)
        source = "prod-code"
    elif args.manager_name.strip():
        group_id = int(qcs.resolve_group_id_from_manager_name(client, args.manager_name.strip()) or 0)
        source = "manager-name"

    if not group_id:
        raise SystemExit("无法解析 groupId，请提供 --group-id/--group-url/--prod-code/--manager-name")

    payload = {
        "group_id": group_id,
        "source": source,
    }
    if args.with_group_info:
        group = qcs.fetch_group_info(client, group_id, source)
        payload["group"] = asdict(group)

    if args.json:
        print_json(payload)
    else:
        print(f"groupId={group_id} | source={source}")
        if payload.get("group"):
            group = payload["group"]
            print(f"group={group.get('group_name') or '未知'} | manager={group.get('manager_name') or '未知'}")
    return 0


def main() -> int:
    return run(build_parser().parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
