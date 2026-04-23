#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from _qieman_skill_common import (
    build_community_client,
    ensure_project_dir,
    load_dashboard_module,
    load_public_module,
    resolve_project_dir,
)


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def slugify(text: str) -> str:
    base = re.sub(r"[^\w]+", "-", text.strip().lower(), flags=re.UNICODE).strip("-")
    return base or "default"


def safe_text(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip()


def safe_int(value: Any) -> int:
    try:
        if value in (None, ""):
            return 0
        return int(value)
    except Exception:
        return 0


def safe_float(value: Any) -> float:
    try:
        if value in (None, ""):
            return 0.0
        return float(value)
    except Exception:
        return 0.0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="增量监控：新调仓动作 + 新论坛发言")
    parser.add_argument("--prod-code", default="LONG_WIN", help="产品代码，默认 LONG_WIN")
    parser.add_argument("--manager-name", default="ETF拯救世界", help="主理人昵称过滤，默认 ETF拯救世界")
    parser.add_argument(
        "--forum-mode",
        choices=("auto", "following-posts", "public"),
        default="auto",
        help="论坛数据源：auto 优先 following-posts，失败回落 public",
    )
    parser.add_argument("--public-query", default="", help="public 模式查询词，默认使用 manager-name")
    parser.add_argument("--pages", type=int, default=4, help="论坛抓取页数，默认 4")
    parser.add_argument("--page-size", type=int, default=20, help="论坛每页数量，默认 20")
    parser.add_argument("--max-trades", type=int, default=120, help="调仓动作扫描上限，默认 120")
    parser.add_argument("--max-posts", type=int, default=120, help="发言扫描上限，默认 120")
    parser.add_argument("--preview", type=int, default=8, help="返回明细上限，默认 8")
    parser.add_argument("--state-file", default="", help="状态文件路径，默认 output/watch-state-*.json")
    parser.add_argument("--emit-initial", action="store_true", help="首次运行也输出当前结果，不仅建基线")
    parser.add_argument("--reset-state", action="store_true", help="重置状态文件")
    parser.add_argument("--cookie", default="", help="可选，原始 cookie（following-posts）")
    parser.add_argument("--cookie-file", default="", help="可选，cookie 文件（following-posts）")
    parser.add_argument("--cookie-env", default="QIEMAN_COOKIE", help="cookie 环境变量名")
    parser.add_argument("--access-token", default="", help="可选，access token（following-posts）")
    parser.add_argument("--access-token-env", default="QIEMAN_ACCESS_TOKEN", help="access token 环境变量名")
    parser.add_argument("--project-dir", default="", help="可选，项目目录")
    parser.add_argument("--json", action="store_true", help="输出 JSON")
    return parser


def default_state_file(project_dir: Path, prod_code: str, manager_name: str) -> Path:
    output_dir = project_dir / "output"
    output_dir.mkdir(parents=True, exist_ok=True)
    name = f"watch-state-{slugify(prod_code)}-{slugify(manager_name)}.json"
    return output_dir / name


def load_state(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    if not isinstance(payload, dict):
        return {}
    return payload


def save_state(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def trade_uid(action: Dict[str, Any]) -> str:
    key = safe_text(action.get("action_key"))
    if key:
        return key
    pieces = [
        safe_text(action.get("adjustment_id")),
        safe_text(action.get("side")),
        safe_text(action.get("fund_code")),
        safe_text(action.get("txn_date") or action.get("created_at")),
        safe_text(action.get("trade_unit")),
    ]
    return "|".join(pieces)


def post_uid(post: Dict[str, Any]) -> str:
    pid = safe_text(post.get("post_id"))
    if pid:
        return f"post:{pid}"
    url = safe_text(post.get("detail_url") or post.get("url"))
    if url:
        return f"url:{url}"
    title = safe_text(post.get("title") or post.get("intro"))
    created = safe_text(post.get("created_at") or post.get("publish_date"))
    author = safe_text(post.get("user_name") or post.get("author"))
    return f"text:{created}|{author}|{title}"


def collect_trade_events(project_dir: Path, prod_code: str, max_trades: int) -> List[Dict[str, Any]]:
    dashboard = load_dashboard_module(project_dir)
    data = dashboard.fetch_platform_trade_data(prod_code)
    if not data.get("supported"):
        reason = safe_text(data.get("error")) or "平台调仓接口不可用"
        raise RuntimeError(reason)

    actions = [row for row in list(data.get("actions") or []) if isinstance(row, dict)]
    rows: List[Dict[str, Any]] = []
    for action in actions[: max(1, max_trades)]:
        rows.append(
            {
                "uid": trade_uid(action),
                "date": safe_text(action.get("txn_date") or action.get("created_at")),
                "adjustment_id": safe_int(action.get("adjustment_id")),
                "action_title": safe_text(action.get("action_title") or action.get("action")),
                "action": safe_text(action.get("action")),
                "side": safe_text(action.get("side")),
                "fund_code": safe_text(action.get("fund_code")),
                "fund_name": safe_text(action.get("fund_name")),
                "trade_unit": safe_int(action.get("trade_unit")),
                "trade_valuation": safe_float(action.get("trade_valuation")),
                "current_valuation": safe_float(action.get("current_valuation")),
                "current_valuation_source": safe_text(action.get("current_valuation_source")),
                "valuation_change_pct": safe_float(action.get("valuation_change_pct")),
                "article_url": safe_text(action.get("article_url")),
            }
        )
    return rows


def collect_forum_events_following(
    project_dir: Path,
    manager_name: str,
    pages: int,
    page_size: int,
    max_posts: int,
    cookie: str,
    cookie_file: str,
    cookie_env: str,
    access_token: str,
    access_token_env: str,
) -> Tuple[str, List[Dict[str, Any]]]:
    qcs, client = build_community_client(
        project_dir=project_dir,
        cookie=cookie,
        cookie_file=cookie_file,
        cookie_env=cookie_env,
        access_token=access_token,
        access_token_env=access_token_env,
    )
    qcs.ensure_auth_available(client, "following-posts")
    posts = qcs.fetch_following_posts(
        client=client,
        page_size=max(1, page_size),
        pages=max(1, pages),
        broker_user_id=None,
        user_name=manager_name or None,
        keyword=None,
        since_date=None,
        until_date=None,
    )

    rows: List[Dict[str, Any]] = []
    for post in posts[: max(1, max_posts)]:
        item = asdict(post)
        row = {
            "uid": "",
            "source": "following-posts",
            "post_id": safe_int(item.get("post_id")),
            "created_at": safe_text(item.get("created_at")),
            "user_name": safe_text(item.get("user_name")),
            "title": safe_text(item.get("title") or item.get("intro")),
            "detail_url": safe_text(item.get("detail_url")),
            "like_count": safe_int(item.get("like_count")),
            "comment_count": safe_int(item.get("comment_count")),
        }
        row["uid"] = post_uid(row)
        rows.append(row)
    return "following-posts", rows


def collect_forum_events_public(
    project_dir: Path,
    manager_name: str,
    public_query: str,
    pages: int,
    max_posts: int,
) -> Tuple[str, List[Dict[str, Any]]]:
    qps = load_public_module(project_dir)
    query = safe_text(public_query) or manager_name or "长赢计划"
    author = safe_text(manager_name) or None
    opener = qps.build_opener(cookie_header=None)
    articles = qps.crawl_recent_items(
        query=query,
        author=author,
        opener=opener,
        latest_guess=18000,
        probe_window=400,
        max_pages=max(1, pages * 2),
        step=6,
        sleep_seconds=0.6,
    )

    rows: List[Dict[str, Any]] = []
    for article in articles[: max(1, max_posts)]:
        item = asdict(article)
        row = {
            "uid": "",
            "source": "public",
            "post_id": 0,
            "created_at": safe_text(item.get("publish_date")),
            "user_name": safe_text(item.get("author")),
            "title": safe_text(item.get("title") or item.get("snippet")),
            "detail_url": safe_text(item.get("url")),
            "like_count": 0,
            "comment_count": 0,
        }
        row["uid"] = post_uid(row)
        rows.append(row)
    return "public", rows


def collect_forum_events(
    project_dir: Path,
    forum_mode: str,
    manager_name: str,
    public_query: str,
    pages: int,
    page_size: int,
    max_posts: int,
    cookie: str,
    cookie_file: str,
    cookie_env: str,
    access_token: str,
    access_token_env: str,
) -> Tuple[str, List[Dict[str, Any]], Optional[str]]:
    if forum_mode == "following-posts":
        source, items = collect_forum_events_following(
            project_dir=project_dir,
            manager_name=manager_name,
            pages=pages,
            page_size=page_size,
            max_posts=max_posts,
            cookie=cookie,
            cookie_file=cookie_file,
            cookie_env=cookie_env,
            access_token=access_token,
            access_token_env=access_token_env,
        )
        return source, items, None

    if forum_mode == "public":
        source, items = collect_forum_events_public(
            project_dir=project_dir,
            manager_name=manager_name,
            public_query=public_query,
            pages=pages,
            max_posts=max_posts,
        )
        return source, items, None

    # auto
    try:
        source, items = collect_forum_events_following(
            project_dir=project_dir,
            manager_name=manager_name,
            pages=pages,
            page_size=page_size,
            max_posts=max_posts,
            cookie=cookie,
            cookie_file=cookie_file,
            cookie_env=cookie_env,
            access_token=access_token,
            access_token_env=access_token_env,
        )
        return source, items, None
    except Exception as exc:
        source, items = collect_forum_events_public(
            project_dir=project_dir,
            manager_name=manager_name,
            public_query=public_query,
            pages=pages,
            max_posts=max_posts,
        )
        return source, items, f"following-posts 不可用，已回落 public：{safe_text(exc)}"


def keep_recent_ids(rows: List[Dict[str, Any]], old_ids: List[str], limit: int = 2000) -> List[str]:
    current = [safe_text(row.get("uid")) for row in rows if safe_text(row.get("uid"))]
    merged = current + [value for value in old_ids if value not in set(current)]
    result: List[str] = []
    seen = set()
    for item in merged:
        if not item or item in seen:
            continue
        seen.add(item)
        result.append(item)
        if len(result) >= max(100, limit):
            break
    return result


def pick_updates(rows: List[Dict[str, Any]], seen_ids: set[str], preview: int) -> List[Dict[str, Any]]:
    updates = [row for row in rows if safe_text(row.get("uid")) not in seen_ids]
    return updates[: max(1, preview)]


def print_human(payload: Dict[str, Any]) -> None:
    if payload.get("initialized") and not payload.get("has_updates"):
        print(
            f"首次建基线完成：trade={payload.get('trade_total', 0)} "
            f"post={payload.get('post_total', 0)} | source={payload.get('forum_source')}"
        )
        return

    if not payload.get("has_updates"):
        print(
            f"无新增 | source={payload.get('forum_source')} "
            f"| checked_at={payload.get('checked_at')}"
        )
        return

    print(
        f"发现更新：调仓 +{payload.get('new_trade_count', 0)}，"
        f"发言 +{payload.get('new_post_count', 0)} | source={payload.get('forum_source')}"
    )
    for item in payload.get("new_trades") or []:
        print(
            f"[调仓] {safe_text(item.get('date'))} #{safe_text(item.get('adjustment_id'))} "
            f"{safe_text(item.get('action_title'))} | {safe_text(item.get('fund_name') or item.get('fund_code'))}"
        )
    for item in payload.get("new_posts") or []:
        print(
            f"[发言] {safe_text(item.get('created_at'))} "
            f"{safe_text(item.get('user_name') or '未知')} | {safe_text(item.get('title'))}"
        )


def run(args: argparse.Namespace) -> int:
    project_dir = ensure_project_dir(resolve_project_dir(args.project_dir))
    state_path = (
        Path(args.state_file).expanduser().resolve()
        if args.state_file.strip()
        else default_state_file(project_dir, args.prod_code, args.manager_name)
    )

    if args.reset_state and state_path.exists():
        state_path.unlink()

    state = load_state(state_path)
    seen_trade_ids = set(
        item for item in list(state.get("seen_trade_ids") or []) if isinstance(item, str) and item.strip()
    )
    seen_post_ids = set(
        item for item in list(state.get("seen_post_ids") or []) if isinstance(item, str) and item.strip()
    )

    trades = collect_trade_events(project_dir=project_dir, prod_code=args.prod_code, max_trades=args.max_trades)
    forum_source, posts, forum_note = collect_forum_events(
        project_dir=project_dir,
        forum_mode=args.forum_mode,
        manager_name=args.manager_name,
        public_query=args.public_query,
        pages=args.pages,
        page_size=args.page_size,
        max_posts=args.max_posts,
        cookie=args.cookie,
        cookie_file=args.cookie_file,
        cookie_env=args.cookie_env,
        access_token=args.access_token,
        access_token_env=args.access_token_env,
    )

    first_run = not state_path.exists()
    initialized = first_run and not args.emit_initial

    if initialized:
        new_trades: List[Dict[str, Any]] = []
        new_posts: List[Dict[str, Any]] = []
    else:
        new_trades = pick_updates(trades, seen_trade_ids, args.preview)
        new_posts = pick_updates(posts, seen_post_ids, args.preview)

    next_trade_ids = keep_recent_ids(trades, list(seen_trade_ids))
    next_post_ids = keep_recent_ids(posts, list(seen_post_ids))

    payload: Dict[str, Any] = {
        "checked_at": utc_now_iso(),
        "project_dir": str(project_dir),
        "state_file": str(state_path),
        "forum_source": forum_source,
        "forum_note": forum_note or "",
        "initialized": initialized,
        "emit_initial": bool(args.emit_initial),
        "has_updates": bool(new_trades or new_posts),
        "trade_total": len(trades),
        "post_total": len(posts),
        "new_trade_count": len(new_trades),
        "new_post_count": len(new_posts),
        "new_trades": new_trades,
        "new_posts": new_posts,
    }

    save_state(
        state_path,
        {
            "updated_at": payload["checked_at"],
            "forum_source": forum_source,
            "seen_trade_ids": next_trade_ids,
            "seen_post_ids": next_post_ids,
            "prod_code": args.prod_code,
            "manager_name": args.manager_name,
        },
    )

    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        print_human(payload)
    return 0


def main() -> int:
    return run(build_parser().parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
