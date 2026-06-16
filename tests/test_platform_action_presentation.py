import unittest

from dashboard import cache
from dashboard.platform_fetcher import build_platform_action_presentation


class SinglePassActions:
    def __init__(self, actions):
        self.actions = actions
        self.iteration_count = 0

    def __iter__(self):
        self.iteration_count += 1
        if self.iteration_count > 1:
            raise AssertionError("actions should be consumed once")
        return iter(self.actions)


class PlatformActionPresentationTests(unittest.TestCase):
    def setUp(self) -> None:
        if hasattr(cache, "PLATFORM_ACTION_PRESENTATION_CACHE"):
            cache.PLATFORM_ACTION_PRESENTATION_CACHE.clear()

    def tearDown(self) -> None:
        if hasattr(cache, "PLATFORM_ACTION_PRESENTATION_CACHE"):
            cache.PLATFORM_ACTION_PRESENTATION_CACHE.clear()

    def test_builds_side_summaries_from_one_source_pass(self) -> None:
        actions = SinglePassActions(
            [
                {
                    "action_key": "buy-1",
                    "side": "buy",
                    "adjustment_id": 10,
                    "txn_ts": 1_720_000_000_000,
                },
                {
                    "action_key": "sell-1",
                    "side": "sell",
                    "adjustment_id": 11,
                    "txn_ts": 1_719_900_000_000,
                },
                {
                    "action_key": "old-buy",
                    "side": "buy",
                    "adjustment_id": 12,
                    "txn_ts": 1_600_000_000_000,
                },
                "ignored",
            ]
        )

        presentation = build_platform_action_presentation(
            {"actions": actions},
            {"since": "2024-07-01", "until": "2024-07-05"},
            "buy",
        )

        self.assertEqual(actions.iteration_count, 1)
        self.assertEqual([item["action_key"] for item in presentation["all_actions"]], ["buy-1", "sell-1"])
        self.assertEqual([item["action_key"] for item in presentation["filtered_actions"]], ["buy-1"])
        self.assertEqual(presentation["summary_all"]["count"], 2)
        self.assertEqual(presentation["summary_all"]["buy_count"], 1)
        self.assertEqual(presentation["summary_all"]["sell_count"], 1)
        self.assertEqual(presentation["summary_buy"]["count"], 1)
        self.assertEqual(presentation["summary_sell"]["count"], 1)

    def test_reuses_presentation_for_same_payload_and_filters(self) -> None:
        actions = SinglePassActions(
            [
                {
                    "action_key": "buy-1",
                    "side": "buy",
                    "adjustment_id": 10,
                    "txn_ts": 1_720_000_000_000,
                }
            ]
        )
        platform_trades = {"prod_code": "LONG_WIN", "actions": actions}
        form_values = {"platform_window": "all"}

        first = build_platform_action_presentation(platform_trades, form_values, "all")
        second = build_platform_action_presentation(platform_trades, form_values, "all")

        self.assertIs(first, second)
        self.assertEqual(actions.iteration_count, 1)


if __name__ == "__main__":
    unittest.main()
