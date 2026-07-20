# CLAUDE.md — 且慢主理人看板 (qieman-manager-dashboard)

## 项目概览

macOS 原生 SwiftUI 应用 + Swift CLI，管理且慢（Qieman）投资平台数据。
- 本地 dashboard 展示基金持仓、净值走势、社区动态
- Swift 原生客户端抓取且慢平台数据，SwiftUI 前端渲染
- 支持 App 内手工维护持仓、自动更新、菜单栏小组件
- 中国股市惯例：红色涨、绿色跌

**技术栈**: SwiftUI + AppKit + Foundation (macOS 14+) | SPM 测试/校验 + swiftc 打包
**数据通道**: Swift 原生 API 直连；Agent 技能调用原生 `qieman-cli`
**当前发布版本**: v3.2.0（GitHub Release + `releases/macos/latest.json`）

## 目录结构与行数

### 原生命令行
`macos-app/Core/QiemanCommandLine.swift` 提供登录、动态、评论、调仓、持仓、估值和巡检命令；`scripts/qieman` 为启动器。

### macos-app/ — SwiftUI 原生 App（58 个 Swift 文件，21426 行）

#### 入口与配置
| 文件 | 行数 | 职责 |
|---|---|---|
| `QiemanDashboardApp.swift` | 359 | App 入口 @main |
| `Package.swift` | 19 | SPM 配置（极简） |

#### Core/ 核心逻辑（~8700 行）
| 文件 | 行数 | 职责 |
|---|---|---|
| `Core/Models.swift` | 1644 | 数据模型：基金、持仓、净值、交易记录等 |
| `Core/QiemanPlatformNativeClient.swift` | 1460 | 且慢平台原生客户端（最大 API 客户端） |
| `Core/QiemanNativeClient.swift` | 1103 | 且慢原生 API 客户端 |
| `Core/AppModel.swift` | 283 | **核心状态容器**：@MainActor ObservableObject |
| `Core/AppModel/PortfolioCRUD.swift` | 612 | 持仓 CRUD 操作 |
| `Core/AppModel/Validation.swift` | 432 | 数据验证 |
| `Core/AppModel/AssetAggregation.swift` | 354 | 资产汇总计算 |
| `Core/AppModel/ManagerWatch.swift` | 326 | 主理人关注 |
| `Core/AppModel/InvestmentPlan.swift` | 264 | 投资计划模型 |
| `Core/AppModel/Auth.swift` | 238 | 认证逻辑 |
| `Core/AppModel/Import.swift` | 234 | 导入逻辑 |
| `Core/AppModel/PendingTrade.swift` | 176 | 待处理交易 |
| `Core/AppModel/PortfolioRefresh.swift` | 144 | 持仓刷新 |
| `Core/AppModel/DataDirectory.swift` | 82 | 数据目录管理 |
| `Core/AppModel/ComputedProperties.swift` | 192 | 计算属性 |
| `Core/AppModel/Update.swift` | 99 | 更新逻辑 |
| `Core/ApplicationDataController.swift` | 本地数据目录与 Cookie 路径管理 |
| `Core/AppSelfUpdater.swift` | 357 | App 自动更新（GitHub Release） |
| `Core/AppUpdateChecker.swift` | 210 | 更新检查 |
| `Core/NativeSnapshotStore.swift` | 365 | 数据快照持久化 |
| `Core/UserPortfolioStore.swift` | 353 | 用户持仓存储 |
| `Core/InvestmentPlansStore.swift` | 180 | 投资计划存储 |
| `Core/PendingTradesStore.swift` | 169 | 待处理交易存储 |
| `Core/PersonalAssetAutomation.swift` | 444 | 个人资产自动化 |
| `Core/PersonalAssetSorting.swift` | 88 | 资产排序 |
| `Core/ManagerWatchStore.swift` | 23 | 主理人关注存储 |
| `Core/DashboardAPI.swift` | 105 | Dashboard API 客户端 |
| `Core/QiemanCookieManager.swift` | 148 | Cookie 管理（且慢登录态） |
| `Core/LocalNotificationManager.swift` | 65 | 本地通知 |
| `Core/MenuBarTicker/` | 989 | 菜单栏小组件（Entries/Settings/Kind/Types） |

#### Views/ 视图（~7300 行）
| 文件 | 行数 | 职责 |
|---|---|---|
| `Views/PersonalAssetBrowser.swift` | 1572 | **最大视图**：个人资产浏览器 |
| `Views/PlatformComponents.swift` | 970 | 平台专用组件 |
| `Views/OverviewSectionView.swift` | 804 | 总览板块 |
| `Views/QiemanLoginView.swift` | 778 | 登录视图 |
| `Views/SettingsMenuBarPanel.swift` | 760 | 菜单栏设置面板 |
| `Views/PersonalAssetCards.swift` | 629 | 资产卡片组件 |
| `Views/ContentView.swift` | 565 | 主内容视图 |
| `Views/PlatformSectionView.swift` | 452 | 平台板块 |
| `Views/MenuBarPortfolioView.swift` | 362 | 菜单栏持仓小组件 |
| `Views/ForumComponents.swift` | 252 | 论坛组件 |
| `Views/SharedComponents.swift` | 300 | 通用 UI 组件 |
| `Views/PortfolioSectionView.swift` | 287 | 持仓板块 |
| `Views/ForumSectionView.swift` | 219 | 论坛板块 |
| `Views/SettingsSectionView.swift` | 218 | 设置主视图 |
| `Views/SettingsComponents.swift` | 231 | 设置通用组件 |
| `Views/SettingsWatchPanel.swift` | 182 | 关注设置面板 |
| `Views/SettingsAccountPanel.swift` | 133 | 账户设置面板 |
| `Views/SettingsAppPanel.swift` | 79 | 应用设置面板 |

#### 其他
| 文件 | 行数 | 职责 |
|---|---|---|
| `Design/AppPalette.swift` | 74 | 设计系统：颜色/字体/间距 |
| `Support/ValueFormatting.swift` | 80 | 数值格式化工具 |
| `Tests/` | 224 | 测试（DownloadProgressTests + PersonalAssetSortingTests） |

### scripts/（287 行）
| 文件 | 行数 | 职责 |
|---|---|---|
| `scripts/render_macos_icon.swift` | 151 | App 图标生成 |
| `scripts/build_macos_app.sh` | 136 | Swift 编译构建脚本 |

### releases/
| 文件 | 职责 |
|---|---|
| `releases/macos/latest.json` | 自动更新元数据（版本号、下载 URL） |

### skills/
Agent 技能层（qieman-manager-dashboard、qieman-alpha-signals、project-map）

## 构建与运行命令

```bash
# 构建 macOS App
APP_VERSION=3.2.0 bash scripts/build_macos_app.sh  # → dist/macos-app/QiemanDashboard.app

# 运行
open dist/macos-app/QiemanDashboard.app

# 构建/运行原生 CLI
bash scripts/build_qieman_cli.sh
scripts/qieman version

# 运行测试
swift test  # 在 macos-app/ 目录下
```

**构建要求**: macOS 14+, Xcode CLI Tools

## 架构与数据流

```
QiemanDashboardApp (@main)
  └─ AppModel (@MainActor ObservableObject, @EnvironmentObject)
       ├─ ApplicationDataController (本地数据目录)
       ├─ QiemanNativeClient (且慢 API 直连, 主路径)
       ├─ QiemanPlatformNativeClient (平台 API)
       ├─ Views/
       │    ├─ ContentView → Overview/Portfolio/Platform/Forum 四板块
       │    ├─ PersonalAssetBrowser (资产浏览器, 1572 行)
       │    └─ SettingsSectionView (设置面板)
       ├─ MenuBarTicker (菜单栏小组件)
       └─ Stores (持仓/计划/交易/关注/快照, 各独立 Store)
```

**数据通道**: App 和 CLI 直接复用 Swift 原生客户端。

## 关键约定

1. **@MainActor + ObservableObject** — AppModel 是单一状态容器，所有 View 通过 @EnvironmentObject 访问
2. **中国股市惯例** — 红涨绿跌，所有涨跌颜色用 AppPalette 统一
3. **纯 Swift 运行时** — 不依赖 Python、本地 HTTP 服务、OCR 或表格导入
4. **Cookie 认证** — 且慢登录态通过 QiemanCookieManager 管理，当前保存为本地受权限保护的 `qieman.cookie` 文件；后续可迁移 Keychain
5. **自动更新** — GitHub Release + latest.json，AppSelfUpdater 处理下载安装
6. **数据持久化** — SQLite/JSON 文件混合，通过各 Store 类管理
7. **AppModel 拆分** — 核心状态在 AppModel.swift，子功能拆到 AppModel/ 子目录

## 已知坑点

1. **PersonalAssetBrowser.swift 较大** — 修改需避免顺手重排无关 UI
2. **QiemanPlatformNativeClient.swift 较大** — 且慢 API 和行情回退逻辑集中
3. **Models.swift 较大** — 数据模型集中在一个文件
4. **CLI JSON 契约** — Agent 消费 snake_case 字段，修改需补契约测试
5. **且慢 API 非公开** — 随时可能变更需维护

## Agent 工作指南

- 修改 UI 时注意涨跌颜色用 AppPalette（红涨绿跌）
- CLI 修改优先定位 `Core/QiemanCommandLine.swift`，保持 snake_case JSON 契约
- Swift App 入口在 `macos-app/QiemanDashboardApp.swift`
- AppModel 是全局状态中心，拆分子文件在 `macos-app/Core/AppModel/`
- 构建必须指定版本号：`APP_VERSION=x.y.z bash scripts/build_macos_app.sh`
- 发布流程：构建 → GitHub Release 上传 zip → 更新 `releases/macos/latest.json`
- 参考 `PROJECT_MAP.md` 获取更详细的架构说明
