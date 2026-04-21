#!/usr/bin/env python3
from __future__ import annotations

import importlib
import json
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable, List, Optional


DEFAULT_PROJECT_DIR = Path("/Users/xufan65/Documents/Codex/2026-04-17-new-chat")


def resolve_project_dir(explicit: str = "") -> Path:
    raw = explicit.strip() if explicit else os.environ.get("QIEMAN_PROJECT_DIR", "").strip()
    target = Path(raw).expanduser() if raw else DEFAULT_PROJECT_DIR
    return target.resolve()


def ensure_project_dir(project_dir: Path) -> Path:
    if not project_dir.exists() or not project_dir.is_dir():
        raise FileNotFoundError(f"项目目录不存在: {project_dir}")
    return project_dir


def ensure_project_import(project_dir: Path) -> None:
    project_path = str(project_dir)
    if project_path not in sys.path:
        sys.path.insert(0, project_path)


def load_project_module(project_dir: Path, module_name: str):
    ensure_project_import(project_dir)
    return importlib.import_module(module_name)


def parse_csv_codes(text: str) -> List[str]:
    return [item.strip() for item in text.split(",") if item.strip()]


def unique_codes(codes: Iterable[str]) -> List[str]:
    result: List[str] = []
    seen = set()
    for code in codes:
        clean = str(code).strip()
        if not clean or clean in seen:
            continue
        seen.add(clean)
        result.append(clean)
    return result


def parse_date(value: str) -> Optional[str]:
    text = value.strip()
    if not text:
        return None
    try:
        datetime.strptime(text, "%Y-%m-%d")
    except ValueError as exc:
        raise SystemExit(f"日期格式错误: {text}，请使用 YYYY-MM-DD") from exc
    return text


def in_date_range(date_text: str, since: Optional[str], until: Optional[str]) -> bool:
    text = (date_text or "").strip()
    if len(text) >= 10:
        text = text[:10]
    if not text:
        return False
    if since and text < since:
        return False
    if until and text > until:
        return False
    return True


def project_file(project_dir: Path, file_name: str) -> Path:
    path = project_dir / file_name
    if not path.exists():
        raise FileNotFoundError(f"缺少项目文件: {path}")
    return path


def load_dashboard_module(project_dir: Path):
    return load_project_module(project_dir, "dashboard_server")


def load_community_module(project_dir: Path):
    return load_project_module(project_dir, "qieman_community_scraper")


def load_public_module(project_dir: Path):
    return load_project_module(project_dir, "qieman_scraper")


def read_cookie_from_inputs(
    project_dir: Path,
    cookie: str = "",
    cookie_file: str = "",
    cookie_env: str = "QIEMAN_COOKIE",
) -> str:
    if cookie.strip():
        return cookie.strip()
    if cookie_file.strip():
        return Path(cookie_file).expanduser().read_text(encoding="utf-8").strip()
    env_value = os.environ.get(cookie_env, "").strip()
    if env_value:
        return env_value
    default_cookie_file = project_dir / "qieman.cookie"
    if default_cookie_file.exists():
        return default_cookie_file.read_text(encoding="utf-8").strip()
    return ""


def build_community_client(
    project_dir: Path,
    cookie: str = "",
    cookie_file: str = "",
    cookie_env: str = "QIEMAN_COOKIE",
    access_token: str = "",
    access_token_env: str = "QIEMAN_ACCESS_TOKEN",
):
    qcs = load_community_module(project_dir)
    cookie_value = read_cookie_from_inputs(
        project_dir=project_dir,
        cookie=cookie,
        cookie_file=cookie_file,
        cookie_env=cookie_env,
    )
    token = access_token.strip()
    if not token:
        token = os.environ.get(access_token_env, "").strip()
    if not token:
        token = qcs.extract_access_token(cookie_value or "") or ""
    client = qcs.QiemanCommunityClient(access_token=token or None, cookie=cookie_value or None)
    return qcs, client


def parse_json_file(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def print_json(payload: Any) -> None:
    print(json.dumps(payload, ensure_ascii=False, indent=2))
