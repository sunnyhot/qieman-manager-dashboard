import unittest

from dashboard import cache
from dashboard.platform_fetcher import build_platform_action_presentation


class CacheBoundsTests(unittest.TestCase):
    def setUp(self) -> None:
        if hasattr(cache, "PLATFORM_ACTION_PRESENTATION_CACHE"):
            cache.PLATFORM_ACTION_PRESENTATION_CACHE.clear()

    def tearDown(self) -> None:
        if hasattr(cache, "PLATFORM_ACTION_PRESENTATION_CACHE"):
            cache.PLATFORM_ACTION_PRESENTATION_CACHE.clear()

    def test_platform_action_presentation_cache_is_bounded(self) -> None:
        platform_trades = {
            "prod_code": "LONG_WIN",
            "actions": [
                {
                    "action_key": "buy-1",
                    "side": "buy",
                    "adjustment_id": 10,
                    "txn_ts": 1_720_000_000_000,
                }
            ],
        }

        for index in range(cache.MAX_DERIVED_CACHE_ENTRIES + 5):
            build_platform_action_presentation(
                platform_trades,
                {"since": f"2024-01-{(index % 28) + 1:02d}", "until": f"2024-02-{(index % 28) + 1:02d}"},
                "all",
            )

        self.assertLessEqual(len(cache.PLATFORM_ACTION_PRESENTATION_CACHE), cache.MAX_DERIVED_CACHE_ENTRIES)


if __name__ == "__main__":
    unittest.main()
