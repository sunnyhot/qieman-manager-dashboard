import unittest

from dashboard import cache
from dashboard.html_helpers import build_platform_monthly_overview


class SinglePassActions:
    def __init__(self, actions):
        self.actions = actions
        self.iteration_count = 0

    def __iter__(self):
        self.iteration_count += 1
        if self.iteration_count > 1:
            raise AssertionError("monthly overview actions should be consumed once")
        return iter(self.actions)


class PlatformMonthlyOverviewCacheTests(unittest.TestCase):
    def setUp(self) -> None:
        if hasattr(cache, "PLATFORM_MONTHLY_OVERVIEW_CACHE"):
            cache.PLATFORM_MONTHLY_OVERVIEW_CACHE.clear()

    def tearDown(self) -> None:
        if hasattr(cache, "PLATFORM_MONTHLY_OVERVIEW_CACHE"):
            cache.PLATFORM_MONTHLY_OVERVIEW_CACHE.clear()

    def test_reuses_monthly_overview_for_same_actions_source_and_limit(self) -> None:
        actions = SinglePassActions(
            [
                {"action_key": "buy-1", "side": "buy", "txn_date": "2024-07-04"},
                {"action_key": "sell-1", "side": "sell", "txn_date": "2024-07-03"},
            ]
        )

        first = build_platform_monthly_overview(actions, limit_months=12)
        second = build_platform_monthly_overview(actions, limit_months=12)

        self.assertIs(first, second)
        self.assertEqual(actions.iteration_count, 1)
        self.assertEqual(first["month_count"], 1)
        self.assertEqual(first["buy_count"], 1)
        self.assertEqual(first["sell_count"], 1)


if __name__ == "__main__":
    unittest.main()
