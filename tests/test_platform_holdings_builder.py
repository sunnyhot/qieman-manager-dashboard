import builtins
import unittest

from dashboard import platform_fetcher


class PlatformHoldingsBuilderTests(unittest.TestCase):
    def test_builds_latest_holdings_without_sorting_source_actions(self) -> None:
        actions = [
            {
                "action_key": "old-buy",
                "fund_code": "000300",
                "title": "沪深300",
                "post_plan_unit": 100,
                "txn_ts": 100,
                "txn_date": "2024-07-01",
            },
            {
                "action_key": "other-buy",
                "fund_code": "000905",
                "title": "中证500",
                "post_plan_unit": 5,
                "txn_ts": 150,
                "txn_date": "2024-07-02",
            },
            {
                "action_key": "new-sell",
                "fund_code": "000300",
                "title": "沪深300",
                "post_plan_unit": 0,
                "txn_ts": 200,
                "txn_date": "2024-07-03",
            },
        ]

        original_sorted = getattr(platform_fetcher, "sorted", None)
        platform_fetcher.sorted = self.fail_sorted_source_actions(actions)
        try:
            holdings = platform_fetcher.build_platform_holdings_from_actions(actions)
        finally:
            if original_sorted is None:
                delattr(platform_fetcher, "sorted")
            else:
                platform_fetcher.sorted = original_sorted

        self.assertEqual(holdings["asset_count"], 1)
        self.assertEqual(holdings["latest_time"], "2024-07-02")
        self.assertEqual([item["asset_key"] for item in holdings["items"]], ["000905"])

    def fail_sorted_source_actions(self, source_actions):
        def fail_sorted(values, *args, **kwargs):
            if values is source_actions:
                raise AssertionError("holdings should not sort source actions")
            return builtins.sorted(values, *args, **kwargs)

        return fail_sorted


if __name__ == "__main__":
    unittest.main()
