from __future__ import annotations

import argparse
import json
import textwrap
import webbrowser
from datetime import datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Dict, Optional
from urllib.parse import parse_qs, urlparse

from . import cache
from .comments import fetch_post_comments, load_comments_for_view
from .config import (
    AUTO_FETCH_TIMEOUT_SECONDS,
    COOKIE_FILE,
    DEFAULT_HOST,
    DEFAULT_PORT,
    HOME_PLATFORM_FETCH_TIMEOUT_SECONDS,
    MANUAL_FETCH_TIMEOUT_SECONDS,
    OUTPUT_DIR,
    PLATFORM_FETCH_TIMEOUT_SECONDS,
)
from .html_helpers import (
    collect_form_values,
    first_mapping_value,
)
from .html_pages import (
    render_dashboard_page,
    render_forum_page,
    render_platform_page,
    render_timeline_page,
)
from .performance import performance_start, record_performance
from .platform_fetcher import fetch_platform_trade_data, get_snapshot_by_name
from .snapshot import run_auth_check, run_fetch
from .utils import first_mapping_value, format_time, normalize_text, safe_int


def api_status() -> Dict[str, Any]:
    return {
        "cookie_exists": COOKIE_FILE.exists(),
        "cookie_file": str(COOKIE_FILE),
        "output_dir": str(OUTPUT_DIR),
        "default_form": {
            "mode": "following-posts" if COOKIE_FILE.exists() else "group-manager",
            "prod_code": "LONG_WIN",
            "user_name": "ETF拯救世界",
            "pages": "5",
            "page_size": "10",
        },
    }


def api_bootstrap() -> Dict[str, Any]:
    return {
        "status": api_status(),
    }


def api_platform(prod_code: str) -> Dict[str, Any]:
    target = normalize_text(prod_code) or normalize_text(api_status().get("default_form", {}).get("prod_code")) or "LONG_WIN"
    return fetch_platform_trade_data(target)


class DashboardHandler(BaseHTTPRequestHandler):
    def handle_one_request(self) -> None:
        started_at = performance_start()
        try:
            super().handle_one_request()
        finally:
            raw_path = getattr(self, "path", "")
            parsed = urlparse(raw_path) if raw_path else None
            record_performance(
                "dashboard.request",
                started_at,
                method=getattr(self, "command", ""),
                route=parsed.path if parsed else "<unknown>",
            )

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path in {"/", "/timeline", "/platform", "/forum"}:
            params = parse_qs(parsed.query)
            form_values = collect_form_values(params)
            selected_name = first_mapping_value(params, "snapshot")
            auto_run = first_mapping_value(params, "auto_run") == "1"
            source_label = "尚未选择数据"
            notice = ""
            error = ""
            current_snapshot: Optional[Dict[str, Any]] = None

            should_fetch_latest_default = parsed.path in {"/", "/forum"} and not selected_name and not auto_run

            if auto_run or should_fetch_latest_default:
                try:
                    payload = dict(form_values)
                    payload["persist"] = False
                    current_snapshot = run_fetch(payload, timeout_seconds=AUTO_FETCH_TIMEOUT_SECONDS)
                    cache.LIVE_SNAPSHOT = current_snapshot
                    selected_name = "__live__"
                    source_label = "自动刷新结果" if auto_run else "默认实时结果"
                    notice_prefix = "已自动刷新" if auto_run else "已默认获取最新数据"
                    notice = f"{notice_prefix} {format_time(datetime.now().isoformat(timespec='seconds'))}"
                except Exception as exc:
                    error = str(exc)
            elif selected_name:
                if selected_name == "__live__":
                    try:
                        current_snapshot = get_snapshot_by_name(selected_name)
                        source_label = "临时实时结果"
                    except FileNotFoundError:
                        error = "临时结果已失效，请重新刷新。"
                else:
                    selected_name = ""
                    error = "请重新刷新最新数据。"

            focus_post_id = safe_int(first_mapping_value(params, "focus_post_id"))
            comment_sort = first_mapping_value(params, "comment_sort") or "hot"
            comment_page = safe_int(first_mapping_value(params, "comment_page")) or 1
            only_manager_replies = first_mapping_value(params, "only_manager_replies") == "1"
            signal_filter = first_mapping_value(params, "signal_filter") or "all"
            timeline_asset = first_mapping_value(params, "timeline_asset") or "all"
            platform_timeout = HOME_PLATFORM_FETCH_TIMEOUT_SECONDS if parsed.path == "/" else PLATFORM_FETCH_TIMEOUT_SECONDS
            platform_trades = fetch_platform_trade_data(
                normalize_text(form_values.get("prod_code")),
                timeout_seconds=platform_timeout,
            )
            if parsed.path == "/timeline":
                self.respond_html(
                    render_timeline_page(
                        form_values=form_values,
                        current_snapshot_name=selected_name,
                        platform_trades=platform_trades,
                        signal_filter=signal_filter,
                        timeline_asset=timeline_asset,
                        source_label=source_label,
                    )
                )
                return
            if parsed.path == "/platform":
                self.respond_html(
                    render_platform_page(
                        form_values=form_values,
                        current_snapshot_name=selected_name,
                        platform_trades=platform_trades,
                        signal_filter=signal_filter,
                        timeline_asset=timeline_asset,
                        source_label=source_label,
                    )
                )
                return
            comments_payload, comment_error = load_comments_for_view(
                snapshot=current_snapshot,
                focus_post_id=focus_post_id,
                comment_sort=comment_sort,
                comment_page=comment_page,
                only_manager_replies=only_manager_replies,
            )
            if parsed.path == "/forum":
                self.respond_html(
                    render_forum_page(
                        form_values=form_values,
                        current_snapshot=current_snapshot,
                        current_snapshot_name=selected_name,
                        source_label=source_label,
                        focus_post_id=focus_post_id,
                        comments_payload=comments_payload,
                        comment_error=comment_error,
                        comment_sort=comment_sort,
                        comment_page=comment_page,
                        only_manager_replies=only_manager_replies,
                    )
                )
                return
            self.respond_html(
                render_dashboard_page(
                    form_values=form_values,
                    current_snapshot=current_snapshot,
                    platform_trades=platform_trades,
                    current_snapshot_name=selected_name,
                    source_label=source_label,
                    notice=notice,
                    error=error,
                    focus_post_id=focus_post_id,
                    comments_payload=comments_payload,
                    comment_error=comment_error,
                    comment_sort=comment_sort,
                    comment_page=comment_page,
                    only_manager_replies=only_manager_replies,
                    signal_filter=signal_filter,
                    timeline_asset=timeline_asset,
                )
            )
            return
        if parsed.path == "/api/status":
            self.respond_json(api_status())
            return
        if parsed.path == "/api/bootstrap":
            self.respond_json(api_bootstrap())
            return
        if parsed.path == "/api/platform":
            params = parse_qs(parsed.query)
            prod_code = normalize_text(params.get("prod_code", [""])[0])
            self.respond_json(api_platform(prod_code))
            return
        if parsed.path == "/api/check-auth":
            self.respond_json(run_auth_check())
            return
        if parsed.path == "/api/comments":
            params = parse_qs(parsed.query)
            post_id = safe_int(normalize_text(params.get("post_id", [""])[0]))
            page_size = safe_int(normalize_text(params.get("page_size", ["10"])[0])) or 10
            sort_type = normalize_text(params.get("sort_type", ["hot"])[0]) or "hot"
            page_num = safe_int(normalize_text(params.get("page_num", ["1"])[0])) or 1
            manager_broker_user_id = normalize_text(params.get("manager_broker_user_id", [""])[0])
            if not post_id:
                self.respond_error(HTTPStatus.BAD_REQUEST, "缺少 post_id")
                return
            try:
                payload = fetch_post_comments(
                    post_id=post_id,
                    page_size=page_size,
                    sort_type=sort_type,
                    page_num=page_num,
                    manager_broker_user_id=manager_broker_user_id,
                )
            except Exception as exc:
                self.respond_error(HTTPStatus.BAD_REQUEST, str(exc))
                return
            self.respond_json(payload)
            return
        self.respond_error(HTTPStatus.NOT_FOUND, "未找到接口")

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/":
            length = int(self.headers.get("Content-Length", "0"))
            raw_body = self.rfile.read(length).decode("utf-8")
            form_data = parse_qs(raw_body, keep_blank_values=True)
            form_values = collect_form_values(form_data)
            action = first_mapping_value(form_data, "action")
            current_snapshot_name = first_mapping_value(form_data, "snapshot")
            current_snapshot: Optional[Dict[str, Any]] = None
            source_label = "尚未选择数据"
            notice = ""
            error = ""
            auth_result: Optional[Dict[str, Any]] = None

            if action == "fetch-preview":
                try:
                    payload = dict(form_values)
                    payload["persist"] = False
                    current_snapshot = run_fetch(payload, timeout_seconds=MANUAL_FETCH_TIMEOUT_SECONDS)
                    cache.LIVE_SNAPSHOT = current_snapshot
                    current_snapshot_name = "__live__"
                    source_label = "临时实时结果"
                    notice = "已经刷新到最新结果。"
                except Exception as exc:
                    error = str(exc)
            elif action == "auth-check":
                auth_result = run_auth_check()
                notice = ""

            if not current_snapshot and current_snapshot_name:
                if current_snapshot_name == "__live__":
                    try:
                        current_snapshot = get_snapshot_by_name(current_snapshot_name)
                        source_label = "临时实时结果"
                    except FileNotFoundError:
                        current_snapshot_name = ""
                        if not error:
                            error = "临时结果已失效，请重新刷新。"
                else:
                    current_snapshot_name = ""
                    if not error:
                        error = "请重新刷新最新数据。"

            focus_post_id = safe_int(first_mapping_value(form_data, "focus_post_id"))
            comment_sort = first_mapping_value(form_data, "comment_sort") or "hot"
            comment_page = safe_int(first_mapping_value(form_data, "comment_page")) or 1
            only_manager_replies = first_mapping_value(form_data, "only_manager_replies") == "1"
            signal_filter = first_mapping_value(form_data, "signal_filter") or "all"
            timeline_asset = first_mapping_value(form_data, "timeline_asset") or "all"
            platform_trades = fetch_platform_trade_data(
                normalize_text(form_values.get("prod_code")),
                timeout_seconds=PLATFORM_FETCH_TIMEOUT_SECONDS,
            )
            comments_payload, comment_error = load_comments_for_view(
                snapshot=current_snapshot,
                focus_post_id=focus_post_id,
                comment_sort=comment_sort,
                comment_page=comment_page,
                only_manager_replies=only_manager_replies,
            )
            self.respond_html(
                render_dashboard_page(
                    form_values=form_values,
                    current_snapshot=current_snapshot,
                    platform_trades=platform_trades,
                    current_snapshot_name=current_snapshot_name,
                    source_label=source_label,
                    notice=notice,
                    error=error,
                    auth_result=auth_result,
                    focus_post_id=focus_post_id,
                    comments_payload=comments_payload,
                    comment_error=comment_error,
                    comment_sort=comment_sort,
                    comment_page=comment_page,
                    only_manager_replies=only_manager_replies,
                    signal_filter=signal_filter,
                    timeline_asset=timeline_asset,
                )
            )
            return
        if parsed.path != "/api/fetch":
            self.respond_error(HTTPStatus.NOT_FOUND, "未找到接口")
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length)
            payload = json.loads(body.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            self.respond_error(HTTPStatus.BAD_REQUEST, "请求体不是合法 JSON")
            return

        try:
            snapshot = run_fetch(
                payload if isinstance(payload, dict) else {},
                timeout_seconds=MANUAL_FETCH_TIMEOUT_SECONDS,
            )
        except Exception as exc:
            self.respond_error(HTTPStatus.BAD_REQUEST, str(exc))
            return

        self.respond_json({"snapshot": snapshot})

    def log_message(self, format: str, *args: Any) -> None:
        return

    def respond_html(self, html_content: str) -> None:
        body = html_content.encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def respond_json(self, payload: Dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def respond_error(self, status: HTTPStatus, message: str) -> None:
        body = json.dumps({"error": message}, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="本地且慢主理人看板")
    parser.add_argument("--host", default=DEFAULT_HOST, help=f"监听地址，默认 {DEFAULT_HOST}")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"监听端口，默认 {DEFAULT_PORT}")
    parser.add_argument("--open", action="store_true", help="启动后自动打开浏览器")
    return parser


def run_server(host: str, port: int, open_browser: bool) -> int:
    server = ThreadingHTTPServer((host, port), DashboardHandler)
    url = f"http://{host}:{port}"
    print(textwrap.dedent(
        f"""
        Dashboard 已启动
        地址: {url}
        输出目录: {OUTPUT_DIR}
        Cookie 文件: {COOKIE_FILE}
        按 Ctrl+C 停止服务
        """
    ).strip())
    if open_browser:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nDashboard 已停止")
    finally:
        server.server_close()
    return 0


def main() -> int:
    args = build_parser().parse_args()
    return run_server(args.host, args.port, args.open)
