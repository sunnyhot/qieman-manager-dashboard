#!/usr/bin/env python3
from __future__ import annotations

import argparse

from _qieman_skill_common import (
    build_community_client,
    ensure_project_dir,
    print_json,
    resolve_project_dir,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="检查且慢登录态并返回当前用户信息")
    parser.add_argument("--cookie", default="", help="可选，原始 cookie")
    parser.add_argument("--cookie-file", default="", help="可选，cookie 文件")
    parser.add_argument("--cookie-env", default="QIEMAN_COOKIE", help="cookie 环境变量名")
    parser.add_argument("--access-token", default="", help="可选，直接传 access token")
    parser.add_argument("--access-token-env", default="QIEMAN_ACCESS_TOKEN", help="access token 环境变量名")
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

    try:
        qcs.ensure_auth_available(client, "auth-check")
        user = qcs.fetch_auth_user_info(client)
        payload = {
            "ok": True,
            "user_name": user.user_name,
            "broker_user_id": user.broker_user_id,
            "user_label": user.user_label,
            "user_avatar_url": user.user_avatar_url,
        }
    except Exception as exc:
        payload = {
            "ok": False,
            "error": str(exc),
            "user_name": "",
            "broker_user_id": "",
            "user_label": "",
            "user_avatar_url": "",
        }

    if args.json:
        print_json(payload)
    else:
        print(
            f"ok={payload['ok']} | user={payload['user_name'] or '未知'} "
            f"| brokerUserId={payload['broker_user_id'] or '未知'} | label={payload['user_label'] or '未知'}"
        )
        if not payload["ok"]:
            print(f"error: {payload['error']}")
    return 0


def main() -> int:
    return run(build_parser().parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
