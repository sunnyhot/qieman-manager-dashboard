# Comprehensive Optimization Design

Date: 2026-06-12
Project: qieman-manager-dashboard

## Goal

Improve the project in three ordered batches:

1. Batch A: strengthen quality gates, test coverage wiring, documentation accuracy, cookie storage safety, and Swift/Python data-channel contract coverage.
2. Batch B: reduce architectural coupling and large-file pressure after the quality baseline is in place.
3. Batch C: add user-facing product improvements after the core workflow is easier to change safely.

The first implementation plan will cover Batch A only. Batch B and Batch C stay documented here so Batch A does not accidentally block or conflict with them.

## Current Context

The repository contains a macOS SwiftUI app, a Python local dashboard server, scraper scripts, release automation, and agent skills. Swift Package Manager is available for tests, while the release bundle is still built by `scripts/build_macos_app.sh` using direct `swiftc`.

Recent inspection found these facts:

- `swift test` currently runs 42 XCTest tests successfully.
- `python3 -m compileall -q dashboard qieman_scraper.py qieman_community_scraper.py scripts` succeeds.
- The only GitHub workflow is tag-triggered release publishing, so regular push or pull request changes have no CI gate.
- `macos-app/Tests/DownloadProgressTests.swift` is outside the configured test target path and is not listed by `swift test list`.
- Several docs and defaults are stale: checked-in update metadata is `v2.7.10`, while project docs still reference older versions; some docs describe the old monolithic `dashboard_server.py` shape.
- Project docs say cookie authentication is stored in Keychain, but the current implementation writes `qieman.cookie` as a local file.
- Swift native clients and Python scraper/dashboard code independently normalize similar Qieman payloads, which can drift without shared fixture checks.

## Batch A Scope

Batch A delivers a foundation for safer future changes. It intentionally avoids broad refactors or new product features.

### A1. Continuous Integration

Add a new GitHub Actions workflow for regular validation. It should run on `push` and `pull_request`.

Required jobs:

- Swift package test: `swift test` from `macos-app/`.
- Swift build check: `swift build --package-path macos-app`.
- Python syntax check: `python3 -m compileall -q dashboard qieman_scraper.py qieman_community_scraper.py scripts`.

The release workflow remains tag-only. Batch A does not change release publishing behavior.

### A2. Download Progress XCTest Wiring

Move the standalone download progress test into the configured XCTest target, or replace it with an XCTest file under `macos-app/Tests/QiemanDashboardTests/`.

The new test must import the app target with `@testable import QiemanDashboard` and exercise the real `AppSelfUpdateDownloadProgress` type rather than duplicating the struct in the test file.

Success criteria:

- `swift test list` includes download progress tests.
- `swift test` still passes.

### A3. Documentation And Version Metadata Accuracy

Update the docs that describe the project map and build commands so they match the current repository.

Required updates:

- Align current release references with `releases/macos/latest.json`.
- Describe `dashboard_server.py` as the entrypoint and `dashboard/` as the actual Python server package.
- Remove contradictory statements about SPM versus direct `swiftc`: SPM is used for build/test validation, and the app bundle script uses direct `swiftc`.
- Update build command examples to avoid stale default versions.
- Correct the cookie storage description so it matches the current file-backed implementation.

Batch A should keep docs concise. It does not need to regenerate every line-count table unless the table is touched for accuracy.

### A4. Cookie File Safety

Keep the current file-backed cookie design for compatibility with the Python fallback path, but make the storage safer.

Required behavior:

- When saving `qieman.cookie`, set POSIX permissions to owner-read/write only.
- Existing readable cookie files should be tightened opportunistically when loaded or saved.
- Documentation should clearly state that the current storage is a local protected file, not Keychain.

Out of scope for Batch A:

- Full Keychain migration.
- Cross-process token broker.
- Removing Python fallback cookie-file compatibility.

### A5. Swift/Python Contract Fixture Skeleton

Add the first contract-test structure for the dual data channels. The goal is to make future parser drift visible without building a large fixture framework immediately.

Required design:

- Store small JSON fixtures under a stable test fixture directory.
- Cover at least one post snapshot shape and one platform adjustment/holding shape if practical.
- Add Swift tests for the corresponding Swift normalization/parsing surface where accessible.
- Add a lightweight Python test or script that normalizes the same fixture through the Python path.

If direct cross-language equivalence is too large for the first pass, Batch A may create the fixture directory, add one representative fixture, and add one side's executable contract test. The implementation plan must call out any deferred second-side coverage explicitly.

## Batch B Direction

Batch B starts only after Batch A is green.

Planned work:

- Introduce lightweight HTTP client abstractions for Swift native clients so network behavior can be mocked and retried consistently.
- Split large model/client files by domain where the split improves testability: community, platform, portfolio, update, notification, and shared formatting/parsing.
- Continue reducing `AppModel` proxy pressure by moving views toward smaller observable state objects.
- Add targeted tests around retry, timeout, API error mapping, and parsing fallback behavior.

Batch B should proceed in small pull requests. It should not mix mechanical file splits with behavior changes unless the behavior change is covered by tests first.

## Batch C Direction

Batch C starts after core architecture changes are stable enough for user-facing work.

Planned work:

- Monthly report export to file, with month-based archive naming and reuse of existing Markdown generation.
- Manager watch backoff, duplicate notification suppression, and a visible status timeline.
- Import preview diff and undo for Alipay/portfolio imports.
- Better portfolio analysis based on persisted snapshots or historical NAV where available.

Batch C work should preserve the Chinese market convention already used by the app: red for gains and green for losses.

## Data Flow

Batch A does not change production data flow.

Existing flow remains:

- Swift app uses native Qieman clients for the primary path.
- Python local server and scraper scripts remain available for fallback and debugging.
- Local JSON and cookie files remain under the app data directory.

The only data-flow addition in Batch A is test-only fixture flow:

- Fixture JSON is read by tests.
- Swift and Python normalization code consume the same representative samples where feasible.
- Tests assert stable IDs, titles, counts, dates, and selected numeric fields rather than comparing entire large payloads.

## Error Handling

Batch A error-handling changes are intentionally narrow:

- CI failures should fail fast and show the exact command that failed.
- Cookie permission tightening should not delete or corrupt an existing cookie. If permission changes fail, the save/load path should surface the existing error behavior or log context through existing app error channels.
- Contract tests should prefer small, stable assertions so unrelated upstream payload fields do not cause noisy failures.

## Testing Plan

Batch A verification commands:

- `swift test list`
- `swift test`
- `swift build --package-path macos-app`
- `python3 -m compileall -q dashboard qieman_scraper.py qieman_community_scraper.py scripts`

Additional checks:

- Inspect GitHub workflow YAML for correct triggers.
- Confirm docs no longer contain stale version references for the current release.
- Confirm `DownloadProgressTests` is listed by `swift test list`.

## Rollout

Batch A can be merged as one focused quality-baseline change if all checks pass.

Batch B and Batch C should be planned separately after Batch A lands. Their implementation plans should reference this design but should not be bundled into the first patch set.

## Non-Goals

- No broad UI redesign in Batch A.
- No production API endpoint changes in Batch A.
- No full Keychain migration in Batch A.
- No large model/client split in Batch A.
- No new investment analysis product feature in Batch A.
