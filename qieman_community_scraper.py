#!/usr/bin/env python3
"""
Scrape Qieman community manager feeds and login-only following feeds.

This script uses the same request-signing approach as Qieman's web client:
- x-sign
- x-request-id
- sensors-anonymous-id

Supported modes:
1. group-manager: public manager posts in a community group
2. following-posts: login-only following feed
3. following-users: login-only followed-user list
4. auth-check: verify whether the provided cookie/token is valid
5. my-groups: login-only joined-group list
6. space-items: personal space activity feed

Examples:
    python3 qieman_community_scraper.py --prod-code LONG_WIN --markdown
    python3 qieman_community_scraper.py --mode following-posts --cookie-file qieman.cookie --user-name "ETF拯救世界"
    python3 qieman_community_scraper.py --mode auth-check --cookie-file qieman.cookie
    python3 qieman_community_scraper.py --mode my-groups --cookie-file qieman.cookie
    python3 qieman_community_scraper.py --mode space-items --space-user-id 123456 --markdown
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import random
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import asdict, dataclass
from datetime import date, datetime
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional


USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0.0.0 Safari/537.36"
)
BASE_URL = "https://qieman.com"
API_BASE = "/pmdj/v2"
DEFAULT_OUTPUT_DIR = Path("/Users/xufan65/Documents/Codex/2026-04-17-new-chat/output")
GROUP_ID_RE = re.compile(r"group-detail/(\d+)")


@dataclass
class GroupInfo:
    group_id: int
    group_name: str
    group_desc: str
    group_rule: str
    manager_name: str
    manager_label: str
    manager_broker_user_id: str
    manager_avatar_url: str
    source: str


@dataclass
class CommunityPost:
    group_id: int
    group_name: str
    post_id: int
    broker_user_id: str
    user_name: str
    user_label: str
    created_at: str
    title: str
    intro: str
    content_text: str
    like_count: int
    comment_count: int
    collection_count: int
    post_type: int
    detail_url: str


@dataclass
class AuthUserInfo:
    user_name: str
    user_label: str
    broker_user_id: str
    user_avatar_url: str


@dataclass
class FollowedUser:
    broker_user_id: str
    space_user_id: str
    user_name: str
    user_label: str
    user_desc: str
    user_avatar_url: str


@dataclass
class SpaceUserInfo:
    space_user_id: str
    broker_user_id: str
    user_name: str
    user_label: str
    user_desc: str
    user_avatar_url: str


class QiemanApiError(RuntimeError):
    def __init__(
        self,
        *,
        status: int,
        code: str,
        message: str,
        detail_message: str = "",
    ) -> None:
        self.status = status
        self.code = code
        self.message = message
        self.detail_message = detail_message
        super().__init__(self.describe())

    def describe(self) -> str:
        parts = [
            f"HTTP {self.status}",
            f"code={self.code or 'unknown'}",
            self.message or "未知错误",
        ]
        if self.detail_message:
            parts.append(self.detail_message)
        return " | ".join(parts)


class QiemanCommunityClient:
    def __init__(self, access_token: Optional[str] = None, cookie: Optional[str] = None):
        self.access_token = access_token or extract_access_token(cookie or "")
        self.cookie = cookie
        self.anonymous_id = "anon-" + sha256_hex(str(time.time()))[:16]

    def _headers(self, path_with_query: str) -> Dict[str, str]:
        headers = {
            "User-Agent": USER_AGENT,
            "Accept": "application/json",
            "Cache-Control": "no-store",
            "x-sign": make_x_sign(),
            "x-request-id": make_x_request_id(path_with_query, self.anonymous_id),
            "sensors-anonymous-id": self.anonymous_id,
        }
        if self.access_token:
            headers["Authorization"] = f"Bearer {self.access_token}"
        if self.cookie:
            headers["Cookie"] = self.cookie
        return headers

    def get(self, path: str, params: Optional[Dict[str, Any]] = None) -> Any:
        query = ""
        if params:
            query = "?" + urllib.parse.urlencode(
                {key: value for key, value in params.items() if value is not None}
            )
        full_path = f"{API_BASE}{path}{query}"
        request = urllib.request.Request(BASE_URL + full_path, headers=self._headers(full_path))
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                payload = json.loads(response.read().decode("utf-8", errors="ignore"))
        except urllib.error.HTTPError as exc:
            raise parse_http_error(exc) from exc
        raise_if_api_error(payload, status=200)
        return payload


def sha256_hex(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def make_x_sign() -> str:
    now = int(time.time() * 1000)
    return f"{now}{sha256_hex(str(int(1.01 * now))).upper()[:32]}"


def make_x_request_id(path_with_query: str, anonymous_id: str) -> str:
    now = int(time.time() * 1000)
    seed = f"{random.random()}{now}{path_with_query}{anonymous_id}"
    return "albus." + sha256_hex(seed)[-20:].upper()


def extract_access_token(cookie: str) -> Optional[str]:
    if not cookie:
        return None
    for chunk in cookie.split(";"):
        key, _, value = chunk.strip().partition("=")
        if key == "access_token" and value:
            return value
    return None


def decode_jwt_payload(token: str) -> Dict[str, Any]:
    if not token or token.count(".") < 2:
        return {}
    try:
        payload = token.split(".")[1]
        padding = "=" * (-len(payload) % 4)
        raw = base64.urlsafe_b64decode(payload + padding)
        data = json.loads(raw.decode("utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def parse_http_error(exc: urllib.error.HTTPError) -> QiemanApiError:
    body = exc.read().decode("utf-8", errors="ignore")
    try:
        payload = json.loads(body)
    except json.JSONDecodeError:
        return QiemanApiError(
            status=exc.code,
            code=str(exc.code),
            message=body[:200] or exc.reason,
        )
    return build_api_error(payload, status=exc.code)


def build_api_error(payload: Any, status: int) -> QiemanApiError:
    if isinstance(payload, dict):
        detail = payload.get("detail")
        detail_message = ""
        if isinstance(detail, dict):
            detail_message = clean_text(detail.get("msg") or detail.get("message"))
        elif detail:
            detail_message = clean_text(detail)
        return QiemanApiError(
            status=status,
            code=clean_text(payload.get("code")),
            message=clean_text(payload.get("msg") or payload.get("message")),
            detail_message=detail_message,
        )
    return QiemanApiError(status=status, code=str(status), message=clean_text(payload))


def raise_if_api_error(payload: Any, status: int) -> None:
    if not isinstance(payload, dict):
        return
    code = clean_text(payload.get("code"))
    if code and code not in {"0", "200"}:
        raise build_api_error(payload, status=status)


def clean_text(value: Any) -> str:
    if value is None:
        return ""
    return str(value).replace("\r\n", "\n").replace("\r", "\n").strip()


def strip_post_content(contents: List[Dict[str, Any]]) -> str:
    parts: List[str] = []
    for item in contents or []:
        detail = clean_text(item.get("detail"))
        if detail:
            parts.append(detail)
    return "\n\n".join(parts).strip()


def make_post_detail_url(post_id: int) -> str:
    return f"{BASE_URL}/content/post-detail/{post_id}"


def safe_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def extract_items(payload: Any) -> List[Dict[str, Any]]:
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    if not isinstance(payload, dict):
        return []
    for key in (
        "data",
        "content",
        "items",
        "list",
        "records",
        "rows",
        "recommendUserList",
        "result",
    ):
        value = payload.get(key)
        if isinstance(value, list):
            return [item for item in value if isinstance(item, dict)]
        if isinstance(value, dict):
            nested = extract_items(value)
            if nested:
                return nested
    return []


def extract_cursor(payload: Any) -> Optional[str]:
    if not isinstance(payload, dict):
        return None
    for key in ("pageId", "nextPageId", "nextCursor", "cursor"):
        value = clean_text(payload.get(key))
        if value:
            return value
    for key in ("data", "content", "result"):
        value = payload.get(key)
        if isinstance(value, dict):
            nested = extract_cursor(value)
            if nested:
                return nested
    return None


def parse_post_item(item: Dict[str, Any], default_group: Optional[GroupInfo] = None) -> CommunityPost:
    content = item.get("content") if isinstance(item.get("content"), dict) else {}
    group_info = item.get("groupInfo") if isinstance(item.get("groupInfo"), dict) else {}
    contents = content.get("contents") if isinstance(content.get("contents"), list) else []
    post_id = safe_int(item.get("id") or item.get("postId"))
    broker_user_id = clean_text(item.get("brokerUserId"))
    default_group_id = default_group.group_id if default_group else 0
    default_group_name = default_group.group_name if default_group else ""
    default_manager_name = default_group.manager_name if default_group else ""
    default_manager_id = default_group.manager_broker_user_id if default_group else ""
    return CommunityPost(
        group_id=safe_int(group_info.get("groupId"), default_group_id),
        group_name=clean_text(group_info.get("groupName")) or default_group_name,
        post_id=post_id,
        broker_user_id=broker_user_id,
        user_name=clean_text(item.get("userName"))
        or (default_manager_name if broker_user_id == default_manager_id else ""),
        user_label=clean_text(item.get("userLabel")),
        created_at=clean_text(item.get("createdAt")),
        title=clean_text(content.get("title")) or clean_text(item.get("title")),
        intro=clean_text(content.get("intro")) or clean_text(item.get("intro")),
        content_text=strip_post_content(contents) or clean_text(item.get("richContent")),
        like_count=safe_int(item.get("likeNum")),
        comment_count=safe_int(item.get("commentNum")),
        collection_count=safe_int(item.get("collectionCount")),
        post_type=safe_int(item.get("type") or item.get("postType")),
        detail_url=clean_text(item.get("url")) or make_post_detail_url(post_id),
    )


def parse_date_arg(value: Optional[str], flag_name: str) -> Optional[date]:
    if not value:
        return None
    try:
        return datetime.strptime(value, "%Y-%m-%d").date()
    except ValueError as exc:
        raise SystemExit(f"{flag_name} 需要使用 YYYY-MM-DD 格式，例如 2026-04-17") from exc


def parse_post_date(value: str) -> Optional[date]:
    text = clean_text(value)
    if len(text) < 10:
        return None
    try:
        return datetime.strptime(text[:10], "%Y-%m-%d").date()
    except ValueError:
        return None


def post_matches_filters(
    post: CommunityPost,
    keyword: Optional[str],
    since_date: Optional[date],
    until_date: Optional[date],
) -> bool:
    keyword_filter = (keyword or "").lower()
    if keyword_filter:
        haystack = "\n".join([post.title, post.intro, post.content_text]).lower()
        if keyword_filter not in haystack:
            return False
    post_date = parse_post_date(post.created_at)
    if since_date and post_date and post_date < since_date:
        return False
    if until_date and post_date and post_date > until_date:
        return False
    return True


def resolve_date_filters(args: argparse.Namespace) -> tuple[Optional[date], Optional[date]]:
    since_date = parse_date_arg(args.since, "--since")
    until_date = parse_date_arg(args.until, "--until")
    if since_date and until_date and since_date > until_date:
        raise SystemExit("--since 不能晚于 --until")
    return since_date, until_date


def resolve_cookie(args: argparse.Namespace) -> Optional[str]:
    if args.cookie:
        return args.cookie.strip()
    if args.cookie_file:
        return args.cookie_file.read_text(encoding="utf-8").strip()
    if args.cookie_env:
        value = os.getenv(args.cookie_env, "").strip()
        if value:
            return value
    return None


def resolve_access_token(args: argparse.Namespace, cookie: Optional[str]) -> Optional[str]:
    if args.access_token:
        return args.access_token.strip()
    if args.access_token_env:
        value = os.getenv(args.access_token_env, "").strip()
        if value:
            return value
    return extract_access_token(cookie or "")


def ensure_auth_available(client: QiemanCommunityClient, mode: str) -> None:
    if client.access_token or client.cookie:
        return
    raise SystemExit(
        f"{mode} 模式需要登录态。请通过 --cookie、--cookie-file、环境变量 QIEMAN_COOKIE，"
        "或 --access-token 提供认证信息。"
    )


def resolve_group_id_from_url(group_url: str) -> Optional[int]:
    match = GROUP_ID_RE.search(group_url)
    return int(match.group(1)) if match else None


def resolve_group_id_from_prod_code(
    client: QiemanCommunityClient, prod_code: str
) -> Optional[int]:
    config = client.get("/community/config", {"prodCode": prod_code})
    entrance = config.get("caAssetDetailEntrance") or {}
    return resolve_group_id_from_url(clean_text(entrance.get("communityUrl")))


def resolve_group_id_from_manager_name(
    client: QiemanCommunityClient, manager_name: str
) -> Optional[int]:
    for page in range(1, 11):
        awesome = client.get("/community/group/awesome-list", {"page": page, "size": 50})
        groups = awesome.get("data", [])
        if not groups:
            break
        for group in groups:
            group_id = group.get("groupId")
            if not group_id:
                continue
            manager = client.get("/community/group/manager-info", {"groupId": group_id})
            leader = (manager.get("groupLeaderInfo") or {}).get("leader") or {}
            if manager_name.lower() in clean_text(leader.get("userName")).lower():
                return int(group_id)
    return None


def fetch_group_info(client: QiemanCommunityClient, group_id: int, source: str) -> GroupInfo:
    summary = client.get("/community/group/summary", {"groupId": group_id})
    manager_info = client.get("/community/group/manager-info", {"groupId": group_id})
    leader = (manager_info.get("groupLeaderInfo") or {}).get("leader") or {}
    return GroupInfo(
        group_id=group_id,
        group_name=clean_text(summary.get("groupName")),
        group_desc=clean_text(summary.get("groupDesc")),
        group_rule=clean_text(summary.get("groupRule")),
        manager_name=clean_text(leader.get("userName")),
        manager_label=clean_text(leader.get("userLabel")),
        manager_broker_user_id=clean_text(leader.get("brokerUserId")),
        manager_avatar_url=clean_text(leader.get("userAvatarUrl")),
        source=source,
    )


def fetch_group_posts(
    client: QiemanCommunityClient,
    group: GroupInfo,
    page_size: int,
    pages: int,
    only_manager: bool,
    broker_user_id: Optional[str],
    keyword: Optional[str],
    since_date: Optional[date],
    until_date: Optional[date],
) -> List[CommunityPost]:
    posts: List[CommunityPost] = []
    target_user_id = broker_user_id or group.manager_broker_user_id
    for page_num in range(1, pages + 1):
        payload = client.get(
            "/community/post/list",
            {
                "pageNum": page_num,
                "pageSize": page_size,
                "groupId": group.group_id,
                "postType": 1,
                "queryStrategy": "ONLY_GROUP_POST",
                "orderBy": "TIME",
            },
        )
        items = payload.get("data") if isinstance(payload, dict) else payload
        if not items:
            break
        for item in items:
            post = parse_post_item(item, default_group=group)
            post_user_id = post.broker_user_id
            if only_manager and target_user_id and post_user_id != target_user_id:
                continue
            if not post_matches_filters(post, keyword, since_date, until_date):
                continue
            posts.append(post)
        time.sleep(0.2)
    return posts


def fetch_auth_user_info(client: QiemanCommunityClient) -> AuthUserInfo:
    payload = client.get("/community/auth-user-info")
    if isinstance(payload, dict):
        for key in ("data", "userInfo", "user"):
            value = payload.get(key)
            if isinstance(value, dict):
                payload = value
                break
    if not isinstance(payload, dict):
        payload = {}
    token_payload = decode_jwt_payload(client.access_token or "")
    return AuthUserInfo(
        user_name=clean_text(payload.get("userName")),
        user_label=clean_text(payload.get("userLabel")),
        broker_user_id=clean_text(payload.get("brokerUserId") or token_payload.get("sub")),
        user_avatar_url=clean_text(payload.get("userAvatarUrl")),
    )


def fetch_following_posts(
    client: QiemanCommunityClient,
    page_size: int,
    pages: int,
    broker_user_id: Optional[str],
    user_name: Optional[str],
    keyword: Optional[str],
    since_date: Optional[date],
    until_date: Optional[date],
) -> List[CommunityPost]:
    posts: List[CommunityPost] = []
    page_id: Optional[str] = None
    user_name_filter = (user_name or "").lower()
    for _ in range(pages):
        params: Dict[str, Any] = {"size": page_size}
        if page_id:
            params["pageId"] = page_id
        payload = client.get("/community/follow/following/post/list", params)
        items = extract_items(payload)
        if not items:
            break
        for item in items:
            post = parse_post_item(item)
            if broker_user_id and post.broker_user_id != broker_user_id:
                continue
            if user_name_filter and user_name_filter not in post.user_name.lower():
                continue
            if not post_matches_filters(post, keyword, since_date, until_date):
                continue
            posts.append(post)
        next_page_id = extract_cursor(payload)
        if not next_page_id or next_page_id == page_id:
            break
        page_id = next_page_id
        time.sleep(0.2)
    return posts


def fetch_following_users(
    client: QiemanCommunityClient,
    page_size: int,
    pages: int,
) -> List[FollowedUser]:
    users: List[FollowedUser] = []
    for page in range(1, pages + 1):
        payload = client.get("/community/follow/page/user", {"page": page, "size": page_size})
        items = extract_items(payload)
        if not items:
            break
        for item in items:
            users.append(
                FollowedUser(
                    broker_user_id=clean_text(item.get("brokerUserId")),
                    space_user_id=clean_text(item.get("spaceUserId") or item.get("userId")),
                    user_name=clean_text(item.get("userName")),
                    user_label=clean_text(item.get("userLabel")),
                    user_desc=clean_text(item.get("userDesc")),
                    user_avatar_url=clean_text(item.get("userAvatarUrl")),
                )
            )
        time.sleep(0.2)
    return users


def fetch_my_groups(client: QiemanCommunityClient) -> List[GroupInfo]:
    payload = client.get("/community/group/my-groups")
    items = extract_items(payload)
    group_ids: List[int] = []
    seen: set[int] = set()
    for item in items:
        group_id = safe_int(item.get("groupId") or item.get("id"))
        if not group_id or group_id in seen:
            continue
        group_ids.append(group_id)
        seen.add(group_id)
    groups: List[GroupInfo] = []
    for group_id in group_ids:
        groups.append(fetch_group_info(client, group_id, "my-groups"))
        time.sleep(0.2)
    return groups


def fetch_space_user_info(client: QiemanCommunityClient, space_user_id: str) -> SpaceUserInfo:
    payload = client.get("/community/space/userInfo", {"spaceUserId": space_user_id})
    if isinstance(payload, dict):
        for key in ("data", "userInfo", "user", "content"):
            value = payload.get(key)
            if isinstance(value, dict):
                payload = value
                break
    if not isinstance(payload, dict):
        raise SystemExit("无法解析个人空间信息。")
    return SpaceUserInfo(
        space_user_id=clean_text(payload.get("spaceUserId") or space_user_id),
        broker_user_id=clean_text(payload.get("brokerUserId") or payload.get("userId")),
        user_name=clean_text(payload.get("userName")),
        user_label=clean_text(payload.get("userLabel")),
        user_desc=clean_text(payload.get("userDesc")),
        user_avatar_url=clean_text(payload.get("userAvatarUrl")),
    )


def resolve_space_user_id(
    args: argparse.Namespace,
    client: QiemanCommunityClient,
) -> str:
    if args.space_user_id:
        return args.space_user_id
    if not (args.user_name or args.broker_user_id):
        raise SystemExit(
            "space-items 模式请提供 --space-user-id；如果你已登录，也可以传 --user-name 或 --broker-user-id 自动反查。"
        )
    ensure_auth_available(client, args.mode)
    users = fetch_following_users(
        client=client,
        page_size=max(args.page_size, 50),
        pages=max(args.pages, 10),
    )
    for user in users:
        if args.broker_user_id and user.broker_user_id == args.broker_user_id:
            return user.space_user_id
        if args.user_name and args.user_name.lower() in user.user_name.lower():
            return user.space_user_id
    raise SystemExit("没能在你的关注列表里解析到目标 spaceUserId，请先跑 following-users 看一下导出结果。")


def fetch_space_items(
    client: QiemanCommunityClient,
    space_user_id: str,
    page_size: int,
    pages: int,
    keyword: Optional[str],
    since_date: Optional[date],
    until_date: Optional[date],
) -> List[CommunityPost]:
    posts: List[CommunityPost] = []
    for page in range(1, pages + 1):
        payload = client.get(
            "/community/space/items",
            {"spaceUserId": space_user_id, "page": page, "size": page_size},
        )
        items = extract_items(payload)
        if not items:
            break
        for item in items:
            post = parse_post_item(item)
            if not post_matches_filters(post, keyword, since_date, until_date):
                continue
            posts.append(post)
        time.sleep(0.2)
    return posts


def save_json(
    path: Path,
    group: GroupInfo,
    posts: Iterable[CommunityPost],
    filters: Optional[Dict[str, Any]] = None,
) -> None:
    payload = {
        "group": asdict(group),
        "filters": filters or {},
        "posts": [asdict(post) for post in posts],
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def save_markdown(
    path: Path,
    group: GroupInfo,
    posts: Iterable[CommunityPost],
    filters: Optional[Dict[str, Any]] = None,
) -> None:
    lines = [
        f"# {group.group_name}",
        "",
        f"- groupId: {group.group_id}",
        f"- 主理人: {group.manager_name or '未知'}",
        f"- 主理人标签: {group.manager_label or '未知'}",
        f"- brokerUserId: {group.manager_broker_user_id or '未知'}",
        f"- 来源: {group.source}",
    ]
    if filters:
        lines.extend(
            [
                f"- 过滤 keyword: {clean_text(filters.get('keyword')) or '未设置'}",
                f"- 过滤 since: {clean_text(filters.get('since')) or '未设置'}",
                f"- 过滤 until: {clean_text(filters.get('until')) or '未设置'}",
            ]
        )
    lines.extend(["", group.group_desc, ""])
    for index, post in enumerate(posts, start=1):
        lines.extend(
            [
                f"## {index}. {post.title or post.intro or f'帖子 {post.post_id}'}",
                "",
                f"- postId: {post.post_id}",
                f"- userId: {post.broker_user_id}",
                f"- 时间: {post.created_at}",
                f"- 点赞: {post.like_count}",
                f"- 评论: {post.comment_count}",
                f"- 收藏: {post.collection_count}",
                f"- 链接: {post.detail_url}",
                "",
                post.content_text or post.intro or "无正文",
                "",
            ]
        )
    path.write_text("\n".join(lines).strip() + "\n", encoding="utf-8")


def slugify(text: str) -> str:
    value = re.sub(r"[^\w\u4e00-\u9fff-]+", "-", text.strip(), flags=re.U)
    value = re.sub(r"-{2,}", "-", value).strip("-")
    return value or "qieman-community"


def make_output_timestamp() -> str:
    return datetime.now().strftime("%Y%m%d-%H%M%S-%f")


def resolve_group_id(args: argparse.Namespace, client: QiemanCommunityClient) -> tuple[int, str]:
    if args.group_id:
        return args.group_id, "group-id"
    if args.group_url:
        group_id = resolve_group_id_from_url(args.group_url)
        if group_id:
            return group_id, "group-url"
    if args.prod_code:
        group_id = resolve_group_id_from_prod_code(client, args.prod_code)
        if group_id:
            return group_id, "prod-code"
    if args.manager_name:
        group_id = resolve_group_id_from_manager_name(client, args.manager_name)
        if group_id:
            return group_id, "manager-name"
    raise SystemExit("无法解析 groupId。请提供 --group-id、--group-url、--prod-code 或更明确的 --manager-name。")


def save_feed_json(
    path: Path,
    meta: Dict[str, Any],
    posts: Iterable[CommunityPost],
) -> None:
    payload = {
        "meta": meta,
        "posts": [asdict(post) for post in posts],
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def save_feed_markdown(path: Path, title: str, summary_lines: List[str], posts: Iterable[CommunityPost]) -> None:
    lines = [f"# {title}", ""]
    lines.extend(summary_lines)
    lines.append("")
    for index, post in enumerate(posts, start=1):
        lines.extend(
            [
                f"## {index}. {post.title or post.intro or f'帖子 {post.post_id}'}",
                "",
                f"- postId: {post.post_id}",
                f"- 用户: {post.user_name or '未知'}",
                f"- brokerUserId: {post.broker_user_id or '未知'}",
                f"- 标签: {post.user_label or '未知'}",
                f"- 小组: {post.group_name or '未知'}",
                f"- 时间: {post.created_at}",
                f"- 点赞: {post.like_count}",
                f"- 评论: {post.comment_count}",
                f"- 收藏: {post.collection_count}",
                f"- 链接: {post.detail_url}",
                "",
                post.content_text or post.intro or "无正文",
                "",
            ]
        )
    path.write_text("\n".join(lines).strip() + "\n", encoding="utf-8")


def save_followed_users_json(path: Path, meta: Dict[str, Any], users: Iterable[FollowedUser]) -> None:
    payload = {
        "meta": meta,
        "users": [asdict(user) for user in users],
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def save_followed_users_markdown(
    path: Path,
    title: str,
    summary_lines: List[str],
    users: Iterable[FollowedUser],
) -> None:
    lines = [f"# {title}", ""]
    lines.extend(summary_lines)
    lines.append("")
    for index, user in enumerate(users, start=1):
        lines.extend(
            [
                f"## {index}. {user.user_name or '未知用户'}",
                "",
                f"- brokerUserId: {user.broker_user_id or '未知'}",
                f"- spaceUserId: {user.space_user_id or '未知'}",
                f"- 标签: {user.user_label or '未知'}",
                "",
                user.user_desc or "无简介",
                "",
            ]
        )
    path.write_text("\n".join(lines).strip() + "\n", encoding="utf-8")


def save_groups_json(path: Path, meta: Dict[str, Any], groups: Iterable[GroupInfo]) -> None:
    payload = {
        "meta": meta,
        "groups": [asdict(group) for group in groups],
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def save_groups_markdown(
    path: Path,
    title: str,
    summary_lines: List[str],
    groups: Iterable[GroupInfo],
) -> None:
    lines = [f"# {title}", ""]
    lines.extend(summary_lines)
    lines.append("")
    for index, group in enumerate(groups, start=1):
        lines.extend(
            [
                f"## {index}. {group.group_name or f'小组 {group.group_id}'}",
                "",
                f"- groupId: {group.group_id}",
                f"- 主理人: {group.manager_name or '未知'}",
                f"- 主理人标签: {group.manager_label or '未知'}",
                f"- 来源: {group.source}",
                "",
                group.group_desc or "无简介",
                "",
            ]
        )
    path.write_text("\n".join(lines).strip() + "\n", encoding="utf-8")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="抓取且慢社区里的主理人动态流 / 关注动态流")
    parser.add_argument(
        "--mode",
        choices=(
            "group-manager",
            "following-posts",
            "following-users",
            "auth-check",
            "my-groups",
            "space-items",
        ),
        default="group-manager",
        help="抓取模式，默认 group-manager",
    )
    parser.add_argument("--group-id", type=int, help="直接指定社区小组 groupId")
    parser.add_argument("--group-url", help="社区小组链接，例如 https://qieman.com/content/group-detail/43")
    parser.add_argument("--prod-code", help="产品代码，例如 LONG_WIN")
    parser.add_argument("--manager-name", help="主理人名字，先在公开精选小组里尝试解析")
    parser.add_argument("--broker-user-id", help="可选，直接限定某个发言人的 brokerUserId")
    parser.add_argument("--user-name", help="按用户昵称过滤，可用于 following-posts / space-items 自动反查")
    parser.add_argument("--space-user-id", help="个人空间 spaceUserId，可用于 space-items 模式")
    parser.add_argument("--keyword", help="按标题/正文关键词过滤，可用于 group-manager / following-posts / space-items")
    parser.add_argument("--since", help="起始日期，格式 YYYY-MM-DD")
    parser.add_argument("--until", help="结束日期，格式 YYYY-MM-DD")
    parser.add_argument("--pages", type=int, default=3, help="抓取页数，默认 3")
    parser.add_argument("--page-size", type=int, default=10, help="每页数量，默认 10")
    parser.add_argument(
        "--only-manager",
        action="store_true",
        help="只保留组长/主理人的帖子",
    )
    parser.add_argument("--cookie", help="可选，原始 Cookie 字符串")
    parser.add_argument("--cookie-file", type=Path, help="可选，从文件读取 Cookie，避免 shell 历史泄露")
    parser.add_argument("--cookie-env", default="QIEMAN_COOKIE", help="可选，读取 Cookie 的环境变量名")
    parser.add_argument("--access-token", help="可选，直接指定 access_token")
    parser.add_argument(
        "--access-token-env",
        default="QIEMAN_ACCESS_TOKEN",
        help="可选，读取 access_token 的环境变量名",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help=f"输出目录，默认 {DEFAULT_OUTPUT_DIR}",
    )
    parser.add_argument("--markdown", action="store_true", help="同时输出 Markdown")
    return parser


def run_group_manager_mode(args: argparse.Namespace, client: QiemanCommunityClient) -> int:
    since_date, until_date = resolve_date_filters(args)
    group_id, source = resolve_group_id(args, client)
    group = fetch_group_info(client, group_id, source)
    posts = fetch_group_posts(
        client=client,
        group=group,
        page_size=args.page_size,
        pages=args.pages,
        only_manager=args.only_manager or not args.broker_user_id,
        broker_user_id=args.broker_user_id,
        keyword=args.keyword,
        since_date=since_date,
        until_date=until_date,
    )
    if not posts:
        raise SystemExit("没有抓到帖子。可能这个小组最近没有主理人发言，或关键词/日期过滤条件过严。")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = make_output_timestamp()
    file_stem = slugify(group.manager_name or group.group_name or str(group.group_id))
    json_path = args.output_dir / f"{file_stem}-community-{timestamp}.json"
    filters = {
        "keyword": args.keyword,
        "since": args.since,
        "until": args.until,
    }
    save_json(json_path, group, posts, filters=filters)
    print(f"共抓取 {len(posts)} 条社区动态")
    print(f"JSON: {json_path}")
    if args.markdown:
        md_path = args.output_dir / f"{file_stem}-community-{timestamp}.md"
        save_markdown(md_path, group, posts, filters=filters)
        print(f"Markdown: {md_path}")
    return 0


def run_following_posts_mode(args: argparse.Namespace, client: QiemanCommunityClient) -> int:
    since_date, until_date = resolve_date_filters(args)
    ensure_auth_available(client, args.mode)
    auth_user = fetch_auth_user_info(client)
    posts = fetch_following_posts(
        client=client,
        page_size=args.page_size,
        pages=args.pages,
        broker_user_id=args.broker_user_id,
        user_name=args.user_name,
        keyword=args.keyword,
        since_date=since_date,
        until_date=until_date,
    )
    if not posts:
        raise SystemExit("没有抓到关注动态。可能是你还没关注对应主理人，或过滤条件过严。")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = make_output_timestamp()
    filter_name = (
        args.user_name
        or args.broker_user_id
        or auth_user.user_name
        or auth_user.broker_user_id
        or "following"
    )
    file_stem = slugify(filter_name)
    json_path = args.output_dir / f"{file_stem}-following-{timestamp}.json"
    meta = {
        "mode": args.mode,
        "auth_user": asdict(auth_user),
        "filters": {
            "broker_user_id": args.broker_user_id,
            "user_name": args.user_name,
            "keyword": args.keyword,
            "since": args.since,
            "until": args.until,
        },
    }
    save_feed_json(json_path, meta, posts)
    print(f"共抓取 {len(posts)} 条关注动态")
    print(f"JSON: {json_path}")
    if args.markdown:
        md_path = args.output_dir / f"{file_stem}-following-{timestamp}.md"
        summary_lines = [
            f"- 登录用户: {auth_user.user_name or '未知'}",
            f"- 登录用户 brokerUserId: {auth_user.broker_user_id or '未知'}",
            f"- 过滤 userName: {args.user_name or '未设置'}",
            f"- 过滤 brokerUserId: {args.broker_user_id or '未设置'}",
            f"- 过滤 keyword: {args.keyword or '未设置'}",
            f"- 过滤 since: {args.since or '未设置'}",
            f"- 过滤 until: {args.until or '未设置'}",
        ]
        save_feed_markdown(md_path, "且慢关注动态", summary_lines, posts)
        print(f"Markdown: {md_path}")
    return 0


def run_following_users_mode(args: argparse.Namespace, client: QiemanCommunityClient) -> int:
    ensure_auth_available(client, args.mode)
    auth_user = fetch_auth_user_info(client)
    users = fetch_following_users(client=client, page_size=args.page_size, pages=args.pages)
    if not users:
        raise SystemExit("没有抓到关注列表。可能是账号尚未关注任何主理人，或登录态已失效。")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = make_output_timestamp()
    file_stem = slugify(auth_user.user_name or auth_user.broker_user_id or "following-users")
    json_path = args.output_dir / f"{file_stem}-following-users-{timestamp}.json"
    meta = {
        "mode": args.mode,
        "auth_user": asdict(auth_user),
    }
    save_followed_users_json(json_path, meta, users)
    print(f"共抓取 {len(users)} 个关注用户")
    print(f"JSON: {json_path}")
    if args.markdown:
        md_path = args.output_dir / f"{file_stem}-following-users-{timestamp}.md"
        summary_lines = [
            f"- 登录用户: {auth_user.user_name or '未知'}",
            f"- 登录用户 brokerUserId: {auth_user.broker_user_id or '未知'}",
        ]
        save_followed_users_markdown(md_path, "且慢关注用户", summary_lines, users)
        print(f"Markdown: {md_path}")
    return 0


def run_auth_check_mode(args: argparse.Namespace, client: QiemanCommunityClient) -> int:
    ensure_auth_available(client, args.mode)
    auth_user = fetch_auth_user_info(client)
    print("登录态有效")
    print(f"userName: {auth_user.user_name or '未知'}")
    print(f"brokerUserId: {auth_user.broker_user_id or '未知'}")
    print(f"userLabel: {auth_user.user_label or '未知'}")
    return 0


def run_my_groups_mode(args: argparse.Namespace, client: QiemanCommunityClient) -> int:
    ensure_auth_available(client, args.mode)
    auth_user = fetch_auth_user_info(client)
    groups = fetch_my_groups(client)
    if not groups:
        raise SystemExit("没有抓到已加入小组。可能账号尚未加入任何社区小组，或登录态已失效。")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = make_output_timestamp()
    file_stem = slugify(auth_user.user_name or auth_user.broker_user_id or "my-groups")
    json_path = args.output_dir / f"{file_stem}-my-groups-{timestamp}.json"
    meta = {
        "mode": args.mode,
        "auth_user": asdict(auth_user),
    }
    save_groups_json(json_path, meta, groups)
    print(f"共抓取 {len(groups)} 个已加入小组")
    print(f"JSON: {json_path}")
    if args.markdown:
        md_path = args.output_dir / f"{file_stem}-my-groups-{timestamp}.md"
        summary_lines = [
            f"- 登录用户: {auth_user.user_name or '未知'}",
            f"- 登录用户 brokerUserId: {auth_user.broker_user_id or '未知'}",
        ]
        save_groups_markdown(md_path, "且慢已加入小组", summary_lines, groups)
        print(f"Markdown: {md_path}")
    return 0


def run_space_items_mode(args: argparse.Namespace, client: QiemanCommunityClient) -> int:
    since_date, until_date = resolve_date_filters(args)
    space_user_id = resolve_space_user_id(args, client)
    space_user = fetch_space_user_info(client, space_user_id)
    posts = fetch_space_items(
        client=client,
        space_user_id=space_user_id,
        page_size=args.page_size,
        pages=args.pages,
        keyword=args.keyword,
        since_date=since_date,
        until_date=until_date,
    )
    if not posts:
        raise SystemExit("没有抓到个人空间动态。可能这个 spaceUserId 没有公开内容，或关键词/日期过滤条件过严。")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = make_output_timestamp()
    file_stem = slugify(space_user.user_name or space_user.space_user_id)
    json_path = args.output_dir / f"{file_stem}-space-items-{timestamp}.json"
    meta = {
        "mode": args.mode,
        "space_user": asdict(space_user),
        "filters": {
            "space_user_id": space_user_id,
            "user_name": args.user_name,
            "broker_user_id": args.broker_user_id,
            "keyword": args.keyword,
            "since": args.since,
            "until": args.until,
        },
    }
    save_feed_json(json_path, meta, posts)
    print(f"共抓取 {len(posts)} 条个人空间动态")
    print(f"JSON: {json_path}")
    if args.markdown:
        md_path = args.output_dir / f"{file_stem}-space-items-{timestamp}.md"
        summary_lines = [
            f"- 用户: {space_user.user_name or '未知'}",
            f"- spaceUserId: {space_user.space_user_id or '未知'}",
            f"- brokerUserId: {space_user.broker_user_id or '未知'}",
            f"- 标签: {space_user.user_label or '未知'}",
            f"- 过滤 keyword: {args.keyword or '未设置'}",
            f"- 过滤 since: {args.since or '未设置'}",
            f"- 过滤 until: {args.until or '未设置'}",
        ]
        save_feed_markdown(md_path, "且慢个人空间动态", summary_lines, posts)
        print(f"Markdown: {md_path}")
    return 0


def run(args: argparse.Namespace) -> int:
    cookie = resolve_cookie(args)
    access_token = resolve_access_token(args, cookie)
    client = QiemanCommunityClient(access_token=access_token, cookie=cookie)
    try:
        if args.mode == "group-manager":
            return run_group_manager_mode(args, client)
        if args.mode == "following-posts":
            return run_following_posts_mode(args, client)
        if args.mode == "following-users":
            return run_following_users_mode(args, client)
        if args.mode == "auth-check":
            return run_auth_check_mode(args, client)
        if args.mode == "my-groups":
            return run_my_groups_mode(args, client)
        if args.mode == "space-items":
            return run_space_items_mode(args, client)
    except QiemanApiError as exc:
        if exc.code == "9401":
            raise SystemExit(
                "登录态无效或缺失。请重新从 qieman.com 导出 Cookie / access_token 后重试。"
            ) from exc
        raise SystemExit(f"且慢接口返回错误: {exc.describe()}") from exc
    raise SystemExit(f"不支持的 mode: {args.mode}")


if __name__ == "__main__":
    raise SystemExit(run(build_parser().parse_args()))
