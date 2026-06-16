import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch

from dashboard import cache, fund_fetcher


class SlowTextFetcher:
    def __init__(self, text: str) -> None:
        self.text = text
        self.call_count = 0
        self.lock = threading.Lock()

    def __call__(self, url: str) -> str:
        with self.lock:
            self.call_count += 1
        time.sleep(0.05)
        return self.text


class FundFetcherConcurrencyTests(unittest.TestCase):
    def setUp(self) -> None:
        fund_fetcher.FUND_HISTORY_CACHE.clear()
        fund_fetcher.FUND_QUOTE_CACHE.clear()
        if hasattr(cache, "FUND_HISTORY_LOCKS"):
            cache.FUND_HISTORY_LOCKS.clear()
        if hasattr(cache, "FUND_QUOTE_LOCKS"):
            cache.FUND_QUOTE_LOCKS.clear()

    def tearDown(self) -> None:
        fund_fetcher.FUND_HISTORY_CACHE.clear()
        fund_fetcher.FUND_QUOTE_CACHE.clear()
        if hasattr(cache, "FUND_HISTORY_LOCKS"):
            cache.FUND_HISTORY_LOCKS.clear()
        if hasattr(cache, "FUND_QUOTE_LOCKS"):
            cache.FUND_QUOTE_LOCKS.clear()

    def test_concurrent_history_fetches_share_single_remote_call(self) -> None:
        remote = SlowTextFetcher(
            'var fS_name = "沪深300";'
            'var Data_netWorthTrend = [{"x": 1704067200000, "y": 1.2}];'
        )

        with patch("dashboard.fund_fetcher.fetch_remote_text", side_effect=remote):
            with ThreadPoolExecutor(max_workers=2) as executor:
                results = list(executor.map(lambda _: fund_fetcher.fetch_fund_history_series("000300"), range(2)))

        self.assertEqual(remote.call_count, 1)
        self.assertIs(results[0], results[1])
        self.assertEqual(results[0]["series"][0]["nav"], 1.2)

    def test_concurrent_quote_fetches_share_single_remote_call(self) -> None:
        remote = SlowTextFetcher(
            'jsonpgz({"name":"沪深300","gsz":"1.23","gztime":"2026-06-16 14:55",'
            '"dwjz":"1.2","jzrq":"2026-06-15","gszzl":"0.1"});'
        )

        with patch("dashboard.fund_fetcher.fetch_remote_text", side_effect=remote):
            with ThreadPoolExecutor(max_workers=2) as executor:
                results = list(executor.map(lambda _: fund_fetcher.fetch_fund_quote("000300"), range(2)))

        self.assertEqual(remote.call_count, 1)
        self.assertIs(results[0], results[1])
        self.assertEqual(results[0]["price"], 1.23)


if __name__ == "__main__":
    unittest.main()
