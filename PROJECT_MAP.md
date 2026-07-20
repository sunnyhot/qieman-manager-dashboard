# PROJECT_MAP — Qieman Manager Dashboard

## Architecture

The project is macOS-only and uses a pure Swift runtime.

```text
QiemanDashboardApp (SwiftUI)
  └─ AppModel (@MainActor)
      ├─ QiemanNativeClient              community/auth/comments
      ├─ QiemanPlatformNativeClient      trades/holdings/NAV/estimates
      ├─ ApplicationDataController       local data directory and Cookie path
      ├─ Stores                          portfolio/plans/trades/snapshots
      └─ Views                           overview/portfolio/platform/forum/workbench/settings

qieman-cli (Swift)
  └─ QiemanCommandLine
      ├─ shares the native clients and models
      └─ emits stable snake_case JSON for Agent skills
```

There is no Python Web dashboard, localhost HTTP service, Python crawler, OCR, image import, or spreadsheet import.

## Important paths

| Path | Responsibility |
|---|---|
| `macos-app/QiemanDashboardApp.swift` | App entry |
| `macos-app/Core/AppModel.swift` | Main state container |
| `macos-app/Core/QiemanNativeClient.swift` | Qieman community native client |
| `macos-app/Core/QiemanPlatformNativeClient.swift` | Platform, quote and valuation native client |
| `macos-app/Core/QiemanCommandLine.swift` | CLI commands and JSON contracts |
| `macos-app/CLI/main.swift` | CLI process entry |
| `macos-app/Core/ApplicationDataController.swift` | App data directory management |
| `macos-app/Core/Models.swift` | Shared domain models |
| `macos-app/Views/` | SwiftUI views |
| `macos-app/Tests/QiemanDashboardTests/` | XCTest suite |
| `scripts/build_macos_app.sh` | Release-compatible App build |
| `scripts/build_qieman_cli.sh` | Native CLI build |
| `scripts/qieman` | CLI launcher |
| `skills/qieman-alpha-signals/` | Atomic Agent command routing |
| `skills/qieman-manager-dashboard/` | Native App/CLI Agent routing |

## Commands

```bash
cd macos-app && swift test
bash scripts/build_qieman_cli.sh
scripts/qieman version
APP_VERSION=3.2.1 bash scripts/build_macos_app.sh
```

## Contracts

- App persisted JSON remains Codable and backward compatible.
- Agent CLI JSON uses snake_case field names.
- Cookie defaults to `~/Library/Application Support/QiemanDashboard/qieman.cookie` and must never be printed.
- Chinese market colors remain red-up and green-down through `AppPalette`.
