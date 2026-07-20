# Native application and CLI routing

Set `QIEMAN_PROJECT_DIR` to the repository and invoke `$QIEMAN_PROJECT_DIR/scripts/qieman`.

## Native UI

```bash
scripts/qieman app-open
```

Use the SwiftUI application for interactive portfolio, forum, platform, settings and workbench tasks.

## Community

```bash
scripts/qieman following-posts --user-name "ETF拯救世界"
scripts/qieman group-posts --prod-code LONG_WIN
scripts/qieman following-users
scripts/qieman my-groups
scripts/qieman space-items --space-user-id 123456
```

## Platform and valuation

```bash
scripts/qieman platform-actions --prod-code LONG_WIN
scripts/qieman platform-holdings --prod-code LONG_WIN
scripts/qieman platform-timeline --prod-code LONG_WIN
scripts/qieman platform-monthly --prod-code LONG_WIN --months 12
scripts/qieman valuation --fund-codes 021550,001052
```

## Authentication

The default Cookie path is `~/Library/Application Support/QiemanDashboard/qieman.cookie`. Override it with `--cookie-file`. Never expose the Cookie content.

## Removed modes

There is no localhost dashboard, HTTP route, Python crawler, OCR, image import, or spreadsheet import.
