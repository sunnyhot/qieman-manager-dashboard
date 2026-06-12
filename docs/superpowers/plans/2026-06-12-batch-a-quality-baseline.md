# Batch A Quality Baseline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Batch A foundation for CI, test wiring, documentation accuracy, cookie-file safety, and dual-channel contract fixtures.

**Architecture:** Keep production data flow unchanged. Add regular validation around the existing Swift Package target, Python standard-library code, and small contract fixtures; make cookie-file persistence safer without replacing the Python-compatible file path.

**Tech Stack:** Swift 5.9, XCTest, SwiftUI/AppKit app target, Python 3 standard library `unittest`, GitHub Actions on macOS.

---

## Files And Responsibilities

- Create `.github/workflows/ci.yml`: regular push and pull request validation.
- Replace `macos-app/Tests/DownloadProgressTests.swift` with `macos-app/Tests/QiemanDashboardTests/DownloadProgressTests.swift`: XCTest coverage for the real download progress type.
- Modify `macos-app/Core/QiemanCookieManager.swift`: tighten cookie-file permissions on save and load.
- Create `macos-app/Tests/QiemanDashboardTests/QiemanCookieManagerTests.swift`: permission tests for cookie persistence.
- Modify `README.md`, `AGENTS.md`, `PROJECT_MAP.md`, `CLAUDE.md`, and `scripts/build_macos_app.sh`: align docs and local default version with current repository state.
- Create `macos-app/Tests/QiemanDashboardTests/Fixtures/post-snapshot.json`: shared post snapshot fixture.
- Create `macos-app/Tests/QiemanDashboardTests/Fixtures/platform-adjustments.json`: shared platform adjustment fixture.
- Create `macos-app/Tests/QiemanDashboardTests/ContractFixtureTests.swift`: Swift fixture assertions through `NativeSnapshotStore`.
- Create `tests/test_contract_fixtures.py`: Python fixture assertions through `dashboard.snapshot` and `dashboard.platform_fetcher`.
- Modify `.github/workflows/ci.yml` again after Python tests exist: add Python unittest discovery.

## Task 1: Add Regular CI Baseline

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create the CI workflow**

```yaml
name: CI

on:
  push:
    branches:
      - main
  pull_request:

jobs:
  swift:
    name: Swift build and tests
    runs-on: macos-15
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build Swift package
        run: swift build --package-path macos-app

      - name: Run Swift tests
        working-directory: macos-app
        run: swift test

  python:
    name: Python syntax check
    runs-on: macos-15
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Compile Python sources
        run: python3 -m compileall -q dashboard qieman_scraper.py qieman_community_scraper.py scripts
```

- [ ] **Step 2: Verify the Swift commands locally**

Run:

```bash
swift build --package-path macos-app
(cd macos-app && swift test)
```

Expected: both commands exit 0; `swift test` reports 42 tests passing before later tasks add tests.

- [ ] **Step 3: Verify the Python command locally**

Run:

```bash
python3 -m compileall -q dashboard qieman_scraper.py qieman_community_scraper.py scripts
```

Expected: command exits 0 with no output.

- [ ] **Step 4: Check whitespace**

Run:

```bash
git diff --check .github/workflows/ci.yml
```

Expected: no output and exit 0.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add regular validation workflow"
```

## Task 2: Move Download Progress Coverage Into XCTest

**Files:**
- Delete: `macos-app/Tests/DownloadProgressTests.swift`
- Create: `macos-app/Tests/QiemanDashboardTests/DownloadProgressTests.swift`

- [ ] **Step 1: Confirm the current test is not in XCTest**

Run:

```bash
(cd macos-app && swift test list | rg DownloadProgressTests)
```

Expected: command exits 1 with no matches.

- [ ] **Step 2: Add XCTest coverage for the real type**

Create `macos-app/Tests/QiemanDashboardTests/DownloadProgressTests.swift`:

```swift
import XCTest
@testable import QiemanDashboard

final class DownloadProgressTests: XCTestCase {
    func testPercentTextRoundsFraction() {
        XCTAssertEqual(AppSelfUpdateDownloadProgress(bytesReceived: 0, totalBytes: 100, fraction: 0).percentText, "0%")
        XCTAssertEqual(AppSelfUpdateDownloadProgress(bytesReceived: 50, totalBytes: 100, fraction: 0.5).percentText, "50%")
        XCTAssertEqual(AppSelfUpdateDownloadProgress(bytesReceived: 99, totalBytes: 100, fraction: 0.99).percentText, "99%")
        XCTAssertEqual(AppSelfUpdateDownloadProgress(bytesReceived: 999, totalBytes: 1_000, fraction: 0.999).percentText, "100%")
    }

    func testSizeTextIncludesTotalWhenTotalBytesAreKnown() {
        let progress = AppSelfUpdateDownloadProgress(bytesReceived: 1_024, totalBytes: 2_048, fraction: 0.5)

        XCTAssertTrue(progress.sizeText.contains("/"), progress.sizeText)
        XCTAssertFalse(progress.sizeText.isEmpty)
    }

    func testSizeTextOmitsTotalWhenTotalBytesAreUnknown() {
        let progress = AppSelfUpdateDownloadProgress(bytesReceived: 1_024, totalBytes: 0, fraction: 0)

        XCTAssertFalse(progress.sizeText.contains("/"), progress.sizeText)
        XCTAssertFalse(progress.sizeText.isEmpty)
    }
}
```

- [ ] **Step 3: Remove the standalone script-style test**

Delete `macos-app/Tests/DownloadProgressTests.swift`.

- [ ] **Step 4: Confirm XCTest discovers the migrated test**

Run:

```bash
(cd macos-app && swift test list | rg DownloadProgressTests)
```

Expected: output contains:

```text
QiemanDashboardTests.DownloadProgressTests/testPercentTextRoundsFraction
QiemanDashboardTests.DownloadProgressTests/testSizeTextIncludesTotalWhenTotalBytesAreKnown
QiemanDashboardTests.DownloadProgressTests/testSizeTextOmitsTotalWhenTotalBytesAreUnknown
```

- [ ] **Step 5: Run the focused test**

Run:

```bash
(cd macos-app && swift test --filter DownloadProgressTests)
```

Expected: 3 tests pass.

- [ ] **Step 6: Commit**

```bash
git add macos-app/Tests/QiemanDashboardTests/DownloadProgressTests.swift
git rm macos-app/Tests/DownloadProgressTests.swift
git commit -m "test: run download progress checks in XCTest"
```

## Task 3: Protect Cookie File Permissions

**Files:**
- Modify: `macos-app/Core/QiemanCookieManager.swift`
- Create: `macos-app/Tests/QiemanDashboardTests/QiemanCookieManagerTests.swift`

- [ ] **Step 1: Add failing permission tests**

Create `macos-app/Tests/QiemanDashboardTests/QiemanCookieManagerTests.swift`:

```swift
import XCTest
@testable import QiemanDashboard

final class QiemanCookieManagerTests: XCTestCase {
    func testPersistCookieHeaderWritesOwnerOnlyPermissions() throws {
        let cookieURL = try temporaryCookieURL()
        let manager = QiemanCookieManager(cookieFileURL: cookieURL)

        try manager.persistCookieHeader("access_token=abc; qm=test")

        XCTAssertEqual(try posixPermissions(at: cookieURL), 0o600)
    }

    func testLoadCookieStringTightensExistingReadableCookieFile() throws {
        let cookieURL = try temporaryCookieURL()
        try FileManager.default.createDirectory(at: cookieURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "access_token=abc".write(to: cookieURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: cookieURL.path)
        let manager = QiemanCookieManager(cookieFileURL: cookieURL)

        XCTAssertEqual(try manager.loadCookieString(), "access_token=abc")

        XCTAssertEqual(try posixPermissions(at: cookieURL), 0o600)
    }

    private func temporaryCookieURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("qieman-cookie-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("qieman.cookie", isDirectory: false)
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let value = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        return value.intValue
    }
}
```

- [ ] **Step 2: Run the focused tests and confirm they fail**

Run:

```bash
(cd macos-app && swift test --filter QiemanCookieManagerTests)
```

Expected: at least one assertion fails because `QiemanCookieManager` has not set owner-only permissions yet.

- [ ] **Step 3: Implement permission tightening**

Modify `macos-app/Core/QiemanCookieManager.swift`:

```swift
final class QiemanCookieManager {
    private static let ownerReadWritePermissions = NSNumber(value: Int16(0o600))
    private let cookieFileURL: URL?

    init(cookieFileURL: URL?) {
        self.cookieFileURL = cookieFileURL
    }

    func loadCookieString() throws -> String {
        guard let cookieFileURL else { return "" }
        guard FileManager.default.fileExists(atPath: cookieFileURL.path) else { return "" }
        try tightenCookieFilePermissionsIfNeeded()
        return try String(contentsOf: cookieFileURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }
```

Update both save paths:

```swift
        try FileManager.default.createDirectory(at: cookieFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try header.write(to: cookieFileURL, atomically: true, encoding: .utf8)
        try tightenCookieFilePermissionsIfNeeded()
```

```swift
        try FileManager.default.createDirectory(at: cookieFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try normalized.write(to: cookieFileURL, atomically: true, encoding: .utf8)
        try tightenCookieFilePermissionsIfNeeded()
```

Add the helper near the bottom of the class:

```swift
    private func tightenCookieFilePermissionsIfNeeded() throws {
        guard let cookieFileURL else { return }
        guard FileManager.default.fileExists(atPath: cookieFileURL.path) else { return }
        try FileManager.default.setAttributes(
            [.posixPermissions: Self.ownerReadWritePermissions],
            ofItemAtPath: cookieFileURL.path
        )
    }
```

- [ ] **Step 4: Run the focused tests and confirm they pass**

Run:

```bash
(cd macos-app && swift test --filter QiemanCookieManagerTests)
```

Expected: 2 tests pass.

- [ ] **Step 5: Run the full Swift test suite**

Run:

```bash
(cd macos-app && swift test)
```

Expected: all XCTest tests pass.

- [ ] **Step 6: Commit**

```bash
git add macos-app/Core/QiemanCookieManager.swift macos-app/Tests/QiemanDashboardTests/QiemanCookieManagerTests.swift
git commit -m "fix: protect qieman cookie file permissions"
```

## Task 4: Align Docs And Version Defaults

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `PROJECT_MAP.md`
- Modify: `CLAUDE.md`
- Modify: `scripts/build_macos_app.sh`

- [ ] **Step 1: Read the current release metadata**

Run:

```bash
python3 -m json.tool releases/macos/latest.json | sed -n '1,24p'
```

Expected: output shows version `2.7.10` and tag `v2.7.10`.

- [ ] **Step 2: Update the build script default version**

Change `scripts/build_macos_app.sh`:

```bash
APP_VERSION="${APP_VERSION:-2.7.10}"
```

- [ ] **Step 3: Update README build and structure text**

Change `README.md` build example:

```bash
APP_VERSION=2.7.10 bash scripts/build_macos_app.sh
```

Change the repository structure section so the Python dashboard entries read:

```text
├── dashboard/           # Python 本地看板服务包（路由、渲染、抓取协调、平台数据）
├── dashboard_server.py  # Python 本地看板入口
├── qieman_scraper.py    # 公开内容抓取
└── qieman_community_scraper.py  # 社区动态抓取
```

Keep the release flow wording unchanged except for stale version examples.

- [ ] **Step 4: Update AGENTS.md**

Apply these content updates:

```text
**当前线上版本**: v2.7.10（GitHub Release + `releases/macos/latest.json`）
```

```text
**技术栈**: SwiftUI + AppKit (macOS 14+) | Python 3 (零第三方依赖) | SPM 测试/校验 + swiftc 打包
```

```text
### Python 本地服务与爬虫（约 6925 行）
| 文件/目录 | 行数 | 职责 |
|---|---:|---|
| `dashboard_server.py` | 5 | Python 本地看板入口 |
| `dashboard/` | 5364 | HTTP 路由、HTML 渲染、平台数据、快照归一化、估值抓取 |
| `qieman_community_scraper.py` | 1175 | 社区动态爬虫：讨论、评论 |
| `qieman_scraper.py` | 381 | 且慢平台爬虫：文章、主理人、组合数据 |
```

```text
APP_VERSION=2.7.10 bash scripts/build_macos_app.sh  # → dist/macos-app/QiemanDashboard.app
```

```text
4. **Cookie 认证** — 且慢登录态通过 QiemanCookieManager 管理，当前保存为本地受权限保护的 `qieman.cookie` 文件；后续可迁移 Keychain
```

- [ ] **Step 5: Update PROJECT_MAP.md and CLAUDE.md**

Make these docs agree with the same facts:

```text
macOS 14+
SPM 测试/校验 + swiftc 打包
dashboard_server.py 是入口，dashboard/ 是 Python 服务包
Cookie 当前保存为本地受权限保护的 qieman.cookie 文件，不写 Keychain
当前线上版本 v2.7.10
```

- [ ] **Step 6: Scan for stale statements**

Run:

```bash
rg -n "2\\.2\\.50|2\\.3\\.1|2\\.7\\.8|5117|206KB|存 Keychain|无 SPM 构建|macOS 13" README.md AGENTS.md CLAUDE.md PROJECT_MAP.md scripts/build_macos_app.sh
```

Expected: no output and exit 1.

- [ ] **Step 7: Commit**

```bash
git add README.md AGENTS.md PROJECT_MAP.md CLAUDE.md scripts/build_macos_app.sh
git commit -m "docs: align project map and build metadata"
```

## Task 5: Add Dual-Channel Contract Fixtures

**Files:**
- Create: `macos-app/Tests/QiemanDashboardTests/Fixtures/post-snapshot.json`
- Create: `macos-app/Tests/QiemanDashboardTests/Fixtures/platform-adjustments.json`
- Create: `macos-app/Tests/QiemanDashboardTests/ContractFixtureTests.swift`
- Create: `tests/test_contract_fixtures.py`
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add the post snapshot fixture**

Create `macos-app/Tests/QiemanDashboardTests/Fixtures/post-snapshot.json`:

```json
{
  "group": {
    "group_id": 123,
    "group_name": "长赢指数投资计划",
    "manager_name": "ETF拯救世界",
    "manager_broker_user_id": "broker-001"
  },
  "meta": {
    "mode": "group-manager",
    "filters": {
      "prod_code": "LONG_WIN"
    }
  },
  "posts": [
    {
      "post_id": 9001,
      "group_id": 123,
      "group_name": "长赢指数投资计划",
      "broker_user_id": "broker-001",
      "user_name": "ETF拯救世界",
      "created_at": "2026-06-10 09:30",
      "title": "本周调仓说明",
      "content_text": "买入沪深300，继续保持均衡配置。",
      "like_count": 12,
      "comment_count": 3,
      "detail_url": "https://qieman.com/post/9001"
    },
    {
      "post_id": 9000,
      "group_id": 123,
      "group_name": "长赢指数投资计划",
      "broker_user_id": "broker-001",
      "user_name": "ETF拯救世界",
      "created_at": "2026-06-09 15:00",
      "title": "昨日市场复盘",
      "content_text": "继续观察估值变化。",
      "like_count": 8,
      "comment_count": 1,
      "detail_url": "https://qieman.com/post/9000"
    }
  ]
}
```

- [ ] **Step 2: Add the platform adjustment fixture**

Create `macos-app/Tests/QiemanDashboardTests/Fixtures/platform-adjustments.json`:

```json
[
  {
    "adjustmentId": 501,
    "adjustCreateTime": 1781040600000,
    "adjustTxnDate": 1781040600000,
    "comment": "样例调仓",
    "url": "https://qieman.com/articles/501",
    "orders": [
      {
        "orderCode": "022",
        "variety": "沪深300",
        "tradeUnit": 100,
        "postPlanUnit": 100,
        "strategyType": "宽基",
        "largeClass": "权益",
        "nav": "1.2345",
        "navDate": 1780954200000,
        "fund": {
          "fundCode": "000300",
          "fundName": "沪深300ETF联接"
        }
      },
      {
        "orderCode": "024",
        "variety": "中证红利",
        "tradeUnit": 20,
        "postPlanUnit": 0,
        "strategyType": "红利",
        "largeClass": "权益",
        "nav": "1.1111",
        "navDate": 1780954200000,
        "fund": {
          "fundCode": "000922",
          "fundName": "中证红利指数"
        }
      }
    ]
  }
]
```

- [ ] **Step 3: Add Swift contract coverage for post snapshots**

Create `macos-app/Tests/QiemanDashboardTests/ContractFixtureTests.swift`:

```swift
import XCTest
@testable import QiemanDashboard

final class ContractFixtureTests: XCTestCase {
    func testPostSnapshotFixtureMatchesSwiftNormalizer() throws {
        let raw = try loadJSONFixture(named: "post-snapshot.json")
        let fixtureURL = fixtureDirectory().appendingPathComponent("post-snapshot.json")

        let payload = NativeSnapshotStore().snapshot(
            from: raw,
            fileURL: fixtureURL,
            createdAt: "2026-06-12 12:00:00",
            includeRecords: true,
            persisted: false
        )

        XCTAssertEqual(payload.snapshotType, "posts")
        XCTAssertEqual(payload.mode, "group-manager")
        XCTAssertEqual(payload.title, "ETF拯救世界")
        XCTAssertEqual(payload.subtitle, "长赢指数投资计划")
        XCTAssertEqual(payload.count, 2)
        XCTAssertEqual(payload.records.first?.postId, 9001)
        XCTAssertEqual(payload.records.first?.title, "本周调仓说明")
        XCTAssertEqual(payload.stats.count, 2)
    }

    private func loadJSONFixture(named name: String) throws -> Any {
        let data = try Data(contentsOf: fixtureDirectory().appendingPathComponent(name))
        return try JSONSerialization.jsonObject(with: data)
    }

    private func fixtureDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
    }
}
```

- [ ] **Step 4: Add Python contract coverage for the same fixtures**

Create `tests/test_contract_fixtures.py`:

```python
import json
import unittest
from pathlib import Path
from unittest.mock import patch

from dashboard.platform_fetcher import build_platform_trade_data
from dashboard.snapshot import normalize_snapshot


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "macos-app" / "Tests" / "QiemanDashboardTests" / "Fixtures"


class ContractFixtureTests(unittest.TestCase):
    def test_post_snapshot_fixture_matches_python_normalizer(self) -> None:
        payload = normalize_snapshot(FIXTURES / "post-snapshot.json", include_records=True)

        self.assertEqual(payload["snapshot_type"], "posts")
        self.assertEqual(payload["mode"], "group-manager")
        self.assertEqual(payload["title"], "ETF拯救世界")
        self.assertEqual(payload["subtitle"], "长赢指数投资计划")
        self.assertEqual(payload["count"], 2)
        self.assertEqual(payload["records"][0]["post_id"], 9001)
        self.assertEqual(payload["records"][0]["title"], "本周调仓说明")
        self.assertEqual(payload["stats"]["count"], 2)

    def test_platform_adjustment_fixture_matches_python_builder_without_network(self) -> None:
        raw_items = json.loads((FIXTURES / "platform-adjustments.json").read_text(encoding="utf-8"))

        with patch("dashboard.platform_fetcher.preload_fund_market_data", return_value=({}, {})):
            payload = build_platform_trade_data("LONG_WIN", raw_items)

        self.assertTrue(payload["supported"])
        self.assertEqual(payload["prod_code"], "LONG_WIN")
        self.assertEqual(payload["count"], 2)
        self.assertEqual(payload["buy_count"], 1)
        self.assertEqual(payload["sell_count"], 1)
        self.assertEqual(payload["adjustment_count"], 1)
        self.assertEqual(payload["actions"][0]["adjustment_id"], 501)
        self.assertEqual(payload["actions"][0]["side"], "buy")
        self.assertEqual(payload["holdings"]["asset_count"], 1)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 5: Run the new Swift contract test**

Run:

```bash
(cd macos-app && swift test --filter ContractFixtureTests)
```

Expected: 1 Swift test passes.

- [ ] **Step 6: Run the new Python contract tests**

Run:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```

Expected: 2 Python tests pass.

- [ ] **Step 7: Add Python unittest discovery to CI**

Append this step after the Python compile step in `.github/workflows/ci.yml`:

```yaml
      - name: Run Python contract tests
        run: python3 -m unittest discover -s tests -p 'test_*.py'
```

- [ ] **Step 8: Run all Batch A verification commands**

Run:

```bash
(cd macos-app && swift test list)
(cd macos-app && swift test)
swift build --package-path macos-app
python3 -m compileall -q dashboard qieman_scraper.py qieman_community_scraper.py scripts tests
python3 -m unittest discover -s tests -p 'test_*.py'
```

Expected:

- `swift test list` includes `DownloadProgressTests` and `ContractFixtureTests`.
- `swift test` exits 0.
- `swift build --package-path macos-app` exits 0.
- Python compileall exits 0.
- Python unittest exits 0.

- [ ] **Step 9: Commit**

```bash
git add .github/workflows/ci.yml macos-app/Tests/QiemanDashboardTests/Fixtures macos-app/Tests/QiemanDashboardTests/ContractFixtureTests.swift tests/test_contract_fixtures.py
git commit -m "test: add qieman contract fixtures"
```

## Task 6: Final Batch A Verification

**Files:**
- Verify all files changed in Tasks 1-5.

- [ ] **Step 1: Inspect changed files**

Run:

```bash
git status --short
git log --oneline -n 6
```

Expected: working tree is clean after the task commits, and recent commits include the Batch A commits.

- [ ] **Step 2: Run complete verification**

Run:

```bash
(cd macos-app && swift test list)
(cd macos-app && swift test)
swift build --package-path macos-app
python3 -m compileall -q dashboard qieman_scraper.py qieman_community_scraper.py scripts tests
python3 -m unittest discover -s tests -p 'test_*.py'
rg -n "2\\.2\\.50|2\\.3\\.1|2\\.7\\.8|5117|206KB|存 Keychain|无 SPM 构建|macOS 13" README.md AGENTS.md CLAUDE.md PROJECT_MAP.md scripts/build_macos_app.sh
```

Expected:

- All build and test commands exit 0.
- The final `rg` exits 1 with no output because stale text is absent.

- [ ] **Step 3: Record Batch A result**

If all commands match expected output, report:

```text
Batch A complete. CI, XCTest wiring, cookie-file permissions, docs metadata, and initial contract fixtures are in place.
```

If any command fails, stop and report the exact command, exit code, and failing output before making more changes.

## Self-Review Notes

- Spec A1 maps to Task 1 and Task 5 Step 7.
- Spec A2 maps to Task 2.
- Spec A3 maps to Task 4.
- Spec A4 maps to Task 3.
- Spec A5 maps to Task 5.
- Batch B and Batch C are intentionally not implemented in this plan.
- Swift-side platform fixture normalization is not added in Batch A because the current Swift platform parser enriches payloads through network-backed fund quote/history loading. Python-side platform fixture coverage is added now, and Swift-side platform parser isolation belongs with Batch B's HTTP/client abstraction work.
