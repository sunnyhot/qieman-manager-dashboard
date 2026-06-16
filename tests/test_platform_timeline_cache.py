import unittest

from dashboard import cache
from dashboard.platform_fetcher import build_platform_timeline_from_actions


class SinglePassActions:
    def __init__(self, actions):
        self.actions = actions
        self.iteration_count = 0

    def __iter__(self):
        self.iteration_count += 1
        if self.iteration_count > 1:
            raise AssertionError("timeline actions should be consumed once")
        return iter(self.actions)


class PlatformTimelineCacheTests(unittest.TestCase):
    def setUp(self) -> None:
        if hasattr(cache, "PLATFORM_TIMELINE_CACHE"):
            cache.PLATFORM_TIMELINE_CACHE.clear()

    def tearDown(self) -> None:
        if hasattr(cache, "PLATFORM_TIMELINE_CACHE"):
            cache.PLATFORM_TIMELINE_CACHE.clear()

    def test_reuses_timeline_for_same_actions_source(self) -> None:
        actions = SinglePassActions(
            [
                {
                    "action_key": "buy-1",
                    "title": "沪深300",
                    "fund_code": "000300",
                    "side": "buy",
                    "txn_ts": 1_720_000_000_000,
                    "txn_date": "2024-07-04",
                },
                {
                    "action_key": "sell-1",
                    "title": "中证红利",
                    "fund_code": "000922",
                    "side": "sell",
                    "txn_ts": 1_719_900_000_000,
                    "txn_date": "2024-07-03",
                },
            ]
        )

        first = build_platform_timeline_from_actions(actions)
        second = build_platform_timeline_from_actions(actions)

        self.assertIs(first, second)
        self.assertEqual(actions.iteration_count, 1)
        self.assertEqual([item["label"] for item in first], ["沪深300", "中证红利"])


if __name__ == "__main__":
    unittest.main()
