import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch

from dashboard import cache
from dashboard.platform_fetcher import fetch_platform_trade_data


class SlowPlatformClient:
    def __init__(self) -> None:
        self.call_count = 0
        self.lock = threading.Lock()

    def get(self, path, params, timeout):
        with self.lock:
            self.call_count += 1
        time.sleep(0.05)
        return []


class PlatformFetcherCacheTests(unittest.TestCase):
    def setUp(self) -> None:
        cache.PLATFORM_TRADE_CACHE.clear()
        if hasattr(cache, "PLATFORM_TRADE_LOCKS"):
            cache.PLATFORM_TRADE_LOCKS.clear()

    def tearDown(self) -> None:
        cache.PLATFORM_TRADE_CACHE.clear()
        if hasattr(cache, "PLATFORM_TRADE_LOCKS"):
            cache.PLATFORM_TRADE_LOCKS.clear()

    def test_concurrent_platform_fetches_share_single_remote_call(self) -> None:
        client = SlowPlatformClient()
        payload = {"supported": True, "prod_code": "LONG_WIN", "actions": []}

        with patch("dashboard.platform_fetcher.build_dashboard_client", return_value=client), patch(
            "dashboard.platform_fetcher.build_platform_trade_data",
            return_value=payload,
        ):
            with ThreadPoolExecutor(max_workers=2) as executor:
                results = list(executor.map(lambda _: fetch_platform_trade_data("LONG_WIN"), range(2)))

        self.assertEqual(client.call_count, 1)
        self.assertEqual(results, [payload, payload])


if __name__ == "__main__":
    unittest.main()
