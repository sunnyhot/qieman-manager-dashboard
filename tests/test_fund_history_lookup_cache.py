import unittest
from unittest.mock import patch

from dashboard.fund_fetcher import lookup_fund_nav_by_date


class FundHistoryLookupCacheTests(unittest.TestCase):
    def test_reuses_normalized_lookup_tables_for_repeated_nav_lookup(self) -> None:
        history = {
            "keys": ["20240101", "20240102"],
            "series": [
                {"date": "2024-01-01", "nav": 1.0},
                {"date": "2024-01-02", "nav": 1.1},
            ],
        }

        self.assertEqual(lookup_fund_nav_by_date(history, "2024-01-02")["nav"], 1.1)

        with patch(
            "dashboard.fund_fetcher.safe_int",
            side_effect=AssertionError("normalized history lookup should be cached"),
        ):
            self.assertEqual(lookup_fund_nav_by_date(history, "2024-01-01")["nav"], 1.0)


if __name__ == "__main__":
    unittest.main()
