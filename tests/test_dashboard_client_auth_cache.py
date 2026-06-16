import unittest
from types import SimpleNamespace
from unittest.mock import patch

from dashboard import cache, snapshot


class FakeCookieFile:
    def __init__(self, text: str) -> None:
        self.text = text
        self.read_count = 0
        self.mtime_ns = 100

    def exists(self) -> bool:
        return True

    def stat(self):
        return SimpleNamespace(st_mtime_ns=self.mtime_ns, st_size=len(self.text))

    def read_text(self, encoding: str):
        self.read_count += 1
        return self.text


class DashboardClientAuthCacheTests(unittest.TestCase):
    def setUp(self) -> None:
        cache.CLIENT_AUTH_CACHE.clear()

    def tearDown(self) -> None:
        cache.CLIENT_AUTH_CACHE.clear()

    def test_reuses_cookie_auth_material_until_cookie_file_changes(self) -> None:
        cookie_file = FakeCookieFile("access_token=first; foo=bar")

        with patch("dashboard.snapshot.COOKIE_FILE", cookie_file):
            first = snapshot.build_dashboard_client()
            second = snapshot.build_dashboard_client()
            cookie_file.text = "access_token=second; foo=bar"
            cookie_file.mtime_ns += 1
            third = snapshot.build_dashboard_client()

        self.assertEqual(cookie_file.read_count, 2)
        self.assertEqual(first.access_token, "first")
        self.assertEqual(second.access_token, "first")
        self.assertEqual(third.access_token, "second")


if __name__ == "__main__":
    unittest.main()
