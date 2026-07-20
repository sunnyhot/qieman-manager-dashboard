# 且慢主理人看板 / Qieman Manager Dashboard

> 纯原生 macOS App：主理人论坛与调仓追踪、个人持仓管理、菜单栏实时估值、系统通知推送。

## 功能

- **主理人内容** — 抓取论坛发言、平台调仓，支持关键词/作者过滤、评论查看、月度交易总览
- **个人持仓** — App 内手动录入，支持持仓、待确认买入、定投计划管理
- **菜单栏估值** — 常驻菜单栏显示总资产、今日涨跌、每只持仓实时估值，支持排序
- **通知巡检** — 定时监控主理人调仓与发言，系统通知推送，点击跳转详情
- **自动更新** — 启动后检查 GitHub Release，一键下载安装新版本
- **原生命令行** — Swift CLI 提供登录、动态、评论、调仓、持仓、估值和增量巡检

## 构建

```bash
APP_VERSION=3.2.2 bash scripts/build_macos_app.sh
```

产物：`dist/macos-app/QiemanDashboard.app`，分发包输出到 `/tmp/`。

## 运行

```bash
open dist/macos-app/QiemanDashboard.app
```

## 原生 CLI

```bash
# 首次调用自动编译 Swift CLI
scripts/qieman version
scripts/qieman following-posts --user-name "ETF拯救世界"
scripts/qieman platform-holdings --prod-code LONG_WIN
```

项目仅支持 macOS，不依赖 Python 或本地 HTTP 服务。图片、OCR、CSV、TSV、JSON、XLSX 和支付宝专用导入已移除；个人资产继续支持 App 内手工维护。

## 发布流程

发布由 GitHub Actions 自动完成，配置在 `.github/workflows/release.yml`。推送 `v*` tag 后，Actions 会构建 macOS App、创建 GitHub Release、上传 zip，并提交更新 `releases/macos/latest.json`。

App 通过 GitHub Release asset 读取 `latest.json` 检查更新（URL: `https://github.com/<owner>/<repo>/releases/latest/download/latest.json`）。推送 tag 后 Actions 会自动构建 App、生成包含 sha256 的 `latest.json`、上传到 Release asset 并同步更新 `main` 分支的 `releases/macos/latest.json`。

1. 确认要发布的代码已经提交，并同步到最新 `main`。

```bash
git status --short --branch
git pull --rebase origin main
swift build --package-path macos-app
```

2. 选择新版本号并推送 tag。tag 必须以 `v` 开头；Actions 会把 `v2.5.3` 转成 App 版本号 `2.5.3`，并写入 `CFBundleShortVersionString`。

```bash
VERSION=2.5.3
TAG="v$VERSION"
git tag -a "$TAG" -m "$TAG"
git push origin main "$TAG"
```

3. 等待 GitHub Actions 完成 `Build & Release` workflow。

```bash
git ls-remote origin main
```

打开仓库的 Actions 页面查看构建状态，或用 `git ls-remote origin main` 观察 `main` 是否出现新的 bot commit。workflow 成功后应完成这些动作：

- 构建 `/tmp/QiemanDashboard-$VERSION.zip`
- 创建 GitHub Release：`https://github.com/sunnyhot/qieman-manager-dashboard/releases/tag/$TAG`
- 上传 `QiemanDashboard-$VERSION.zip`
- 提交 `release: update $TAG` 到 `main`，更新 `releases/macos/latest.json`

4. 验证更新源和下载包。

先确认本地拿到 Actions 回写的 `latest.json` commit：

```bash
git pull --rebase origin main
git show --no-patch --format='%h %an <%ae> | %s' HEAD
plutil -p releases/macos/latest.json
```

再检查线上更新清单和 Release asset：

```bash
curl -fsSL "https://github.com/sunnyhot/qieman-manager-dashboard/releases/latest/download/latest.json"
curl -I -L "https://github.com/sunnyhot/qieman-manager-dashboard/releases/download/$TAG/QiemanDashboard-$VERSION.zip"
```

确认 `latest.json` 已返回新 `tag_name` 且包含 `sha256` 字段，且 zip 地址返回 `200` 并带有合理的 `content-length`。Release asset 通过 CDN 分发，通常立即可用。如果用户 App 已经是同版本，检查更新会正常显示没有更新。

5. 如果 Actions 失败，可在本地临时复现构建问题：

```bash
APP_VERSION="$VERSION" SIGN_IDENTITY="-" TARGET_ARCH=arm64 bash scripts/build_macos_app.sh
unzip -t "/tmp/QiemanDashboard-$VERSION.zip"
```

本地构建只用于排错；正常发版不要手动上传 zip 或手动改 `latest.json`，以免和 Actions 的自动流程不一致。

## 仓库结构

```
├── macos-app/           # SwiftUI 原生 App 源码
│   ├── Core/            # 原生 API、状态、存储和 Swift CLI 共享逻辑
│   └── CLI/             # qieman-cli 入口
├── scripts/             # App/CLI 构建与 qieman 启动器
├── skills/              # Agent 技能层（调用原生 Swift CLI）
└── releases/macos/      # latest.json 更新清单
```

## 环境

- macOS 14+，Xcode Command Line Tools（`swiftc`、`iconutil`、`codesign`）
- 当前为 ad-hoc 签名，适合自用；对外分发需 Apple Developer 证书 + 公证
