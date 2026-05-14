     1|# AGENTS.md — 且慢理财 Dashboard (qieman-manager-dashboard)
     2|
     3|## 项目简介
     4|
     5|macOS 原生 SwiftUI 应用 + Python HTTP 服务器，管理且慢（Qieman）投资平台数据。
     6|- 本地 dashboard 展示基金持仓、净值走势、社区动态
     7|- Python 爬虫抓取且慢平台数据（scraper），SwiftUI 前端渲染
     8|- 支持支付宝持仓导入、自动更新、菜单栏小组件
     9|- 中国股市惯例：红色涨、绿色跌
    10|
    11|**技术栈**: SwiftUI + AppKit (macOS 13+) | Python 3 (零第三方依赖) | swiftc 直接编译（无 SPM/Xcode 工程）
    12|
    13|## 文件结构
    14|
    15|### 顶层文件
    16|| 文件 | 大小 | 职责 |
    17||---|---|---|
    18|| `dashboard_server.py` | 206KB | Python HTTP 服务器（主后端）：路由、数据管理、API 代理、且慢数据抓取、持仓 CRUD |
    19|| `qieman_scraper.py` | ~15KB | 且慢平台爬虫：文章、主理人、组合数据 |
    20|| `qieman_community_scraper.py` | ~10KB | 且慢社区爬虫：社区讨论、评论 |
    21|| `README.md` | — | 项目说明 |
    22|
    23|### macos-app/ — SwiftUI 原生前端
    24|
    25|#### 入口
    26|| 文件 | 职责 |
    27||---|---|
    28|| `QiemanDashboardApp.swift` | App 入口，@main |
    29|| `Package.swift` | SPM 配置（474B，极简） |
    30|
    31|#### Core/（核心逻辑）
    32|| 文件 | 职责 |
    33||---|---|
    34|| `AppModel.swift` | **核心状态容器**：@MainActor ObservableObject，@EnvironmentObject 注入全局 |
    35|| `Models.swift` | 数据模型：基金、持仓、净值、交易记录等 |
    36|| `DashboardAPI.swift` | Dashboard API 客户端（本地服务器通信） |
    37|| `QiemanNativeClient.swift` | 且慢原生 API 客户端（~62KB，直接调且慢接口） |
    38|| `QiemanPlatformNativeClient.swift` | 且慢平台原生客户端 |
    39|| `QiemanCookieManager.swift` | Cookie 管理（且慢登录态） |
    40|| `ServerController.swift` | Python 服务器生命周期管理（启动/停止/端口检测） |
    41|| `AppSelfUpdater.swift` | App 自动更新（GitHub Release） |
    42|| `AppUpdateChecker.swift` | 更新检查逻辑 |
    43|| `NativeSnapshotStore.swift` | 数据快照持久化 |
    44|| `PersonalAssetAutomation.swift` | 个人资产自动化 |
    45|| `PersonalAssetSorting.swift` | 资产排序逻辑 |
    46|| `PersonalImportRecognizer.swift` | 支付宝导入识别 |
    47|| `UserPortfolioStore.swift` | 用户持仓存储 |
    48|| `InvestmentPlansStore.swift` | 投资计划存储 |
    49|| `PendingTradesStore.swift` | 待处理交易存储 |
    50|| `ManagerWatchStore.swift` | 主理人关注存储 |
    51|| `LocalNotificationManager.swift` | 本地通知管理 |
    52|
    53|#### Views/（SwiftUI 视图）
    54|| 文件 | 职责 |
    55||---|---|
    56|| `ContentView.swift` | 主内容视图 |
    57|| `OverviewSectionView.swift` | 总览板块 |
    58|| `PortfolioSectionView.swift` | 持仓板块 |
    59|| `PlatformSectionView.swift` | 平台板块 |
    60|| `ForumSectionView.swift` | 社区论坛板块 |
    61|| `PersonalAssetBrowser.swift` | **最大视图**（~66KB）：个人资产浏览器 |
    62|| `PersonalAssetCards.swift` | 资产卡片组件 |
    63|| `MenuBarPortfolioView.swift` | 菜单栏持仓小组件 |
    64|| `QiemanLoginView.swift` | 且慢登录视图 |
    65|| `SettingsSectionView.swift` | 设置主视图 |
    66|| `SettingsAccountPanel.swift` | 账户设置面板 |
    67|| `SettingsAppPanel.swift` | 应用设置面板 |
    68|| `SettingsWatchPanel.swift` | 关注设置面板 |
    69|| `SettingsMenuBarPanel.swift` | 菜单栏设置面板 |
    70|| `SettingsComponents.swift` | 设置通用组件 |
    71|| `SharedComponents.swift` | 通用 UI 组件 |
    72|| `ForumComponents.swift` | 论坛专用组件 |
    73|| `PlatformComponents.swift` | 平台专用组件 |
    74|
    75|#### Design/
    76|| 文件 | 职责 |
    77||---|---|
    78|| `AppPalette.swift` | 设计系统：颜色/字体/间距常量 |
    79|
    80|#### Support/
    81|| 文件 | 职责 |
    82||---|---|
    83|| `ValueFormatting.swift` | 数值格式化工具（百分比、金额等） |
    84|
    85|#### Tests/
    86|| 文件 | 职责 |
    87||---|---|
    88|| `DownloadProgressTests.swift` | 下载进度测试 |
    89|
    90|### scripts/
    91|| 文件 | 职责 |
    92||---|---|
    93|| `build_macos_app.sh` | Swift 编译构建脚本 |
    94|| `render_macos_icon.swift` | App 图标生成 |
    95|| `import_alipay_portfolio.py` | 支付宝持仓导入 |
    96|| `import_alipay_investment_plans.py` | 支付宝投资计划导入 |
    97|| `import_alipay_pending_trades.py` | 支付宝待处理交易导入 |
    98|| `prepare_personal_import.py` | 导入数据预处理 |
    99|
   100|### releases/
   101|| 文件 | 职责 |
   102||---|---|
   103|| `macos/latest.json` | 自动更新元数据（版本号、下载 URL） |
   104|
   105|### skills/（Multica 技能文件）
   106|| 路径 | 说明 |
   107||---|---|
   108|| `skills/qieman-manager-dashboard/SKILL.md` | 且慢 dashboard 项目技能 |
   109|| `skills/qieman-alpha-signals/SKILL.md` | 且慢 alpha 信号技能 |
   110|
   111|## 构建命令
   112|
   113|```bash
   114|# 构建 macOS App
   115|bash scripts/build_macos_app.sh      # swiftc 编译 → .app bundle
   116|
   117|# 启动 Python 服务器（调试）
   118|python3 dashboard_server.py
   119|
   120|# 生成图标
   121|swift scripts/render_macos_icon.swift
   122|```
   123|
   124|**构建要求**: macOS 13+, Xcode CLI Tools, Python 3.9+
   125|
   126|## 架构概览
   127|
   128|```
   129|QiemanDashboardApp (@main)
   130|  └─ AppModel (@MainActor ObservableObject, @EnvironmentObject)
   131|       ├─ ServerController → dashboard_server.py (Python HTTP)
   132|       ├─ QiemanNativeClient (且慢 API 直连)
   133|       ├─ QiemanPlatformNativeClient (平台 API)
   134|       ├─ DashboardAPI (本地服务器通信)
   135|       ├─ Views/
   136|       │    ├─ ContentView (主视图)
   137|       │    ├─ OverviewSectionView (总览)
   138|       │    ├─ PortfolioSectionView (持仓)
   139|       │    ├─ PlatformSectionView (平台)
   140|       │    ├─ ForumSectionView (论坛)
   141|       │    └─ PersonalAssetBrowser (资产浏览器, 66KB)
   142|       └─ Stores (持仓/计划/交易/关注/快照)
   143|```
   144|
   145|**双数据通道**:
   146|1. **原生 Swift** — QiemanNativeClient 直连且慢 API（主路径，快）
   147|2. **Python 服务器** — dashboard_server.py 作为本地 HTTP 后端（备用/调试）
   148|
   149|## 关键约定
   150|
   151|1. **@MainActor + ObservableObject** — AppModel 是单一状态容器，所有 View 通过 @EnvironmentObject 访问
   152|2. **中国股市惯例** — 红涨绿跌，所有涨跌颜色用 AppPalette 统一
   153|3. **Python 零依赖** — dashboard_server.py 不用任何 pip 包，纯标准库
   154|4. **Cookie 认证** — 且慢登录态通过 QiemanCookieManager 管理，存 Keychain
   155|5. **自动更新** — GitHub Release + latest.json，AppSelfUpdater 处理下载安装
   156|6. **数据持久化** — SQLite/JSON 文件混合，通过各 Store 类管理
   157|
   158|## 已知坑点
   159|
   160|1. **dashboard_server.py 巨大 (206KB)** — 单文件包含所有后端逻辑，修改需精确定位
   161|2. **PersonalAssetBrowser.swift 巨大 (66KB)** — 资产浏览器视图未拆分
   162|3. **QiemanPlatformNativeClient.swift (62KB)** — 且慢 API 客户端庞大，接口多
   163|4. **双数据通道** — Swift 原生和 Python 服务器两套数据源，需注意一致性
   164|5. **Python 服务器端口冲突** — ServerController 需检测端口占用
   165|6. **无 SPM 构建** — 用 swiftc 直接编译，无包管理
   166|7. **且慢 API 可能变动** — 非公开 API，随时可能变更需维护
   167|8. **支付宝导入格式** — 依赖支付宝导出 CSV 格式，格式变更需更新识别逻辑
   168|