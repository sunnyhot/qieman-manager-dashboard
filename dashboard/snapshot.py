from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional

from qieman_community_scraper import (
    QiemanCommunityClient,
    extract_access_token,
)

from .config import (
    COOKIE_FILE,
    JSON_LINE_RE,
    PROJECT_DIR,
    SCRAPER_FILE,
)
from .utils import (
    build_generic_stats,
    build_list_stats,
    build_post_stats,
    build_signal_stats,
    format_file_time,
    format_time,
    load_json,
    normalize_post_records,
    normalize_text,
    safe_int,
)


def infer_title_from_file(path: Path) -> str:
    stem = path.stem
    parts = stem.split("-")
    if len(parts) >= 3 and parts[-1].isdigit():
        return "-".join(parts[:-2]) or stem
    if len(parts) >= 2 and parts[-1].isdigit():
        return "-".join(parts[:-1]) or stem
    return stem


def normalize_snapshot(path: Path, include_records: bool) -> Dict[str, Any]:
    raw = load_json(path)
    created_at = format_file_time(path)

    if isinstance(raw, dict) and "posts" in raw:
        records = normalize_post_records(raw.get("posts") or [])
        group = raw.get("group") or {}
        meta = raw.get("meta") or {}
        auth_user = meta.get("auth_user") or {}
        first_record = records[0] if records else {}
        filters = raw.get("filters") or meta.get("filters") or {}
        mode = normalize_text(meta.get("mode")) or "group-manager"
        title = (
            normalize_text((meta.get("space_user") or {}).get("user_name"))
            or normalize_text(group.get("manager_name"))
            or normalize_text(filters.get("user_name"))
            or normalize_text(first_record.get("user_name"))
            or normalize_text(auth_user.get("user_name"))
            or normalize_text(auth_user.get("broker_user_id"))
            or normalize_text(group.get("group_name"))
            or infer_title_from_file(path)
        )
        subtitle = (
            normalize_text(group.get("group_name"))
            or normalize_text(first_record.get("group_name"))
            or normalize_text(meta.get("mode"))
            or "帖子流"
        )
        return {
            "file_name": path.name,
            "file_path": str(path),
            "snapshot_type": "posts",
            "kind_label": "帖子",
            "mode": mode,
            "title": title,
            "subtitle": subtitle,
            "created_at": created_at,
            "count": len(records),
            "filters": filters,
            "group": group,
            "meta": meta,
            "stats": build_post_stats(records),
            "signals": build_signal_stats(records),
            "records": records if include_records else [],
        }

    if isinstance(raw, dict) and "users" in raw:
        records = raw.get("users") or []
        meta = raw.get("meta") or {}
        auth_user = meta.get("auth_user") or {}
        return {
            "file_name": path.name,
            "file_path": str(path),
            "snapshot_type": "users",
            "kind_label": "用户",
            "mode": normalize_text(meta.get("mode")) or "following-users",
            "title": normalize_text(auth_user.get("user_name")) or normalize_text(auth_user.get("broker_user_id")) or "关注用户",
            "subtitle": "关注列表",
            "created_at": created_at,
            "count": len(records),
            "filters": {},
            "group": {},
            "meta": meta,
            "stats": build_list_stats(records, "users"),
            "signals": {},
            "records": records if include_records else [],
        }

    if isinstance(raw, dict) and "groups" in raw:
        records = raw.get("groups") or []
        meta = raw.get("meta") or {}
        auth_user = meta.get("auth_user") or {}
        return {
            "file_name": path.name,
            "file_path": str(path),
            "snapshot_type": "groups",
            "kind_label": "小组",
            "mode": normalize_text(meta.get("mode")) or "my-groups",
            "title": normalize_text(auth_user.get("user_name")) or normalize_text(auth_user.get("broker_user_id")) or "已加入小组",
            "subtitle": "小组列表",
            "created_at": created_at,
            "count": len(records),
            "filters": {},
            "group": {},
            "meta": meta,
            "stats": build_list_stats(records, "groups"),
            "signals": {},
            "records": records if include_records else [],
        }

    if isinstance(raw, list):
        records = raw
        query = normalize_text(records[0].get("query")) if records and isinstance(records[0], dict) else ""
        return {
            "file_name": path.name,
            "file_path": str(path),
            "snapshot_type": "items",
            "kind_label": "内容",
            "mode": "public-content",
            "title": query or infer_title_from_file(path),
            "subtitle": "公开内容检索",
            "created_at": created_at,
            "count": len(records),
            "filters": {"query": query} if query else {},
            "group": {},
            "meta": {},
            "stats": build_generic_stats(records if all(isinstance(item, dict) for item in records) else []),
            "signals": {},
            "records": records if include_records else [],
        }

    return {
        "file_name": path.name,
        "file_path": str(path),
        "snapshot_type": "unknown",
        "kind_label": "未知",
        "mode": "unknown",
        "title": infer_title_from_file(path),
        "subtitle": "未识别结构",
        "created_at": created_at,
        "count": 0,
        "filters": {},
        "group": {},
        "meta": {},
        "stats": {},
        "signals": {},
        "records": raw if include_records else [],
    }


def build_scraper_command(payload: Dict[str, Any], output_dir: Path) -> List[str]:
    mode = normalize_text(payload.get("mode")) or "following-posts"
    command = [
        "python3",
        str(SCRAPER_FILE),
        "--mode",
        mode,
        "--output-dir",
        str(output_dir),
    ]
    if COOKIE_FILE.exists():
        command.extend(["--cookie-file", str(COOKIE_FILE)])

    option_map = {
        "group_id": "--group-id",
        "group_url": "--group-url",
        "prod_code": "--prod-code",
        "manager_name": "--manager-name",
        "broker_user_id": "--broker-user-id",
        "user_name": "--user-name",
        "space_user_id": "--space-user-id",
        "keyword": "--keyword",
        "since": "--since",
        "until": "--until",
    }
    for key, flag in option_map.items():
        value = normalize_text(payload.get(key))
        if value:
            command.extend([flag, value])

    pages = normalize_text(payload.get("pages"))
    page_size = normalize_text(payload.get("page_size"))
    if pages:
        command.extend(["--pages", pages])
    if page_size:
        command.extend(["--page-size", page_size])
    return command


def run_fetch(payload: Dict[str, Any], timeout_seconds: Optional[int] = None) -> Dict[str, Any]:
    persist = False
    target_dir: Optional[tempfile.TemporaryDirectory[str]] = tempfile.TemporaryDirectory(prefix="qieman-live-")
    output_dir = Path(target_dir.name)

    command = build_scraper_command(payload, output_dir)
    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            cwd=PROJECT_DIR,
            timeout=timeout_seconds if timeout_seconds and timeout_seconds > 0 else None,
        )
    except subprocess.TimeoutExpired:
        if target_dir:
            target_dir.cleanup()
        hint = "请稍后重试，或缩小时间范围/页数后再刷新。"
        raise RuntimeError(f"抓取超时（>{safe_int(timeout_seconds)}秒），{hint}")
    stdout = result.stdout.strip()
    stderr = result.stderr.strip()
    if result.returncode != 0:
        if target_dir:
            target_dir.cleanup()
        message = stderr or stdout or "抓取失败"
        raise RuntimeError(message)

    match = JSON_LINE_RE.search(stdout)
    if not match:
        if target_dir:
            target_dir.cleanup()
        raise RuntimeError(stdout or "没有解析到 JSON 输出文件")

    json_path = Path(match.group(1).strip())
    snapshot = normalize_snapshot(json_path, include_records=True)
    snapshot["persisted"] = persist
    snapshot["command"] = command
    snapshot["stdout"] = stdout
    if target_dir:
        target_dir.cleanup()
    return snapshot


def run_auth_check() -> Dict[str, Any]:
    if not COOKIE_FILE.exists():
        return {
            "ok": False,
            "message": "未发现 qieman.cookie",
            "user_name": "",
            "broker_user_id": "",
            "user_label": "",
        }

    command = [
        "python3",
        str(SCRAPER_FILE),
        "--mode",
        "auth-check",
        "--cookie-file",
        str(COOKIE_FILE),
    ]
    result = subprocess.run(command, capture_output=True, text=True, cwd=PROJECT_DIR)
    output = (result.stdout or result.stderr).strip()
    if result.returncode != 0:
        return {
            "ok": False,
            "message": output or "登录校验失败",
            "user_name": "",
            "broker_user_id": "",
            "user_label": "",
        }

    values: Dict[str, str] = {}
    for line in output.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        values[key.strip()] = value.strip()
    return {
        "ok": True,
        "message": "登录态有效",
        "user_name": values.get("userName", ""),
        "broker_user_id": values.get("brokerUserId", ""),
        "user_label": values.get("userLabel", ""),
    }


def build_dashboard_client() -> QiemanCommunityClient:
    cookie = COOKIE_FILE.read_text(encoding="utf-8").strip() if COOKIE_FILE.exists() else None
    access_token = extract_access_token(cookie or "")
    return QiemanCommunityClient(access_token=access_token, cookie=cookie)
