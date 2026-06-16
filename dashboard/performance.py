from __future__ import annotations

import os
import sys
import time
from contextlib import contextmanager
from functools import wraps
from typing import Any, Callable, Dict, Iterator, TypeVar


T = TypeVar("T")
SENSITIVE_MARKERS = ("cookie", "authorization", "token")


def performance_start() -> float:
    return time.perf_counter()


def performance_logging_enabled() -> bool:
    return os.environ.get("QIEMAN_PERF_LOG") == "1"


def record_performance(name: str, started_at: float, **metadata: Any) -> None:
    if not performance_logging_enabled():
        return
    elapsed_ms = (time.perf_counter() - started_at) * 1000
    metadata_text = _format_metadata(metadata)
    suffix = f" {metadata_text}" if metadata_text else ""
    print(f"[perf] {name} {elapsed_ms:.1f}ms{suffix}", file=sys.stderr, flush=True)


@contextmanager
def measure(name: str, **metadata: Any) -> Iterator[None]:
    started_at = performance_start()
    try:
        yield
    finally:
        record_performance(name, started_at, **metadata)


def timed(name: str) -> Callable[[Callable[..., T]], Callable[..., T]]:
    def decorator(function: Callable[..., T]) -> Callable[..., T]:
        @wraps(function)
        def wrapper(*args: Any, **kwargs: Any) -> T:
            started_at = performance_start()
            try:
                return function(*args, **kwargs)
            finally:
                record_performance(name, started_at)

        return wrapper

    return decorator


def _format_metadata(metadata: Dict[str, Any]) -> str:
    parts = []
    for key in sorted(metadata):
        parts.append(f"{key}={_safe_metadata_value(key, metadata[key])}")
    return " ".join(parts)


def _safe_metadata_value(key: str, value: Any) -> str:
    text = str(value)
    if _is_sensitive(key) or _is_sensitive(text):
        return "<redacted>"
    if len(text) > 80:
        return text[:77] + "..."
    return text


def _is_sensitive(value: str) -> bool:
    lower = value.lower()
    return any(marker in lower for marker in SENSITIVE_MARKERS)
