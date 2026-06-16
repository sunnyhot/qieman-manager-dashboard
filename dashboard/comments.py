from __future__ import annotations

import time
from typing import Any, Dict, Optional

from qieman_community_scraper import QiemanApiError

from .cache import COMMENTS_CACHE, COMMENTS_TTL_SECONDS
from .snapshot import build_dashboard_client
from .utils import normalize_text, safe_int


def normalize_comment(item: Dict[str, Any]) -> Dict[str, Any]:
    children = item.get("children") if isinstance(item.get("children"), list) else []
    return {
        "id": safe_int(item.get("id")),
        "post_id": safe_int(item.get("postId")),
        "user_name": normalize_text(item.get("userName")) or normalize_text(item.get("brokerUserId")) or "未知用户",
        "user_avatar_url": normalize_text(item.get("userAvatarUrl")),
        "broker_user_id": normalize_text(item.get("brokerUserId")),
        "content": normalize_text(item.get("content")),
        "created_at": normalize_text(item.get("createdAt")),
        "like_count": safe_int(item.get("likeNum")),
        "reply_count": safe_int(item.get("commentNum")),
        "ip_location": normalize_text(item.get("ipLocation")),
        "to_user_name": normalize_text(item.get("toUserName")),
        "children": [normalize_comment(child) for child in children if isinstance(child, dict)],
    }


def comment_thread_has_broker_user(comment: Dict[str, Any], broker_user_id: str) -> bool:
    target = normalize_text(broker_user_id)
    if not target:
        return False
    if normalize_text(comment.get("broker_user_id")) == target:
        return True
    children = comment.get("children") if isinstance(comment.get("children"), list) else []
    return any(comment_thread_has_broker_user(child, target) for child in children if isinstance(child, dict))


def fetch_post_comments(
    post_id: int,
    page_size: int = 10,
    sort_type: str = "hot",
    page_num: int = 1,
    manager_broker_user_id: str = "",
) -> Dict[str, Any]:
    normalized_sort_type = sort_type.lower()
    normalized_manager_broker_user_id = normalize_text(manager_broker_user_id)
    cache_key = ":".join(
        [
            str(safe_int(post_id)),
            str(safe_int(page_size)),
            normalized_sort_type,
            str(safe_int(page_num)),
            normalized_manager_broker_user_id,
        ]
    )
    now = time.time()
    cached = COMMENTS_CACHE.get(cache_key)
    if cached and now - float(cached.get("ts", 0)) < COMMENTS_TTL_SECONDS:
        data = cached.get("data")
        if isinstance(data, dict):
            return data

    client = build_dashboard_client()
    params: Dict[str, Any] = {
        "pageNum": page_num,
        "pageSize": page_size,
        "postId": post_id,
    }
    if normalized_sort_type == "hot":
        params["sortType"] = "HOT"
    try:
        payload = client.get(
            "/community/comment/list",
            params,
        )
    except QiemanApiError as exc:
        raise RuntimeError(exc.describe()) from exc

    if not isinstance(payload, list):
        raise RuntimeError("评论接口返回结构异常")

    comments = [normalize_comment(item) for item in payload if isinstance(item, dict)]
    if normalized_manager_broker_user_id:
        comments = [comment for comment in comments if comment_thread_has_broker_user(comment, normalized_manager_broker_user_id)]

    result = {
        "post_id": post_id,
        "page_num": page_num,
        "page_size": page_size,
        "sort_type": normalized_sort_type,
        "has_more": len(payload) >= page_size,
        "comments": comments,
    }
    COMMENTS_CACHE[cache_key] = {
        "ts": now,
        "data": result,
    }
    return result


def load_comments_for_view(
    snapshot: Optional[Dict[str, Any]],
    focus_post_id: int,
    comment_sort: str,
    comment_page: int,
    only_manager_replies: bool,
) -> tuple[Optional[Dict[str, Any]], str]:
    if not snapshot or snapshot.get("snapshot_type") != "posts" or not focus_post_id:
        return None, ""
    records = snapshot.get("records") if isinstance(snapshot.get("records"), list) else []
    target = None
    for record in records:
        if safe_int(record.get("post_id")) == focus_post_id:
            target = record
            break
    if not isinstance(target, dict):
        return None, "未找到这条发言。"
    manager_broker_user_id = normalize_text(target.get("broker_user_id")) if only_manager_replies else ""
    try:
        payload = fetch_post_comments(
            post_id=focus_post_id,
            page_size=max(1, safe_int(snapshot.get("meta", {}).get("page_size")) or 10),
            sort_type=comment_sort,
            page_num=max(1, comment_page),
            manager_broker_user_id=manager_broker_user_id,
        )
        return payload, ""
    except Exception as exc:
        return None, str(exc)
