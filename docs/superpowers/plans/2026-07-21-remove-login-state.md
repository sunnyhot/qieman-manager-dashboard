# 删除登录态功能 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 从且慢主理人看板彻底删除登录态（Cookie）体系，连带删除必须登录的关注动态/我的关注/我的小组/登录态校验功能，以及依赖登录态解析路径的「个人空间动态」功能；保留评论、平台调仓、主理人发言等公开能力。

**Architecture:** 纯删除性改动 + 少量文案/默认值调整，不新增业务逻辑。按依赖顺序分层删除：错误类型 → Models → NativeClient → AppModel → ApplicationDataController → CLI → Insight Core → Views → Settings → 测试 → 全量验证。每步独立可编译。

**Tech Stack:** Swift 5（macOS 14+ SwiftUI + AppKit + Foundation），SPM 测试，swiftc 打包 CLI。

**Spec:** `docs/superpowers/specs/2026-07-21-remove-login-state-design.md`

**关键行为变更（实施时注意）**：
1. 「个人空间动态」（spaceItems）功能整体删除：`QueryMode` 只剩 `.groupManager` 一个 case；`fetchSpaceItemsSnapshot` / `fetchSpaceUserInfo` / `resolveSpaceUserID` / `NativeSpaceUserInfo` 全删；`QueryFormState.spaceUserID` / `brokerUserID` 字段删；CLI `space-items` 命令删。历史快照 JSON 兼容字段（`SnapshotRecordPayload.spaceUserId` / `CLISnapshotRecordRow.spaceUserId` / `NativeSnapshotStore` 的 `space_user_id` 解析）保留，今后永远为空。
2. `dataDirectoryURL` 属性保留，固定指向默认目录；自定义目录 UI 和方法删除。
3. CLI `--forum-mode following|auto` 静默回退为 `public`，stderr 给提示。
4. `requestJSON` 的 `cookie: String?` 参数保留（避免大面积改签名），但永远不写 Cookie/Authorization 头。

---

## 文件结构总览

### 整文件删除（3）
- `macos-app/Views/QiemanLoginView.swift`（778 行）
- `macos-app/Core/QiemanCookieManager.swift`（148 行）
- `macos-app/Tests/QiemanDashboardTests/QiemanCookieManagerTests.swift`

### 修改（约 19 个）
- `macos-app/Core/QiemanNativeClient.swift`
- `macos-app/Core/AppModel.swift`
- `macos-app/Core/AppModel/Auth.swift`
- `macos-app/Core/AppModel/AssetAggregation.swift`
- `macos-app/Core/AppModel/ComputedProperties.swift`
- `macos-app/Core/AppModel/DataDirectory.swift`
- `macos-app/Core/AppModel/SubModels.swift`
- `macos-app/Core/ApplicationDataController.swift`
- `macos-app/Core/Models/Query.swift`
- `macos-app/Core/Models/SnapshotPayloads.swift`
- `macos-app/Core/Models/PlatformPayloads.swift`
- `macos-app/Core/QiemanCommandLine.swift`
- `macos-app/Core/CLI/DTOs.swift`
- `macos-app/Core/DashboardInsight.swift`
- `macos-app/Core/TodayBrief.swift`
- `macos-app/Core/EnhancementDashboardPresentation.swift`
- `macos-app/Views/ContentView.swift`
- `macos-app/Views/ForumSectionView.swift`
- `macos-app/Views/SettingsSectionView.swift`
- `macos-app/Views/SettingsAppPanel.swift`
- `macos-app/Views/SettingsAccountPanel.swift`（整文件删）

### 测试修改（5）
- `macos-app/Tests/QiemanDashboardTests/DashboardInsightTests.swift`
- `macos-app/Tests/QiemanDashboardTests/TodayBriefBuilderTests.swift`
- `macos-app/Tests/QiemanDashboardTests/EnhancementDashboardPresentationTests.swift`
- `macos-app/Tests/QiemanDashboardTests/UIExperienceRegressionTests.swift`
- `macos-app/Tests/QiemanDashboardTests/CLIContractSnapshotTests.swift`

---

## Task 1: Models 层删 case 和 struct（最底层，先改）

**Files:**
- Modify: `macos-app/Core/Models/Query.swift`（全文重写）
- Modify: `macos-app/Core/Models/SnapshotPayloads.swift:3-20`（删 Bootstrap/Status/DefaultForm）
- Modify: `macos-app/Core/Models/PlatformPayloads.swift`（删 AuthCheckPayload）

这一层是底层依赖，先改完后续 NativeClient 改造时才能去掉对它们的引用。

- [ ] **Step 1.1: 重写 `Query.swift`，删 4 个 mode case + apply 方法 + spaceUserID/brokerUserID 字段**

把整个 `macos-app/Core/Models/Query.swift` 替换为：

```swift
import Foundation

enum QueryMode: String, CaseIterable, Identifiable {
    case groupManager = "group-manager"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .groupManager:
            return "公开主理人流"
        }
    }
}

extension QueryMode {
    var producesPostRecords: Bool {
        switch self {
        case .groupManager:
            return true
        }
    }
}

struct QueryFormState {
    var mode: QueryMode = .groupManager
    var prodCode: String = "LONG_WIN"
    var managerName: String = ""
    var groupURL: String = ""
    var groupID: String = ""
    var userName: String = "ETF拯救世界"
    var keyword: String = ""
    var since: String = ""
    var until: String = ""
    var pages: String = "5"
    var pageSize: String = "10"
    var autoRefresh: String = ""

    func fetchPayload(persist: Bool) -> [String: Any] {
        var payload: [String: Any] = [
            "mode": mode.rawValue,
            "prod_code": prodCode,
            "manager_name": managerName,
            "group_url": groupURL,
            "group_id": groupID,
            "user_name": userName,
            "keyword": keyword,
            "since": since,
            "until": until,
            "pages": pages,
            "page_size": pageSize,
            "auto_refresh": autoRefresh,
            "persist": persist,
        ]
        payload = payload.filter { key, value in
            if key == "persist" {
                return true
            }
            if let text = value as? String {
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return true
        }
        return payload
    }
}
```

注：`brokerUserID` / `spaceUserID` 字段删除。groupManager 模式不需要它们，且删登录态后无解析路径。

- [ ] **Step 1.2: 删 `SnapshotPayloads.swift` 顶部三个 payload struct**

删除 `macos-app/Core/Models/SnapshotPayloads.swift:3-20`，即删掉：

```swift
struct BootstrapPayload: Decodable {
    let status: StatusPayload
}

struct StatusPayload: Decodable {
    let cookieExists: Bool
    let cookieFile: String
    let outputDir: String
    let defaultForm: DefaultFormPayload
}

struct DefaultFormPayload: Decodable {
    let mode: String
    let prodCode: String
    let userName: String
    let pages: String
    let pageSize: String
}
```

保留 `FetchResponsePayload` 及之后所有内容。

- [ ] **Step 1.3: 删 `PlatformPayloads.swift` 的 `AuthCheckPayload`**

打开 `macos-app/Core/Models/PlatformPayloads.swift`，定位到 `struct AuthCheckPayload`（约 125-131 行），整段删除。保留 `CommentsPayload` / `CommentPayload`。

- [ ] **Step 1.4: 编译验证（预期会失败，因为 NativeClient 还在引用）**

Run: `cd macos-app && swift build 2>&1 | head -40`

Expected: FAIL，错误集中在 `QiemanNativeClient.swift`（引用了刚删的 `AuthCheckPayload`、`DefaultFormPayload`、`QueryMode.followingPosts` 等）。这是预期的——Task 2 会修复。记录错误条数，确保**只有 QiemanNativeClient 相关**报错，没有其他文件报错。

- [ ] **Step 1.5: Commit**

```bash
git add macos-app/Core/Models/Query.swift macos-app/Core/Models/SnapshotPayloads.swift macos-app/Core/Models/PlatformPayloads.swift
git commit -m "refactor: 删除登录态相关 QueryMode case 和 Payload struct"
```

---

## Task 2: NativeClient 瘦身（删登录态方法 + 改造 fetchComments/requestJSON/resolveSpaceUserID）

**Files:**
- Modify: `macos-app/Core/QiemanNativeClient.swift`

- [ ] **Step 2.1: 删 `NativeQiemanError.missingCookie` 和 `missingSpaceUser`**

在 `QiemanNativeClient.swift:4-11`，从 enum 删掉 `case missingCookie`（第 6 行）和 `case missingSpaceUser`（第 8 行）；在 13-30 行的 `errorDescription` switch 里删掉 `case .missingCookie:`（17-18 行）和 `case .missingSpaceUser:`（21-22 行）两个分支。

改完的 enum：

```swift
enum NativeQiemanError: LocalizedError {
    case unsupportedMode(String)
    case missingGroup
    case noResults(String)
    case invalidResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedMode(let mode):
            return "原生抓取暂不支持当前模式：\(mode)"
        case .missingGroup:
            return "无法解析主理人所在小组"
        case .noResults(let message):
            return message
        case .invalidResponse:
            return "且慢接口返回了无法识别的数据。"
        case .api(let message):
            return message
        }
    }
}
```

- [ ] **Step 2.2: 删 cookie 存储属性 + 改 init 为无参**

在 `QiemanNativeClient.swift:39-48`，删 `private let cookieFileURL: URL?` 和 `private let rawCookie: String?`，init 改为无参：

```swift
final class QiemanNativeClient {
    private let baseURL = URL(string: "https://qieman.com")!
    private let apiBase = "/pmdj/v2"
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    private let snapshotStore = NativeSnapshotStore()
    private let anonymousID: String

    init() {
        let seed = "\(Date().timeIntervalSince1970)-\(UUID().uuidString)"
        self.anonymousID = "anon-\(Self.sha256Hex(seed).prefix(16))"
    }
```

- [ ] **Step 2.3: 删 `validateAuth` 方法（50-72 行整段）**

直接删除整个 `func validateAuth() async -> AuthCheckPayload { ... }`。

- [ ] **Step 2.4: 改 `fetchSnapshot` switch（75-87 行）只留 groupManager**

```swift
func fetchSnapshot(form: QueryFormState, persist: Bool, outputDirectory: URL?) async throws -> SnapshotPayload {
    switch form.mode {
    case .groupManager:
        return try await fetchGroupManagerSnapshot(form: form, persist: persist, outputDirectory: outputDirectory)
    }
}
```

- [ ] **Step 2.5: 改造 `fetchComments`（89-125 行）**

把第 96 行 `let cookie = try loadCookie()` 删除；把第 106 行 `cookie: cookie.isEmpty ? nil : cookie` 改为 `cookie: nil`。

改完的关键部分：

```swift
func fetchComments(
    postID: Int,
    sortType: String,
    pageNum: Int,
    pageSize: Int,
    managerBrokerUserID: String
) async throws -> CommentsPayload {
    var params: [String: String] = [
        "pageNum": String(max(1, pageNum)),
        "pageSize": String(max(1, pageSize)),
        "postId": String(postID),
    ]
    if sortType.lowercased() == "hot" {
        params["sortType"] = "HOT"
    }

    let payload = try await requestJSON(path: "/community/comment/list", params: params, cookie: nil)
    // ... 后面 normalizeComment / filter / CommentsPayload 构造原样保留
```

- [ ] **Step 2.6: 删四个 snapshot 方法**

删除整段：
- `fetchFollowingPostsSnapshot`（199-277 行）
- `fetchFollowingUsersSnapshot`（279-314 行）
- `fetchMyGroupsSnapshot`（316-351 行）
- `fetchSpaceItemsSnapshot`（353-412 行）— 个人空间动态功能删除

- [ ] **Step 2.7: 删 3 个 private helper 方法**

- `fetchAuthUserInfo(cookie:)`（451-464 行整段删）
- `fetchFollowingUsers(cookie:pageSize:pages:)`（466-501 行整段删）
- `fetchMyGroups(cookie:)`（503-524 行整段删）

- [ ] **Step 2.8: 删除 space 相关方法 + 类型**

整段删除（个人空间动态功能删除）：
- `fetchSpaceUserInfo(spaceUserID:)`（526-546 行）
- `resolveSpaceUserID(form:pageSize:pages:)`（548-579 行）
- `private struct NativeSpaceUserInfo` 及其 `dictionary` 扩展（约 1085 行起，用 grep 精确定位：`grep -n "struct NativeSpaceUserInfo" macos-app/Core/QiemanNativeClient.swift`）

注意：删除前确认这些方法/类型没有其他调用方（已在 spec 调研中确认仅 spaceItems 链路使用）。

- [ ] **Step 2.9: 删 `loadCookie` 方法（684-695 行整段）**

- [ ] **Step 2.10: 删 `extractAccessToken` 和 `decodeJWTPayload`**

定位（约 991-1018 行附近，用 grep 确认精确位置）：
```bash
grep -n "func extractAccessToken\|func decodeJWTPayload" macos-app/Core/QiemanNativeClient.swift
```
删除这两个 `private func` 的整个实现。

- [ ] **Step 2.11: 改造 `requestJSONInternal`（637-682 行）删 Cookie/Authorization 设头**

删除 659-665 行的整段：
```swift
if let cookie, !cookie.isEmpty {
    request.setValue(cookie, forHTTPHeaderField: "Cookie")
    let accessToken = extractAccessToken(from: cookie)
    if !accessToken.isEmpty {
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    }
}
```

`cookie: String?` 参数**保留**（注释说明「保留参数兼容调用点，不再写头」）。改完后 659 行之前和 666 行之后直接相连。

- [ ] **Step 2.12: 编译验证 NativeClient 单文件**

Run: `cd macos-app && swift build 2>&1 | grep -v "Core/AppModel\|Views/\|Core/QiemanCommandLine\|Core/DashboardInsight\|Core/TodayBrief\|Core/EnhancementDashboard\|Tests/" | head -30`

Expected: `QiemanNativeClient.swift` 本身无错误。其他文件（AppModel、Views、CLI 等）的报错留待后续 Task 修复。

- [ ] **Step 2.13: Commit**

```bash
git add macos-app/Core/QiemanNativeClient.swift
git commit -m "refactor: NativeClient 删除登录态方法，fetchComments 改匿名调用"
```

---

## Task 3: AppModel 层去身份字段

**Files:**
- Modify: `macos-app/Core/AppModel.swift`
- Modify: `macos-app/Core/AppModel/Auth.swift`
- Modify: `macos-app/Core/AppModel/AssetAggregation.swift`
- Modify: `macos-app/Core/AppModel/ComputedProperties.swift`
- Modify: `macos-app/Core/AppModel/DataDirectory.swift`
- Modify: `macos-app/Core/AppModel/SubModels.swift`

- [ ] **Step 3.1: 删 `SubModels.swift` 的 `AuthState` 类**

打开 `macos-app/Core/AppModel/SubModels.swift`，定位 `final class AuthState`（约 84-90 行），整段删除。

- [ ] **Step 3.2: 改 `AppModel.swift`**

打开 `macos-app/Core/AppModel.swift`，做以下删除：

a. 删 `@Published private(set) var authState = AuthState()`（约 68 行）
b. 删 `@Published var status: StatusPayload?`（约 75 行）
c. 删代理属性 `authPayload` / `isCheckingAuth` / `isPresentingLoginSheet`（约 217-231 行，用 grep 确认）
d. 在 `init()` 里删 `authState.objectWillChange.sink { ... }` Combine 订阅（约 465-467 行）
e. 在 `start()` 里删 `rebuildNativeStatus()` 调用（约 527 行），以及 `if !didApplyDefaultForm, let defaultForm = status?.defaultForm { form.apply(defaultForm:); didApplyDefaultForm = true }`（约 528-531 行）
f. 在 `refreshLatest` 末尾删 `rebuildNativeStatus()` 调用（约 617 行）

每个位置用 grep 精确定位：
```bash
grep -n "authState\|var status:\|authPayload\|isCheckingAuth\|isPresentingLoginSheet\|rebuildNativeStatus\|didApplyDefaultForm\|status?.defaultForm" macos-app/Core/AppModel.swift
```

- [ ] **Step 3.3: 改 `Auth.swift`**

打开 `macos-app/Core/AppModel/Auth.swift`：

a. MARK 注释 `// MARK: - Auth, Comments & Login` 改为 `// MARK: - Comments & Window`
b. 删 `func validateAuth() async`（约 8-16 行）
c. 删 `func presentLoginSheet()`（约 58-69 行）
d. 删 `func handleCookieSavedFromLoginSheet()`（约 71-75 行）
e. 删 `func rebuildNativeStatus()`（约 165-180 行）
f. 删 `var nativeCookieExists: Bool`（约 182-185 行）
g. 在 `refreshDataForSectionIfNeeded` 的 `.refreshLatest` 分支，删 `if (section == .overview || section == .forum), !form.mode.producesPostRecords { form.mode = cookieAvailable ? .followingPosts : .groupManager }`（约 122-124 行）

**保留**：`loadCommentsForSelectedPost()`、`openDataDirectory()`、`selectPlatformAction`、`updateLaunchAtLoginEnabled`、`showMainWindow`、`quitApplication`、`refreshLaunchAtLoginStatus`、`setLaunchAtLoginEnabled`、`revealMainWindowIfNeeded`。

- [ ] **Step 3.4: 改 `AssetAggregation.swift` 的 nativeClient 构造**

定位 `macos-app/Core/AppModel/AssetAggregation.swift:6-12`，把 `_nativeClient = QiemanNativeClient(cookieFileURL: dataController.cookieFileURL)` 改为 `_nativeClient = QiemanNativeClient()`。

- [ ] **Step 3.5: 改 `ComputedProperties.swift`**

打开 `macos-app/Core/AppModel/ComputedProperties.swift`，删除：
- `var cookieAvailable: Bool`（80-82 行）
- `var cookieFileURL: URL?`（95-97 行）
- `var isUsingCustomDataDirectory: Bool`（209 行起）
- `var dataDirectoryDisplayName: String`（213 行起）

其余 computed property（portfolio/forum/platform/store URL 等）保留。

- [ ] **Step 3.6: 改 `DataDirectory.swift` 删自定义目录方法**

打开 `macos-app/Core/AppModel/DataDirectory.swift`，删除：
- `func changeDataDirectory(to newURL: URL)`（7 行起，整个方法）
- `func resetDataDirectory()`（37 行起，整个方法）
- `func openDataDirectoryInFinder()`（69 行起，整个方法）

**保留**：`openDataDirectory()`（如果存在；若它实际在 `Auth.swift` 里则不动）。

用 grep 确认：
```bash
cat macos-app/Core/AppModel/DataDirectory.swift
```

- [ ] **Step 3.7: 编译验证 AppModel 层**

Run: `cd macos-app && swift build 2>&1 | grep -v "Views/\|Core/QiemanCommandLine\|Core/CLI/\|Tests/" | head -40`

Expected: Core/AppModel 无错误。Views / CLI / Tests 还有报错（后续 Task 修）。

- [ ] **Step 3.8: Commit**

```bash
git add macos-app/Core/AppModel.swift macos-app/Core/AppModel/
git commit -m "refactor: AppModel 删除登录态字段和自定义目录逻辑"
```

---

## Task 4: ApplicationDataController 去 cookie

**Files:**
- Modify: `macos-app/Core/ApplicationDataController.swift`

- [ ] **Step 4.1: 删 `cookieFileURL` 属性**

定位 `macos-app/Core/ApplicationDataController.swift:28-30`，删 `var cookieFileURL: URL? { ... }` 整段。

- [ ] **Step 4.2: 删 README 模板里的 cookie 说明行**

定位约 89 行，在 `writeReadmeIfNeeded` 的多行字符串里删 `- qieman.cookie: 登录态 Cookie（可选）` 这一行。

用 grep 确认精确位置：
```bash
grep -n "qieman.cookie" macos-app/Core/ApplicationDataController.swift
```

- [ ] **Step 4.3: Commit**

```bash
git add macos-app/Core/ApplicationDataController.swift
git commit -m "refactor: ApplicationDataController 删除 cookie 路径"
```

---

## Task 5: CLI 瘦身（QiemanCommandLine + DTOs）

**Files:**
- Modify: `macos-app/Core/QiemanCommandLine.swift`
- Modify: `macos-app/Core/CLI/DTOs.swift`

- [ ] **Step 5.1: 删 `CLIAuthStatusOutput` DTO**

打开 `macos-app/Core/CLI/DTOs.swift`，删除 `struct CLIAuthStatusOutput`（约 25-32 行）。其余 DTO 保留。

- [ ] **Step 5.2: 改 `QiemanCommandLine.swift` helpText**

定位约 65-90 行的 `helpText`，删除以下命令说明行：
- `auth-status` 说明（约 70 行）
- `following-posts` 说明（约 71 行）
- `following-users` 说明（约 72 行）
- `my-groups` 说明（约 73 行）
- `space-items` 说明（约 76 行）

并删除：
- 通用说明「通用登录参数：--cookie-file PATH 或环境变量 QIEMAN_COOKIE」（约 88 行）
- 「不输出 Cookie 原文」（约 89 行）

- [ ] **Step 5.3: 删 run() 里 5 个 case 分支**

定位约 110-122 行，删：
```swift
case "auth-status": return try await authStatus()
case "following-posts": return try await snapshot(mode: .followingPosts)
case "following-users": return try await snapshot(mode: .followingUsers)
case "my-groups": return try await snapshot(mode: .myGroups)
case "space-items": return try await snapshot(mode: .spaceItems, ...)  // 精确签名用 grep 确认
```

用 grep 确认 space-items case 的精确写法：
```bash
grep -n 'case "space-items"' macos-app/Core/QiemanCommandLine.swift
```

- [ ] **Step 5.4: 删 `authStatus()` 方法**

定位约 151-162 行的 `private func authStatus()`，整段删除。

- [ ] **Step 5.5: 改 `nativeClient()` 构造**

定位约 494-496 行，把 `QiemanNativeClient(cookieFileURL: cookieFileURL(), rawCookie: rawCookie())` 改为 `QiemanNativeClient()`。

- [ ] **Step 5.6: 删 `rawCookie()` 和 `cookieFileURL()` 私有方法**

定位约 498-513 行，删 `private func rawCookie()` 和 `private func cookieFileURL()` 整段。

- [ ] **Step 5.7: 改造 `watchForumSnapshot` 只支持 public 模式**

定位约 538-564 行的 `watchForumSnapshot(mode:managerName:)`，把 `following` / `auto` 分支删掉。改造后：

```swift
private func watchForumSnapshot(mode: String, managerName: String) async throws -> Data {
    // following/auto 已废弃（登录态移除），统一回退到 public
    let effectiveMode = mode.lowercased()
    if effectiveMode != "public" && !effectiveMode.isEmpty {
        FileHandle.standardError.write("forum-mode '\(mode)' 已废弃，回退到 public。\n".data(using: .utf8)!)
    }
    return try await snapshot(mode: .groupManager, managerName: managerName)
}
```

注意：先读原方法完整内容确认 snapshot 调用签名（是否传 managerName），再按实际签名改写。用 grep 确认：
```bash
grep -n "func watchForumSnapshot\|func snapshot(" macos-app/Core/QiemanCommandLine.swift
```

- [ ] **Step 5.8: 编译验证 CLI**

Run: `cd macos-app && swift build 2>&1 | grep "QiemanCommandLine\|CLI/DTOs" | head -20`

Expected: 无错误。

- [ ] **Step 5.9: Commit**

```bash
git add macos-app/Core/QiemanCommandLine.swift macos-app/Core/CLI/DTOs.swift
git commit -m "refactor: CLI 删除登录态命令，forum-mode 只支持 public"
```

---

## Task 6: Insight Core 去 cookie 提示

**Files:**
- Modify: `macos-app/Core/DashboardInsight.swift`
- Modify: `macos-app/Core/TodayBrief.swift`
- Modify: `macos-app/Core/EnhancementDashboardPresentation.swift`

- [ ] **Step 6.1: 改 `DashboardInsight.swift`**

a. `enum DashboardFreshnessKind` 删 `case auth`（约 14 行）
b. `struct DashboardFreshnessContext` 删 `let cookieAvailable: Bool`（约 22 行）
c. `make(context:)` 删整段 `if !context.cookieAvailable { ... }`（约 103-125 行）
d. `dashboardFreshnessSummary` 构造 context 时去掉 `cookieAvailable: cookieAvailable,`（约 316 行）

用 grep 定位每处：
```bash
grep -n "case auth\|cookieAvailable" macos-app/Core/DashboardInsight.swift
```

- [ ] **Step 6.2: 改 `TodayBrief.swift`**

a. `enum TodayBriefKind` 删 `case login`（约 4 行）
b. `struct TodayBriefContext` 删 `let cookieAvailable: Bool`（约 47 行）
c. init 参数删 `cookieAvailable: Bool,`（约 67 行）
d. init 实现删 `self.cookieAvailable = cookieAvailable`（约 86 行）
e. `makeItems` 删整段 `if !context.cookieAvailable { ... TodayBriefItem(kind: .login, ...) }`（约 113-126 行）
f. `todayBriefContext` 构造时去掉 `cookieAvailable:` 参数（约 318-320 行）

- [ ] **Step 6.3: 改 `EnhancementDashboardPresentation.swift`**

a. `make(...)` 参数删 `cookieAvailable: Bool,`（约 227 行）
b. 内部 `makeRuntimeChips(...)` 调用去掉 `cookieAvailable: cookieAvailable`（约 269 行）
c. `makeRuntimeChips` 参数删 `cookieAvailable: Bool`（约 307 行）
d. 删 `EnhancementRuntimeChip(id: "cookie", title: "Cookie", ...)` 整段（约 314-318 行）

- [ ] **Step 6.4: 编译验证 Core**

Run: `cd macos-app && swift build 2>&1 | grep -v "Views/\|Tests/" | head -30`

Expected: Core 全绿。Views / Tests 还有报错。

- [ ] **Step 6.5: Commit**

```bash
git add macos-app/Core/DashboardInsight.swift macos-app/Core/TodayBrief.swift macos-app/Core/EnhancementDashboardPresentation.swift
git commit -m "refactor: Insight Core 移除 cookie 提示项"
```

---

## Task 7: Views 去 UI（ContentView + ForumSectionView + 删登录页）

**Files:**
- Delete: `macos-app/Views/QiemanLoginView.swift`（整文件）
- Delete: `macos-app/Core/QiemanCookieManager.swift`（整文件，放这里删因为 QiemanLoginView 是唯一调用方）
- Modify: `macos-app/Views/ContentView.swift`
- Modify: `macos-app/Views/ForumSectionView.swift`

- [ ] **Step 7.1: 删除登录页和 Cookie 管理器文件**

```bash
rm macos-app/Views/QiemanLoginView.swift
rm macos-app/Core/QiemanCookieManager.swift
```

- [ ] **Step 7.2: 改 `ContentView.swift`**

定位每处（用 grep）：
```bash
grep -n "isPresentingLoginSheet\|QiemanLoginView\|cookieAvailable\|cookieFileURL\|queryModeChip\|QueryMode.allCases\|spaceUserID\|brokerUserID\|spaceUserId\|broker_user_id\|brokerUserId" macos-app/Views/ContentView.swift
```

删除：
a. `.sheet(isPresented: $model.isPresentingLoginSheet) { QiemanLoginView(...) { model.handleCookieSavedFromLoginSheet() } }`（约 96-100 行）
b. sidebarFooter 里 Cookie 徽标：`Circle().fill(model.cookieAvailable ? ...)` + `Text(model.cookieAvailable ? "Cookie 可用" : "Cookie 缺失")`（约 148-153 行）
c. `queryToolbarPanel` 里的 QueryMode 芯片选择器（约 235-248 行整段 `ViewThatFits { HStack { ForEach(QueryMode.allCases)... } LazyVGrid { ... } }`）
d. `toolbarTitleBlock` 里 `ToolbarBadge(title: model.cookieAvailable ? "Cookie 可用" : "Cookie 缺失", ...)`（约 367-371 行）
e. `queryModeChip(mode:)` 整个方法（约 409-435 行）
f. `toolbarField("spaceUserId", text: $model.form.spaceUserID, minWidth: 180)`（约 346 行）— spaceUserID 字段已从 QueryFormState 删除
g. 若存在 `toolbarField("brokerUserId"/"broker_user_id", text: $model.form.brokerUserID, ...)` 文本框，一并删除 — brokerUserID 字段已删

**保留**：「打开数据目录」按钮（155-166 行）、刷新按钮、筛选面板里的产品/主理人/关键词等文本框。

- [ ] **Step 7.3: 改 `ForumSectionView.swift` 评论文案**

定位 190 行：
```bash
grep -n "登录态无法读取评论" macos-app/Views/ForumSectionView.swift
```

把 `"暂无评论，或当前登录态无法读取评论。"` 改为 `"暂无评论。"`。

- [ ] **Step 7.4: 编译验证 Views（除 Settings）**

Run: `cd macos-app && swift build 2>&1 | grep "Views/" | grep -v "Settings" | head -20`

Expected: ContentView / ForumSectionView 无错误。SettingsView 还有报错（Task 8 修）。

- [ ] **Step 7.5: Commit**

```bash
git add -A macos-app/Views/ContentView.swift macos-app/Views/ForumSectionView.swift macos-app/Views/QiemanLoginView.swift macos-app/Core/QiemanCookieManager.swift
git commit -m "refactor: 删除登录页和 Cookie 管理器，Views 去登录态 UI"
```

---

## Task 8: Settings 重组（删账号 tab、外观搬家到通用面板）

**Files:**
- Delete: `macos-app/Views/SettingsAccountPanel.swift`（整文件）
- Modify: `macos-app/Views/SettingsSectionView.swift`
- Modify: `macos-app/Views/SettingsAppPanel.swift`

- [ ] **Step 8.1: 删 SettingsAccountPanel.swift**

```bash
rm macos-app/Views/SettingsAccountPanel.swift
```

- [ ] **Step 8.2: 改 `SettingsSectionView.swift`**

a. `enum SettingsFocus` 删 `case account`（第 7 行），保留 `watch / menuBar / version`
b. `@State var isConfirmingDataDirectoryReset = false`（第 25 行）删除
c. `overviewBadges` 删 Cookie 徽标（约 115 行 `ToolbarBadge(title: model.cookieAvailable ? ...)`)
d. `overviewMetricButtons` 删「账号」metric 按钮（约 142-156 行整段 Button）
e. `selectedSettingsPanel` switch 删 `case .account: accountPanel`（约 209-211 行）

- [ ] **Step 8.3: 改 `SettingsAppPanel.swift` 把外观搬进来**

把 `SettingsAppPanel.swift` 改名为「通用」面板。完整替换为（吸收原 SettingsAccountPanel.swift:9-45 的外观设置代码）：

```swift
import SwiftUI

// MARK: - General Panel (Appearance / Version / Updates)

extension SettingsSectionView {
    var appPanel: some View {
        SettingsPanel(title: "通用", subtitle: "外观、版本与更新", icon: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(
                    title: "外观",
                    value: model.appearance.rawValue,
                    detail: "浅色 / 深色 / 跟随系统",
                    icon: "circle.lefthalf.filled",
                    tint: AppPalette.info
                )
                HStack(spacing: 8) {
                    ForEach(AppAppearance.allCases) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                model.appearance = mode
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: mode == .light ? "sun.max.fill" : mode == .dark ? "moon.fill" : "circle.lefthalf.filled")
                                    .font(.system(size: 11))
                                Text(mode.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(model.appearance == mode ? AppPalette.onBrand : AppPalette.muted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(model.appearance == mode ? AppPalette.brand : AppPalette.card)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(model.appearance == mode ? AppPalette.brand : AppPalette.line, lineWidth: 1)
                            )
                        }
                        .buttonStyle(PressResponsiveButtonStyle())
                    }
                    Spacer()
                }
                .padding(.vertical, 6)

                SettingsDivider()

                SettingsToggleRow(
                    title: "启动时检查更新",
                    detail: "每次打开应用自动检测新版本",
                    icon: "arrow.triangle.2.circlepath",
                    tint: AppPalette.brand,
                    isOn: $model.autoCheckForUpdatesOnLaunch
                )
                SettingsDivider()
                SettingsRow(
                    title: "更新状态",
                    value: model.isCheckingForUpdates ? "检查中" : (model.availableUpdate == nil ? "暂无更新" : "发现更新"),
                    detail: model.isCheckingForUpdates ? "正在检查 GitHub Release" : (model.availableUpdate == nil ? "可手动检查 GitHub Release" : "可下载并安装"),
                    icon: "app.badge",
                    tint: model.availableUpdate == nil ? AppPalette.info : AppPalette.positive
                )
                if let update = model.availableUpdate {
                    SettingsDivider()
                    SettingsRow(
                        title: "可用更新",
                        value: update.version,
                        detail: update.asset?.name ?? "Release 可查看",
                        icon: "sparkles",
                        tint: AppPalette.positive
                    )
                }

                SettingsDivider()

                SettingsActionRow {
                    Button {
                        Task { await model.checkForUpdates(userInitiated: true) }
                    } label: {
                        Label(model.isCheckingForUpdates ? "检查中…" : "检查更新", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.brand)
                    .disabled(model.isCheckingForUpdates)

                    if model.availableUpdate != nil {
                        Button {
                            Task { await model.downloadAndInstallAvailableUpdate() }
                        } label: {
                            Label(model.isInstallingUpdate ? "安装中…" : "下载并安装", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isInstallingUpdate)

                        Button {
                            model.openAvailableUpdateReleasePage()
                        } label: {
                            Label("Release", systemImage: "safari")
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    Button {
                        model.quitApplication()
                    } label: {
                        Label("退出应用", systemImage: "power")
                    }
                    .buttonStyle(.bordered)
                    .tint(AppPalette.danger)
                    .help("退出且慢主理人看板")
                }

                if !model.updateInstallProgress.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if model.updateDownloadFraction > 0 {
                            ProgressView(value: model.updateDownloadFraction, total: 1.0)
                                .progressViewStyle(.linear)
                                .tint(AppPalette.brand)
                        }
                        ToastBar(text: model.updateInstallProgress, tint: AppPalette.info)
                    }
                    .padding(.top, 12)
                }
            }
        }
    }
}
```

- [ ] **Step 8.4: 编译验证整体**

Run: `cd macos-app && swift build 2>&1 | head -40`

Expected: App 主体全绿（Tests 还会有报错）。

- [ ] **Step 8.5: Commit**

```bash
git add -A macos-app/Views/SettingsAccountPanel.swift macos-app/Views/SettingsSectionView.swift macos-app/Views/SettingsAppPanel.swift
git commit -m "refactor: 删除账号面板，外观设置合并到通用面板"
```

---

## Task 9: 测试改动（删 1 个、改 5 个）

**Files:**
- Delete: `macos-app/Tests/QiemanDashboardTests/QiemanCookieManagerTests.swift`
- Modify: `macos-app/Tests/QiemanDashboardTests/DashboardInsightTests.swift`
- Modify: `macos-app/Tests/QiemanDashboardTests/TodayBriefBuilderTests.swift`
- Modify: `macos-app/Tests/QiemanDashboardTests/EnhancementDashboardPresentationTests.swift`
- Modify: `macos-app/Tests/QiemanDashboardTests/UIExperienceRegressionTests.swift`
- Modify: `macos-app/Tests/QiemanDashboardTests/CLIContractSnapshotTests.swift`

- [ ] **Step 9.1: 删 Cookie 管理器测试**

```bash
rm macos-app/Tests/QiemanDashboardTests/QiemanCookieManagerTests.swift
```

- [ ] **Step 9.2: 运行测试看失败列表**

Run: `cd macos-app && swift test 2>&1 | grep -E "error:|warning:" | head -40`

Expected: 编译错误集中在 5 个测试文件，记录每个错误位置。

- [ ] **Step 9.3: 改 `DashboardInsightTests.swift`**

定位：
```bash
grep -n "cookieAvailable\|\.auth\|3 个异常" macos-app/Tests/QiemanDashboardTests/DashboardInsightTests.swift
```

a. `DashboardFreshnessContext(...)` 构造去掉 `cookieAvailable: false,`
b. `XCTAssertEqual(summary.items.prefix(3).map(\.kind), [.system, .managerWatch, .auth])` → 改为 `XCTAssertEqual(summary.items.prefix(2).map(\.kind), [.system, .managerWatch])`
c. headline `"3 个异常待处理"` → `"2 个异常待处理"`

- [ ] **Step 9.4: 改 `TodayBriefBuilderTests.swift`**

定位：
```bash
grep -n "cookieAvailable\|\.login" macos-app/Tests/QiemanDashboardTests/TodayBriefBuilderTests.swift
```

a. 所有 `TodayBriefContext(...)` 调用去掉 `cookieAvailable:` 参数
b. `testMakeItemsShowsSetupWhenPortfolioIsMissing`：
   - `items.map(\.kind)` 断言从 `[.login, .importPortfolio]` 改为 `[.importPortfolio]`
   - `items.first?.destination` 断言相应调整（原本 first 是 `.login` → `.settings`，现在 first 是 `.importPortfolio` → `.portfolio`）。实施时先读该测试方法的完整代码，确认所有引用 `.login` / `.settings` 的断言并同步改为 `.importPortfolio` / `.portfolio`。若该测试方法还断言了第二项（`.importPortfolio`），删除对第二项的断言（因为现在只剩一项）。

- [ ] **Step 9.5: 改 `EnhancementDashboardPresentationTests.swift`**

定位：
```bash
grep -n "cookieAvailable\|cookie\|\"Cookie\"" macos-app/Tests/QiemanDashboardTests/EnhancementDashboardPresentationTests.swift
```

a. `makeDashboard` 助手参数去掉 `cookieAvailable: Bool = true`
b. `EnhancementDashboardSummary.make(...)` 调用去掉 `cookieAvailable: cookieAvailable`
c. 若有用例断言 cookie chip 存在/值，删除该断言

- [ ] **Step 9.6: 改 `UIExperienceRegressionTests.swift`**

删整个 `testDestructiveSettingsAndLoginActionsRequireConfirmation()` 方法（84-91 行）。保留 `testQuitApplicationIsReachableFromMenuBarPopoverAndSettings`（93-106 行）。

- [ ] **Step 9.7: 改 `CLIContractSnapshotTests.swift`**

定位：
```bash
grep -n "CLIAuthStatusOutput\|following-posts" macos-app/Tests/QiemanDashboardTests/CLIContractSnapshotTests.swift
```

a. `testSnakeCaseConversionPreservesExistingKeys`：把演示 DTO 从 `CLIAuthStatusOutput` 换成保留下来的 DTO。实施步骤：
   1. 读该测试方法完整代码，看它实例化 `CLIAuthStatusOutput` 时用了哪些字段（snake_case 锁定的是编码策略，不依赖具体字段值）。
   2. 在 `macos-app/Core/CLI/DTOs.swift` 里找一个保留下来的、字段含 camelCase 的 DTO 作为替代，优先 `CLISnapshotGroupRow`（它有 `groupManagerName` / `managerBrokerUserId` 等 camelCase 字段，能验证 snake_case 转换）。
   3. 用该替代 DTO 改写测试实例化和编码断言，保持原有的 snake_case 键名断言逻辑。
   4. 运行该测试确认通过。

b. `testWatchStateRoundTripsPreservingSnakeCaseKeys`：`forumSource: "following-posts"` → `"public-group"`，断言 `json["forum_source"] as? String == "following-posts"` → `== "public-group"`。

- [ ] **Step 9.8: 运行测试**

Run: `cd macos-app && swift test 2>&1 | tail -20`

Expected: 全部测试 PASS。

- [ ] **Step 9.9: Commit**

```bash
git add -A macos-app/Tests/
git commit -m "test: 适配登录态删除后的断言"
```

---

## Task 10: 全量验证 + 残留符号 grep

- [ ] **Step 10.1: App + CLI 完整构建**

Run:
```bash
APP_VERSION=3.4.0 bash scripts/build_macos_app.sh 2>&1 | tail -10
bash scripts/build_qieman_cli.sh 2>&1 | tail -5
```

Expected: App 构建成功，CLI 构建成功。

- [ ] **Step 10.2: swift test 全绿**

Run: `cd macos-app && swift test 2>&1 | tail -5`

Expected: 全部 PASS。

- [ ] **Step 10.3: 残留符号 grep（应 0 命中，注释除外）**

Run:
```bash
cd macos-app
for sym in cookieAvailable cookieFileURL nativeCookieExists cookieExists validateAuth authPayload isCheckingAuth isPresentingLoginSheet presentLoginSheet handleCookieSavedFromLoginSheet QiemanLoginView QiemanCookieManager fetchFollowingPosts fetchFollowingUsers fetchMyGroups fetchAuthUserInfo fetchSpaceItemsSnapshot fetchSpaceUserInfo resolveSpaceUserID NativeSpaceUserInfo loadCookie rawCookie missingCookie missingSpaceUser extractAccessToken decodeJWTPayload StatusPayload BootstrapPayload DefaultFormPayload AuthCheckPayload CLIAuthStatusOutput AuthState; do
  hits=$(grep -rn "$sym" --include="*.swift" . | grep -v "//" | wc -l | tr -d ' ')
  if [ "$hits" != "0" ]; then
    echo "❌ $sym: $hits hits"
    grep -rn "$sym" --include="*.swift" . | grep -v "//" | head -5
  fi
done
echo "--- QueryMode cases ---"
for sym in followingPosts followingUsers myGroups spaceItems; do
  hits=$(grep -rn "$sym" --include="*.swift" . | grep -v "//" | wc -l | tr -d ' ')
  if [ "$hits" != "0" ]; then
    echo "❌ $sym: $hits hits"
    grep -rn "$sym" --include="*.swift" . | grep -v "//" | head -5
  fi
done
echo "--- QueryFormState 字段 ---"
for sym in "form.spaceUserID\|form.brokerUserID\|var spaceUserID\|var brokerUserID"; do
  hits=$(grep -rnE "$sym" --include="*.swift" . | grep -v "//" | wc -l | tr -d ' ')
  if [ "$hits" != "0" ]; then
    echo "❌ $sym: $hits hits"
    grep -rnE "$sym" --include="*.swift" . | grep -v "//" | head -5
  fi
done
echo "--- CLI commands ---"
for cmd in "auth-status" "following-posts" "following-users" "my-groups" "space-items"; do
  hits=$(grep -rn "$cmd" --include="*.swift" . | wc -l | tr -d ' ')
  if [ "$hits" != "0" ]; then
    echo "⚠️  $cmd: $hits hits (可能是历史快照 meta 字面量，需人工判断)"
    grep -rn "$cmd" --include="*.swift" . | head -3
  fi
done
echo "Done."
```

Expected: 上面几组都无 ❌；CLI commands 那组的命中应该只在注释或字符串字面量里（如测试里的快照 meta），人工判断可接受。
**例外（允许残留）**：`SnapshotRecordPayload.spaceUserId` / `CLISnapshotRecordRow.spaceUserId` / `NativeSnapshotStore` 对 `space_user_id` 的解析——这些是历史快照 JSON 兼容字段，刻意保留，不报错。
echo "Done."
```

Expected: 上面三组都无 ❌；CLI commands 那组的命中应该只在注释或字符串字面量里（如测试里的快照 meta），人工判断可接受。

- [ ] **Step 10.4: 手工 smoke（可选但推荐）**

```bash
open dist/macos-app/QiemanDashboard.app
```

检查：
- 无登录入口，无 Cookie 徽标
- 论坛板块默认显示主理人发言；评论区按钮可见
- 设置面板只剩「巡检 / 菜单栏 / 通用」三项
- 「通用」面板里有外观切换 + 更新检查
- 筛选面板里没有 spaceUserId / brokerUserId 文本框

CLI smoke：
```bash
scripts/qieman version
scripts/qieman auth-status 2>&1 | head -3  # 应报 unknown command
scripts/qieman space-items 2>&1 | head -3  # 应报 unknown command
scripts/qieman group-posts --prod-code LONG_WIN 2>&1 | head -3  # 应正常输出
```

- [ ] **Step 10.5: 更新 AGENTS.md（可选）**

如果 AGENTS.md 里有提到登录态/Cookie 的段落，同步删除或更新。

```bash
grep -n "Cookie\|登录态\|cookie" AGENTS.md
```

若有，按现状更新。

- [ ] **Step 10.6: 最终 Commit**

```bash
git add -A
git commit -m "chore: 删除登录态功能后的全量验证"
```

---

## 完成标准

- [ ] App 构建（`APP_VERSION=3.4.0 bash scripts/build_macos_app.sh`）通过
- [ ] CLI 构建（`bash scripts/build_qieman_cli.sh`）通过
- [ ] `swift test` 全绿
- [ ] 残留符号 grep 无 ❌
- [ ] 手工 smoke 通过
- [ ] 每个 Task 一个 commit，提交信息清晰

## 回滚

纯删除性提交，整体回滚只需 `git revert <commit-range>`。
