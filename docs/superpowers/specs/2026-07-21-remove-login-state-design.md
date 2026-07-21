# 删除「登录态」功能 — 设计文档

- **日期**: 2026-07-21
- **作者**: xufan65（与 ZCode 协作）
- **状态**: Draft，待用户审阅
- **影响版本**: 下一个 release（建议 v3.4.0）

## 1. 背景与动机

当前 App 的登录态（Cookie）体系承担两类能力：

1. **身份相关**：关注动态、我的关注用户、我的小组、登录态校验。这些接口在且慢服务端必须登录才能调，代码层有 `missingCookie` 守卫。
2. **半相关**：评论 `fetchComments`（不强制登录，但服务端策略下未登录常失败）。

经实测和代码确认：

- 平台调仓（`QiemanPlatformNativeClient`）**完全不带 cookie**，纯公开。
- 主理人小组发言、个人空间动态走 `cookie: nil`，**未登录也能拿**。
- 只有「关注/我的」这类个人关系链接口才真需要登录。

用户决定：**彻底删除登录态，连同必须登录才能用的功能一并删除**，只保留匿名可用的公开数据源。评论功能保留（接受未登录下可能拿不到数据的现状，UI 文案不再误导用户去登录）。

进一步决定：**「个人空间动态」（spaceItems）功能也一并删除**。理由：删登录态后 `resolveSpaceUserID` 失去从 userName/brokerUserID 反查 spaceUserId 的能力（原反查路径走关注列表），普通用户无法获取 spaceUserId；且 UI 上 QueryMode 选择器删除后该模式不可达；与主理人发言功能定位重叠。`QueryMode` 删完后只剩 `.groupManager` 一个 case。

## 2. 目标

- 移除所有登录态（Cookie / Authorization）基础设施和登录 UI。
- 删除依赖登录的功能：关注动态、我的关注、我的小组、登录态校验。
- 删除「个人空间动态」功能（spaceItems 模式 / space-items CLI 命令 / spaceUserID+brokerUserID 表单字段）。
- 保留：评论、平台调仓、主理人发言、菜单栏小组件、巡检、更新、数据目录默认存储、外观偏好、窗口/通知等所有非身份相关能力。
- 保留 CLI `qieman`，删除身份相关子命令和 space-items；保留 `post-comments` / `group-posts` 等公开命令。
- 不破坏既有数据：本地已存的快照、持仓、计划、交易、巡检时间线等 JSON 文件原样保留。
- `swift test` 全绿（删除或改写相关测试断言）。

## 3. 非目标

- 不新增「免登录替代品」——关注动态/我的小组直接消失，不做平替。
- 不重写评论接口去补登录态缺失的缺口；评论 UI 文案调整后接受现实。
- 不改任何后端 API 契约；只是不再调用那些必须登录的接口。
- 不重构其他无关模块。

## 4. 架构总览

```
[删除层]                              [保留层]
─────────────                        ─────────────
QiemanLoginView              ➜  删    ContentView（去 sheet）
QiemanCookieManager          ➜  删    QiemanPlatformNativeClient（无 cookie 痕迹）
AuthState / status           ➜  删    QiemanNativeClient（瘦身保留：fetchComments/group/space）
validateAuth / *following*   ➜  删    AppModel（去身份字段，留评论/窗口/通知/巡检/更新）
fetchAuthUserInfo            ➜  删    各 Store（持仓/计划/交易/快照/巡检）
extractAccessToken/JWT       ➜  删    DashboardInsight / TodayBrief（去 cookie 提示）
CLI: auth-status/*following* ➜  删    CLI: post-comments/group-posts/space-items/updates-watch
SettingsAccountPanel         ➜  删    SettingsAppPanel（吸收外观，改名「通用」）
QueryMode.followingPosts...  ➜  删    QueryMode.groupManager / spaceItems
```

核心约束：**只做删除性改动 + 少量文案/默认值调整**，不新增逻辑。

## 5. 详细设计

### 5.1 整文件删除

| 文件 | 行数 | 内容 |
|---|---|---|
| `macos-app/Views/QiemanLoginView.swift` | 778 | 登录页、WebView、Popup 全套 |
| `macos-app/Core/QiemanCookieManager.swift` | 148 | Cookie 合并/落盘管理器 |
| `macos-app/Tests/QiemanDashboardTests/QiemanCookieManagerTests.swift` | — | Cookie 管理单测 |

### 5.2 `Core/QiemanNativeClient.swift`（瘦身）

**删除的方法/属性**：

- `NativeQiemanError.missingCookie`（case + errorDescription 分支）
- `NativeQiemanError.missingSpaceUser`（case + errorDescription 分支）— `resolveSpaceUserID` 删除后无人使用
- 存储属性 `cookieFileURL` / `rawCookie`
- `init(cookieFileURL:rawCookie:)` → 改为无参 `init()`
- `func validateAuth() async -> AuthCheckPayload`
- `func fetchFollowingPostsSnapshot(form:persist:outputDirectory:)`
- `func fetchFollowingUsersSnapshot(form:persist:outputDirectory:)`
- `func fetchMyGroupsSnapshot(form:persist:outputDirectory:)`
- `func fetchSpaceItemsSnapshot(form:persist:outputDirectory:)` — 个人空间动态功能删除
- `func resolveSpaceUserID(form:pageSize:pages:)` — 仅 spaceItems 用
- `func fetchSpaceUserInfo(spaceUserID:)` — 仅 spaceItems 用
- `func fetchAuthUserInfo(cookie:)`
- `func fetchFollowingUsers(cookie:pageSize:pages:)`
- `func fetchMyGroups(cookie:)`
- `func loadCookie() throws`
- `func extractAccessToken(from:)`
- `func decodeJWTPayload(token:)`
- `private struct NativeSpaceUserInfo` 及其 `dictionary` 扩展（约 1085 行起）— 仅 spaceItems 用

**修改的方法**：

- `fetchSnapshot` switch：删 `.followingPosts` / `.followingUsers` / `.myGroups` / `.spaceItems` 四个 case，只留 `.groupManager`。
- `fetchComments(...)`（**保留**）：删掉 `let cookie = try loadCookie()`，第 106 行 `cookie: cookie.isEmpty ? nil : cookie` 改为 `cookie: nil`。其余逻辑（params、normalizeComment、broker user 过滤、`CommentsPayload` 构造）原样保留。
- `requestJSON(path:params:cookie:)` / `requestJSONInternal`：**删除第 659-665 行 `if let cookie, !cookie.isEmpty { ... Cookie / Authorization ... }` 整段设头逻辑**。`cookie: String?` 参数保留（很多公开调用点仍传 `nil`，避免大面积改签名），但永远不写头。

**保留的数据模型字段**（历史快照 JSON 兼容，留着无害，永远空）：

- `SnapshotRecordPayload.spaceUserId`（`SnapshotPayloads.swift:86`）
- `NativeSnapshotStore` 对 `space_user_id` 的解析（`NativeSnapshotStore.swift:210`）

### 5.3 `Core/AppModel/*.swift`

#### `Auth.swift`

- 删 `validateAuth()` / `presentLoginSheet()` / `handleCookieSavedFromLoginSheet()` / `rebuildNativeStatus()` / `nativeCookieExists`。
- `refreshDataForSectionIfNeeded` 的 `.refreshLatest` 分支：删 `form.mode = cookieAvailable ? .followingPosts : .groupManager`。
- MARK 注释从 `Auth, Comments & Login` 改为 `Comments & Window`。
- **保留**：`loadCommentsForSelectedPost()`、`openDataDirectory()`、`selectPlatformAction`、`updateLaunchAtLoginEnabled`、`showMainWindow`、`quitApplication`、`refreshLaunchAtLoginStatus`、`setLaunchAtLoginEnabled`、`revealMainWindowIfNeeded`。

#### `AppModel.swift`

- 删 `@Published private(set) var authState = AuthState()`。
- 删 `@Published var status: StatusPayload?`。
- 删 `authPayload` / `isCheckingAuth` / `isPresentingLoginSheet` 三个代理计算属性。
- 删 `init()` 里 `authState.objectWillChange.sink { ... }` Combine 订阅。
- 删 `start()` 里 `rebuildNativeStatus()` 调用，以及 `if !didApplyDefaultForm, let defaultForm = status?.defaultForm { ... }`（status 已删，默认表单由 `QueryFormState` 自带默认值承担）。
- 删 `refreshLatest` 末尾的 `rebuildNativeStatus()` 调用。
- `dataDirectoryURL` 属性**保留**，固定指向默认目录（见 5.7）。

#### `ComputedProperties.swift`

- 删 `var cookieAvailable: Bool`、`var cookieFileURL: URL?`、`var isUsingCustomDataDirectory: Bool`、`var dataDirectoryDisplayName: String`（自定义目录 UI 删了，这俩 computed 不再需要）。
- 其余（portfolio/forum/platform/store URL 等）保留。

#### `SubModels.swift`

- 删 `final class AuthState`（三个属性全是登录态）。

#### `AssetAggregation.swift`

- `nativeClient` 改为 `QiemanNativeClient()`（无参 init）。

#### `DataDirectory.swift`

- 删 `changeDataDirectory(to:)` / `resetDataDirectory()` / `openDataDirectoryInFinder()`。
- `openDataDirectory()`（委托给 `dataController.openDataDirectory()`）**保留**——菜单栏、ContentView 底部、App 菜单都还在用，让用户能打开默认数据目录。

### 5.4 `Core/ApplicationDataController.swift`

- 删 `var cookieFileURL: URL?`。
- README 模板多行字符串里删 `- qieman.cookie: 登录态 Cookie（可选）` 这一行。
- 其余（supportDirectory / dataDirectoryURL / openDataDirectory / prepareEnvironment）保留。

### 5.5 `Core/Models/Query.swift`

- `enum QueryMode`：删 `followingPosts` / `followingUsers` / `myGroups` / `spaceItems` 四个 case；**只保留 `.groupManager`**（唯一 case）。
- `label` / `producesPostRecords`：相应简化（单 case switch 仍保留，未来若扩展不改签名）。
- `var mode: QueryMode = .followingPosts` → 改为 `= .groupManager`（新默认值）。
- 删 `QueryFormState.apply(defaultForm:)` 方法（仅 `rebuildNativeStatus` + `status?.defaultForm` 链路用）。
- 删 `QueryFormState.spaceUserID` / `brokerUserID` 两个字段（groupManager 模式不用，且无解析路径）。
- `fetchPayload` 里删 `"space_user_id"` 和 `"broker_user_id"` 两个键。

### 5.6 `Core/Models/SnapshotPayloads.swift` / `PlatformPayloads.swift`

- 删 `struct StatusPayload` / `struct BootstrapPayload` / `struct DefaultFormPayload`（仅登录态链路消费）。
- 删 `struct AuthCheckPayload`（仅 `validateAuth` + CLI `auth-status` 用）。
- **保留** `struct CommentsPayload` / `struct CommentPayload`（评论功能）。
- 删除前 grep 确认这三个 Payload 类型无其他引用（已知都在登录态链路）。

### 5.7 数据存储简化

`dataDirectoryURL` 这个**属性保留**（被各 Store 大量引用，删了风险极高），但：

- **删自定义目录 UI**：`SettingsAccountPanel` 整个删；`changeDataDirectory` / `resetDataDirectory` / `openDataDirectoryInFinder` / `isUsingCustomDataDirectory` / `dataDirectoryDisplayName` 方法删除。
- **`dataDirectoryURL` 始终指向默认目录**：`AppModel.swift:520` 的 `init` 里 `dataDirectoryURL = supportDirectory` 保留；`DataDirectory.swift` 仅留 `openDataDirectory()` 这一个对外方法。
- 已有的「自定义目录」状态（用户之前手动选过）不主动迁移——App 升级后 `dataDirectoryURL` 重新固定为默认目录，用户旧目录里的数据需手动搬。**这一行为变更要在 release note 明确写**。

### 5.8 外观设置搬家 + 设置面板重组

#### `Views/SettingsSectionView.swift`

- `enum SettingsFocus`：删 `case account`，保留 `watch / menuBar / version`。
- `overviewBadges`：删 Cookie 徽标。
- `overviewMetricButtons`：删「账号」metric 按钮。
- `selectedSettingsPanel`：删 `case .account: accountPanel` 分支。
- `@State var isConfirmingDataDirectoryReset` 删除。

#### `Views/SettingsAccountPanel.swift`

- **整文件删除**。

#### `Views/SettingsAppPanel.swift`（改名「通用」）

- 面板标题 `版本更新` → `通用`；subtitle `当前版本与在线更新` → `外观、版本与更新`；icon 不变。
- 在「启动时检查更新」**之前**插入「外观」设置区（浅色 / 深色 / 跟随系统三段胶囊按钮，代码从 `SettingsAccountPanel.swift:9-45` 搬过来，删除登录相关上下文）。
- 其余（更新检查 / 下载安装 / 退出应用 / 进度条）原样保留。

### 5.9 `Core/QiemanCommandLine.swift`（CLI 瘦身）

- `helpText`：删 `auth-status` / `following-posts` / `following-users` / `my-groups` / `space-items` 五条命令说明，删 `--cookie-file PATH 或环境变量 QIEMAN_COOKIE` 通用说明，删「不输出 Cookie 原文」。
- `run()`：删 `case "auth-status"` / `"following-posts"` / `"following-users"` / `"my-groups"` / `"space-items"` 五个分支。
- 删 `private func authStatus()` 方法。
- `nativeClient()` 改为 `QiemanNativeClient()`。
- 删 `rawCookie()` / `cookieFileURL()`。
- `watchForumSnapshot(mode:managerName:)`：`--forum-mode` 只支持 `public`（= `.groupManager`）。删 `following` / `auto` 分支；若用户传 `following` 或 `auto`，回退到 `public` 并在 stderr 提示（不报错，保证老脚本兼容）。
- **保留**：`group-posts` / `post-comments` / `valuation` / `group-summary` / `manager-info` / `updates-watch` / `forum-watch-state` / 其他平台命令。

### 5.10 `Core/CLI/DTOs.swift`

- 删 `struct CLIAuthStatusOutput`。
- **保留** `CLISnapshotRecordRow.spaceUserId` 字段（约 47 行）— 历史快照 JSON 兼容，删除会破坏 `CLIContractSnapshotTests` 的 record 序列化断言且让读旧快照失败；该字段今后永远为空串。
- 其余 DTO 保留。

### 5.11 `Core/DashboardInsight.swift`（去 cookie 提示）

- `enum DashboardFreshnessKind`：删 `case auth`。
- `struct DashboardFreshnessContext`：删 `let cookieAvailable: Bool`。
- `make(context:)`：删整段 `if !context.cookieAvailable { ... auth freshness item ... }`。
- `dashboardFreshnessSummary`：构造 context 时去掉 `cookieAvailable:`。

### 5.12 `Core/TodayBrief.swift`（去 login 项）

- `enum TodayBriefKind`：删 `case login`。
- `struct TodayBriefContext`：删 `let cookieAvailable: Bool` 及 init 参数和赋值。
- `makeItems`：删整段 `if !context.cookieAvailable { ... TodayBriefItem(kind: .login, ...) }`。
- `todayBriefContext`：构造 context 时去掉 `cookieAvailable:`。

### 5.13 `Core/EnhancementDashboardPresentation.swift`

> 注：`EnhancementDashboardSummary.make` 在 App 主代码无调用点，仅测试覆盖，疑似半废弃。仍一并清理以保持一致。

- `make(...)`：参数去掉 `cookieAvailable: Bool`。
- `makeRuntimeChips(...)`：参数去掉 `cookieAvailable`，删 `EnhancementRuntimeChip(id: "cookie", title: "Cookie", ...)`。

### 5.14 `Views/ContentView.swift`

- 删 `.sheet(isPresented: $model.isPresentingLoginSheet) { QiemanLoginView(...) }`（唯一登录页实例化点）。
- 删 sidebarFooter 里的 Cookie 徽标（`Circle().fill(model.cookieAvailable ? ...)` + `Text(...)`）。
- 删 `queryToolbarPanel` 里的 QueryMode 芯片选择器（整段 `ViewThatFits { HStack { ForEach(QueryMode.allCases)... } LazyVGrid { ... } }`）。
- 删 `toolbarTitleBlock` 里的 Cookie badge。
- 删 `queryModeChip(mode:)` 方法。
- 删 `toolbarField("spaceUserId", text: $model.form.spaceUserID, ...)` 文本框（约 346 行）— spaceItems 功能删除后该字段无意义。
- 删筛选面板里 `broker_user_id` 文本框（若存在）— brokerUserID 字段已从 QueryFormState 删除。用 grep 确认：`grep -n "brokerUserID\|broker_user_id\|brokerUserId" Views/ContentView.swift`。
- **保留**：「打开数据目录」按钮（菜单栏、ContentView 底部仍可用）。

### 5.15 `Views/ForumSectionView.swift`

- 评论文案 `"暂无评论，或当前登录态无法读取评论。"` → `"暂无评论。"`（评论功能本身保留）。

### 5.16 测试改动

#### 删除

- `macos-app/Tests/QiemanDashboardTests/QiemanCookieManagerTests.swift`（整文件）

#### 修改

- `DashboardInsightTests.swift`：构造 context 去掉 `cookieAvailable:`；断言从 `[.system, .managerWatch, .auth]` 改为 `[.system, .managerWatch]`；headline `"3 个异常待处理"` 改为 `"2 个异常待处理"`。
- `TodayBriefBuilderTests.swift`：
  - `testMakeItemsShowsSetupWhenPortfolioIsMissing`：去掉 `cookieAvailable:`；`items.map(\.kind)` 断言从 `[.login, .importPortfolio]` 改为 `[.importPortfolio]`；`items.first?.destination` 断言相应调整（first 变成 `.importPortfolio` → `.portfolio`）。
  - 其他用例去掉 `cookieAvailable:` 参数。
- `EnhancementDashboardPresentationTests.swift`：`makeDashboard` 助手参数去掉 `cookieAvailable`；`EnhancementDashboardSummary.make(...)` 调用去掉该参数；若有断言 cookie chip 存在的用例相应删除。
- `UIExperienceRegressionTests.swift`：
  - 删 `testDestructiveSettingsAndLoginActionsRequireConfirmation`（断言 `QiemanLoginView` 存在 + `"清除登录态？"`）。
  - `testQuitApplicationIsReachable...` 保留（`quitApplication()` 仍在）。
- `CLIContractSnapshotTests.swift`：
  - `testSnakeCaseConversionPreservesExistingKeys`：把演示 DTO 从 `CLIAuthStatusOutput` 换成另一个保留下来的 DTO（如 `CLISnapshotGroupRow`），保住 snake_case 策略锁定。
  - `testWatchStateRoundTripsPreservingSnakeCaseKeys`：把 `forumSource: "following-posts"` 改为 `"public-group"`，断言同步改。

#### 不动

- `PerformanceTelemetryTests.swift`：`isSensitive` 的 cookie/token/authorization 脱敏逻辑保留（通用防护），测试保留。
- 其他 80+ 测试文件无 cookie/login 引用。

## 6. 数据流变化

**删除前**（论坛板块多模式）：

```
refreshLatest ─┬─ snapshotTask: nativeClient.fetchSnapshot(mode: .followingPosts/.groupManager/.followingUsers/.myGroups/.spaceItems)
               └─ platformTask: platformClient.fetchPlatformPayload(...)
```

**删除后**（唯一模式）：

```
refreshLatest ─┬─ snapshotTask: nativeClient.fetchSnapshot(mode: .groupManager)
               └─ platformTask: platformClient.fetchPlatformPayload(...)
```

- `QueryMode` 只剩 `.groupManager` 一个 case，`fetchSnapshot` 内部 switch 也只留一个 case。
- 默认 mode 固定 `.groupManager`（主理人小组发言）。
- `refreshDataForSectionIfNeeded` 不再动态切 mode。
- 「两条任务并发、互不影响」的设计保留。

## 7. CLI 兼容性

- 删除的命令：`auth-status` / `following-posts` / `following-users` / `my-groups` / `space-items`。老脚本调用会拿到 `unknown command` 错误，需在 release note 提示。
- `updates-watch --forum-mode`：`following` / `auto` 取值静默回退为 `public`，stderr 给一行提示。老脚本能继续跑。
- 保留命令的行为不变。

## 8. 验证策略

1. **编译**：`APP_VERSION=3.4.0 bash scripts/build_macos_app.sh` 通过（App + CLI）。
2. **CLI 构建**：`bash scripts/build_qieman_cli.sh` 通过。
3. **测试**：`swift test`（在 `macos-app/`）全绿。
4. **残留符号 grep（应 0 命中，注释除外）**：`cookieAvailable` / `cookieFileURL` / `nativeCookieExists` / `cookieExists` / `validateAuth` / `authPayload` / `isCheckingAuth` / `isPresentingLoginSheet` / `presentLoginSheet` / `handleCookieSavedFromLoginSheet` / `QiemanLoginView` / `QiemanCookieManager` / `fetchFollowingPosts` / `fetchFollowingUsers` / `fetchMyGroups` / `fetchAuthUserInfo` / `fetchSpaceItemsSnapshot` / `fetchSpaceUserInfo` / `resolveSpaceUserID` / `NativeSpaceUserInfo` / `followingPosts` / `followingUsers` / `myGroups` / `spaceItems` / `loadCookie` / `rawCookie` / `missingCookie` / `missingSpaceUser` / `extractAccessToken` / `decodeJWTPayload` / `StatusPayload` / `BootstrapPayload` / `DefaultFormPayload` / `AuthCheckPayload` / `CLIAuthStatusOutput` / `AuthState` / `auth-status` / `following-posts` / `following-users` / `my-groups` / `space-items`。
   - **例外（允许残留）**：`SnapshotRecordPayload.spaceUserId` / `CLISnapshotRecordRow.spaceUserId` / `NativeSnapshotStore` 对 `space_user_id` 的解析——这些是历史快照 JSON 兼容字段，刻意保留。
5. **手工 smoke**：
   - 启动 App，无登录入口，无 Cookie 徽标。
   - 论坛板块默认显示主理人发言；评论区按钮可见，点击后按现状提示「暂无评论」。
   - 平台调仓刷新正常。
   - 设置面板只剩「巡检 / 菜单栏 / 通用」三项，「通用」里能看到外观 + 更新。
   - 数据目录按钮（菜单栏、ContentView 底部）仍能打开默认目录。
   - `scripts/qieman group-posts ...` / `space-items ...` / `post-comments ...` 正常输出。
   - `scripts/qieman auth-status` 报 unknown command。

## 9. 风险与回滚

**风险**：

- 删除面广（约 20 个文件），漏改导致编译失败的概率高。缓解：分步删除 + 每步编译验证 + 最后 grep 关键符号 0 命中。
- `requestJSON` 保留 `cookie:` 参数但永不写头——略带死代码味道。缓解：注释一句「保留参数兼容调用点，不再写头」。
- 老脚本调用已删的 CLI 命令会失败。缓解：release note 明确列出删除命令。
- 用户之前自定义过数据目录，升级后数据「消失」（其实在旧目录里）。缓解：release note 提示「数据目录恢复默认，自定义目录功能移除」。

**回滚**：纯删除性提交，单 PR/单 commit，回滚只需 `git revert`。

## 10. 不在本次范围

- 评论接口的替代方案（要不要服务端开匿名、要不要换接口）。
- 关注/我的小组的免登录平替。
- 数据目录的可配置化重做（如未来需要）。
- 任何与登录态无关的重构。

## 11. 实施步骤（高层）

1. 整文件删除（3 个）。
2. `QiemanNativeClient.swift` 瘦身 + `fetchComments`/`requestJSON`/`resolveSpaceUserID` 改造。
3. `AppModel.swift` + `AppModel/*.swift` + `SubModels.swift` 去身份字段。
4. `Models/Query.swift` + `Models/*Payloads.swift` 删 case / 删 struct。
5. `ApplicationDataController.swift` 去 cookie。
6. `QiemanCommandLine.swift` + `CLI/DTOs.swift` 删命令。
7. `DashboardInsight.swift` + `TodayBrief.swift` + `EnhancementDashboardPresentation.swift` 去提示。
8. `Views/ContentView.swift` + `Views/ForumSectionView.swift` 去 UI。
9. `Views/SettingsSectionView.swift` + `Views/SettingsAppPanel.swift` 重组设置；删 `SettingsAccountPanel.swift`。
10. 测试改动（删 1 个 + 改 5 个）。
11. 全量编译 + `swift test` + grep 残留符号。
12. （可选）在 PROJECT_MAP.md / AGENTS.md 同步描述。

每步独立编译通过，便于定位问题。

---

## 12. 筛选重构：主理人多选 + 联想搜索（追加范围）

### 12.1 背景与数据事实

经 API 实测确认：
- 且慢社区**总共只有 6 个小组**（`/community/group/awesome-list` 的 `totalCount=6`）。
- 每个小组有**唯一一个主理人**（leader），小组↔主理人≈1:1。
- `awesome-list` 返回的每个 group **不含主理人 userName**，只有 `broker`(brokerId)；要拿主理人名字须对每个 group 调 `/community/group/manager-info`。
- `manager-info` 返回完整主理人信息：`userName` / `brokerUserId` / `userLabel` / `userAvatarUrl`。
- 一个主理人可能领导多个小组（待实测确认，但 6 个小组的规模下不影响）。

**结论**：选主理人 ≈ 选小组。产品字段（prodCode）作为独立筛选维度已无意义（每个小组本身对应一个产品），**去掉产品字段**。

### 12.2 目标

- 筛选面板只保留**主理人多选 + 联想搜索**一个控件。
- 删除其他所有筛选字段：产品、关键词、日期范围、页数/每页、groupId/groupUrl/brokerUserId/spaceUserId/自动刷新。
- 底层抓取改为**多小组并发抓取 + 合并去重 + 按时间排序**。
- 主理人联想数据源：预拉 awesome-list（1 次）+ 每个小组 manager-info（6 次）= 7 个请求，内存建索引，启动时或首次展开筛选面板时触发，缓存到 AppModel。

### 12.3 新增数据模型

**`Core/Models/ManagerSummary.swift`（新文件）**：

```swift
import Foundation

struct ManagerSummary: Identifiable, Hashable {
    let brokerUserId: String   // 唯一标识，用作 id
    let userName: String       // 显示名，如 "ETF拯救世界"
    let userLabel: String      // 副标题，如 "长赢指数投资计划主理人"
    let userAvatarURL: String
    let groupId: Int           // 他领导的小组 ID
    let groupName: String      // 小组名，如 "长赢同路人"

    var id: String { brokerUserId }
}
```

### 12.4 NativeClient 改造

**新增方法** `fetchManagerIndex() async throws -> [ManagerSummary]`：

- 拉 awesome-list 全部页（totalCount 已知，一次 size=50 够了）。
- 对每个 group 调 manager-info，提取 leader。
- 组装 `[ManagerSummary]`，按 userName 排序。
- 这个方法独立于 `fetchGroupManagerSnapshot`，不依赖 QueryFormState。

**改造** `fetchGroupManagerSnapshot` → `fetchMultiGroupSnapshot(groupIds: persist: outputDirectory:)`：

- 入参从单个 `QueryFormState` 改为 `[Int]`（多个 groupId）。
- 对每个 groupId 并发调用现有的「抓单个小组帖子」逻辑（抽成 `fetchSingleGroupPosts(groupId:)`）。
- 合并所有小组的帖子，按 `created_at` 降序排序，去重（按 postId）。
- `postMatchesFilters` 调用简化：去掉 keyword/since/until/userName 参数（字段都删了），这个方法可以直接删除，或保留为 always-true。

**删除** `resolveGroupID`：不再需要从 prodCode/managerName 反查，groupId 直接从 ManagerSummary 来。

### 12.5 QueryFormState 重构

```swift
struct QueryFormState {
    var selectedManagerIds: Set<String> = []   // 选中的主理人 brokerUserId
    var pages: String = "5"
    var pageSize: String = "10"
}
```

- 删除：`mode`（只剩一种，不需要枚举）、`prodCode`、`managerName`、`groupURL`、`groupID`、`userName`、`keyword`、`since`、`until`、`autoRefresh`。
- `QueryMode` 枚举：既然只剩一种模式，**整个枚举删除**。`fetchSnapshot` 不再 switch mode，直接调 `fetchMultiGroupSnapshot`。
- 保留 `pages` / `pageSize` 作为「每个小组抓几页」的参数（用默认值，UI 上可不暴露，或放高级区）。

### 12.6 AppModel 改造

新增：
- `@Published private(set) var managerIndex: [ManagerSummary] = []`
- `@Published private(set) var isLoadingManagerIndex: Bool = false`
- `func loadManagerIndex() async`：调 `nativeClient.fetchManagerIndex()`，结果存 `managerIndex`。启动时（`start()`）触发一次，失败静默（UI 显示重试）。

改造 `refreshLatest`：
- 从 `form.selectedManagerIds` + `managerIndex` 解析出 `[Int]` groupIds。
- 调 `nativeClient.fetchMultiGroupSnapshot(groupIds:...)`。

### 12.7 UI 改造（ContentView 筛选面板）

筛选面板内容区从「一堆 toolbarField」替换为：

**主理人多选联想控件**（新 SwiftUI 组件 `ManagerPicker`，放 `Views/SharedComponents.swift` 或新文件）：
- 一个搜索框 + 下拉列表。
- 输入时从 `model.managerIndex` 按 userName 模糊匹配，显示候选。
- 候选项带勾选状态（选中/未选中），点击切换。
- 已选主理人显示为芯片（chip）标签，可点 × 移除。
- 数据来自 `model.managerIndex`；若 `managerIndex` 为空，显示「正在加载主理人列表…」并触发 `loadManagerIndex`。

筛选面板只剩这一个控件 + 一个「刷新」按钮（已有）。

### 12.8 fetchSnapshot 签名变化

原：
```swift
func fetchSnapshot(form: QueryFormState, persist: Bool, outputDirectory: URL?) async throws -> SnapshotPayload
```

新（不再需要 form，直接传 groupIds）：
```swift
func fetchMultiGroupSnapshot(groupIds: [Int], pages: Int, pageSize: Int, persist: Bool, outputDirectory: URL?) async throws -> SnapshotPayload
```

调用方（AppModel.refreshLatest、CLI）同步改。

### 12.9 CLI 影响

- `group-posts` 命令：原参数 `--prod-code` / `--manager-name` 改为 `--group-id`（可重复，多值）或 `--manager-id`（可重复）。底层调 `fetchMultiGroupSnapshot`。
- 新增 `managers` 命令：输出所有主理人列表（从 fetchManagerIndex），供脚本查询 groupId/brokerUserId。
- `--forum-mode` 参数彻底删除（只剩一种模式）。

### 12.10 测试

- 新增 `ManagerIndexTests`：mock awesome-list + manager-info 响应，验证 `fetchManagerIndex` 解析正确。
- 新增 `MultiGroupSnapshotTests`：mock 多小组帖子，验证合并、去重、按时间排序。
- 改 `CLIContractSnapshotTests`：`group-posts` 命令的 DTO 快照（参数变了）。
- 删除依赖旧 QueryFormState 字段的测试（若有）。

### 12.11 实施顺序（追加 Task 11-14）

在删除登录态（Task 1-10）完成后，追加：
- **Task 11**：新增 `ManagerSummary` 模型 + `fetchManagerIndex` 方法。
- **Task 12**：改造 `fetchGroupManagerSnapshot` → `fetchMultiGroupSnapshot`，删 `resolveGroupID` / `postMatchesFilters` / `QueryMode`。
- **Task 13**：AppModel 加 `managerIndex` + `loadManagerIndex`，改 `refreshLatest`。
- **Task 14**：ContentView 筛选面板替换为 `ManagerPicker` 组件。
- **Task 15**：CLI `group-posts` 参数改造 + 新增 `managers` 命令。
- **Task 16**：测试（新增 2 个 + 改契约快照）。
