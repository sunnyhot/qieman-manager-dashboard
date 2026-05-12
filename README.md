# 且慢主理人看板 / Qieman Manager Dashboard

> 本地 macOS 原生 App：主理人论坛与调仓追踪、个人持仓管理、菜单栏实时估值、系统通知推送。

## 功能

- **主理人内容** — 抓取论坛发言、平台调仓，支持关键词/作者过滤、评论查看、月度交易总览
- **个人持仓** — 手动录入 / 图片 OCR / 表格导入，支持持仓、待确认买入、定投计划管理
- **菜单栏估值** — 常驻菜单栏显示总资产、今日涨跌、每只持仓实时估值，支持排序
- **通知巡检** — 定时监控主理人调仓与发言，系统通知推送，点击跳转详情
- **自动更新** — 启动后检查 GitHub Release，一键下载安装新版本

## 构建

```bash
APP_VERSION=2.2.43 bash scripts/build_macos_app.sh
```

产物：`dist/macos-app/QiemanDashboard.app`，分发包输出到 `/tmp/`。

## 运行

```bash
open dist/macos-app/QiemanDashboard.app
```

## 发布

```bash
# 1. 构建
APP_VERSION=2.2.43 bash scripts/build_macos_app.sh

# 2. 在 GitHub 创建 Release 并上传 /tmp/QiemanDashboard-2.2.43.zip

# 3. 更新 releases/macos/latest.json 中的版本号和下载链接，提交推送
```

App 通过 `raw.githubusercontent.com` 读取 `latest.json` 检查更新。

## 仓库结构

```
├── macos-app/           # SwiftUI 原生 App 源码
├── scripts/             # 构建、图标、辅助脚本
├── skills/              # Agent 技能层（增量巡检、估值查询等）
├── releases/macos/      # latest.json 更新清单
├── dashboard_server.py  # 浏览器版看板（调试用）
├── qieman_scraper.py    # 公开内容抓取
└── qieman_community_scraper.py  # 社区动态抓取
```

## 环境

- macOS 14+，Xcode Command Line Tools（`swiftc`、`iconutil`、`codesign`）
- Python 3.x，零第三方依赖
- 当前为 ad-hoc 签名，适合自用；对外分发需 Apple Developer 证书 + 公证
