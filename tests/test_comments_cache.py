import unittest
from unittest.mock import patch

from dashboard import cache
from dashboard.comments import fetch_post_comments


class FakeCommentClient:
    def __init__(self) -> None:
        self.call_count = 0

    def get(self, path, params):
        self.call_count += 1
        return [
            {
                "id": 1,
                "postId": params["postId"],
                "userName": "Alice",
                "content": "hello",
                "createdAt": "2026-06-16 10:00:00",
            }
        ]


class CommentsCacheTests(unittest.TestCase):
    def setUp(self) -> None:
        cache.COMMENTS_CACHE.clear()

    def tearDown(self) -> None:
        cache.COMMENTS_CACHE.clear()

    def test_reuses_comments_for_same_request_parameters(self) -> None:
        client = FakeCommentClient()

        with patch("dashboard.comments.build_dashboard_client", return_value=client):
            first = fetch_post_comments(post_id=9001, page_size=10, sort_type="hot", page_num=1)
            second = fetch_post_comments(post_id=9001, page_size=10, sort_type="hot", page_num=1)

        self.assertEqual(client.call_count, 1)
        self.assertEqual(first, second)
        self.assertEqual(first["comments"][0]["content"], "hello")


if __name__ == "__main__":
    unittest.main()
