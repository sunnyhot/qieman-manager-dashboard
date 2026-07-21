import XCTest
@testable import QiemanDashboard

final class MultiGroupSnapshotTests: XCTestCase {
    func testMergeDeduplicatesByPostId() {
        let posts: [[String: Any]] = [
            ["post_id": 100, "created_at": "2026-07-21"],
            ["post_id": 100, "created_at": "2026-07-21"],  // 重复
            ["post_id": 200, "created_at": "2026-07-20"],
        ]
        let merged = QiemanNativeClient.mergeAndSortPosts(posts)
        XCTAssertEqual(merged.count, 2)
    }

    func testSortByCreatedAtDescending() {
        let posts: [[String: Any]] = [
            ["post_id": 1, "created_at": "2026-07-20"],
            ["post_id": 2, "created_at": "2026-07-22"],
            ["post_id": 3, "created_at": "2026-07-21"],
        ]
        let merged = QiemanNativeClient.mergeAndSortPosts(posts)
        XCTAssertEqual(merged[0]["post_id"] as? Int, 2)  // 最新在前
        XCTAssertEqual(merged[2]["post_id"] as? Int, 1)
    }

    func testEmptyInputReturnsEmpty() {
        let merged = QiemanNativeClient.mergeAndSortPosts([])
        XCTAssertTrue(merged.isEmpty)
    }

    func testPostsWithoutIdAreKept() {
        let posts: [[String: Any]] = [
            ["created_at": "2026-07-20"],  // 无 post_id
            ["created_at": "2026-07-21"],
        ]
        let merged = QiemanNativeClient.mergeAndSortPosts(posts)
        XCTAssertEqual(merged.count, 2)  // 都保留
    }
}
