# 主理人多选控件 — 设计文档（筛选重构 v2）

- **日期**: 2026-07-21
- **状态**: Draft，待用户审阅
- **影响版本**: v3.5.0
- **前置**: v3.4.1（已删除登录态，已合并关注列表功能）
- **相关**: `docs/superpowers/specs/2026-07-21-remove-login-state-design.md` 第 13-14 节（调研历程）

## 1. 背景与目标

### 1.1 用户需求

把社区动态筛选从「一堆文本框（手填 prodCode/managerName/关键词等）」改为「主理人多选 + 联想搜索」控件，让用户能同时订阅多个主理人的发言合并展示。

### 1.2 关键事实（HAR 实测确认）

- 且慢社区共 **6 个小组**（`/community/group/awesome-list`，totalCount=6）。
- 每个小组 1 个 leader，其中**只有 2 个是产品主理人**：ETF拯救世界（长赢，groupId=43）、稳稳幸福主理人（交银，groupId=19）。其余 4 个是社区运营号。
- 主理人信息**公开可得**（`awesome-list` + `manager-info`），**不需要登录态**。
- 6 个小组里只有 groupId=43（长赢）和 groupId=19（稳稳幸福）绑定可调仓的产品；其余 4 个没有调仓数据。

### 1.3 为什么是多选

用户明确要求多选——能同时订阅 E大 + 稳稳幸福的发言合并展示。单选做不到。

### 1.4 设计原则

- **不破坏现有功能**：ManagerWatch（巡检）、CLI、关注列表等保持工作。
- **不恢复登录态**：公开接口够用。
- **最小改动**：优先新增，避免大范围重构。

## 2. 数据模型

### 2.1 `ManagerSummary`（cherry-pick Task 11）

```swift
struct ManagerSummary: Identifiable, Hashable, Codable {
    let brokerUserId: String
    let userName: String
    let userLabel: String
    let userAvatarURL: String
    let groupId: Int
    let groupName: String

    var id: String { brokerUserId }
}
```

### 2.2 `QueryFormState` 扩展（保留旧字段 + 新增筛选模式开关）

**关键决策**：保留现有字段，**新增** `selectedManagerIds: Set<String>` 和 `filterMode` 枚举。两套机制**互斥**（由 filterMode 切换），不并存。

```swift
enum FilterMode: String, CaseIterable {
    case managerSubscription   // 主理人订阅（多选，走 fetchMultiGroupSnapshot）
    case preciseParams         // 精确参数（prodCode/managerName/关键词/日期，走 fetchSnapshot）
}

struct QueryFormState {
    var filterMode: FilterMode = .managerSubscription   // 新增：默认主理人订阅
    var selectedManagerIds: Set<String> = []            // 新增：主理人多选
    var mode: QueryMode = .groupManager                 // 保留
    var prodCode: String = "LONG_WIN"                   // 保留：精确模式 + ManagerWatch 用
    var managerName: String = ""                        // 保留
    // ... 其他字段保留
}
```

**互斥规则**（解决原 spec 第 10 节的"两套并存困惑"风险）：
- `filterMode == .managerSubscription`：UI 只显示 ManagerPicker，抓取走 `fetchMultiGroupSnapshot`。"同步到巡检"按钮隐藏（巡检是单值，多选不同步）。
- `filterMode == .preciseParams`：UI 只显示现有文本框（prodCode/managerName/关键词/日期），抓取走 `fetchSnapshot`。"同步到巡检"按钮显示。

理由：两套机制的抓取语义不同（多选=多小组并集无筛选；精确=单小组+关键词/日期筛选），并存会产生歧义。互斥让行为明确，UI 也更清爽。

ManagerWatch 仍零改动：它的 `fetchForumWatchSnapshot(prodCode:managerName:)` 直接用 `managerWatchSettings` 里的值构造 form，不依赖 `form.filterMode`。

## 3. NativeClient 改造

### 3.1 新增 `fetchManagerIndex()`（cherry-pick Task 11）

拉 awesome-list（1 次）+ 每个小组 manager-info（6 次），返回 `[ManagerSummary]`，按 userName 排序。

### 3.2 新增 `fetchMultiGroupSnapshot(groupIds:pages:pageSize:persist:outputDirectory:)`（来自 Task 12，改造）

多小组顺序抓取 → 合并 → 按 postId 去重 → 按 created_at 降序。

**关键**：这是**新增**方法，**不删** `fetchSnapshot(form:)`。ManagerWatch 继续用 `fetchSnapshot`。

### 3.3 抽取 `mergeAndSortPosts`（来自 Task 12）

static 纯函数，可测试。

### 3.4 保留的现有方法

- `fetchSnapshot(form:)` — ManagerWatch 用，不动。
- `resolveGroupID` / `fetchGroupManagerSnapshot` / `postMatchesFilters` — 不动。
- `fetchComments` — 评论功能，不动。

## 4. AppModel 改造

### 4.1 新增主理人索引状态

```swift
@Published private(set) var managerIndex: [ManagerSummary] = []
@Published private(set) var isLoadingManagerIndex = false
@Published private(set) var managerIndexError: String?
```

### 4.2 新增 `loadManagerIndex()`

```swift
func loadManagerIndex() async {
    guard !isLoadingManagerIndex else { return }
    isLoadingManagerIndex = true
    managerIndexError = nil
    do {
        managerIndex = try await nativeClient.fetchManagerIndex()
    } catch {
        managerIndexError = error.localizedDescription
    }
    isLoadingManagerIndex = false
}
```

### 4.3 `start()` 触发首次加载

`Task { await loadManagerIndex() }`

### 4.4 `refreshLatest` 分支（按 filterMode）

```swift
let snapshot: SnapshotPayload
switch currentForm.filterMode {
case .managerSubscription:
    let groupIds = currentForm.selectedManagerIds.compactMap { id in
        managerIndex.first { $0.brokerUserId == id }?.groupId
    }
    guard !groupIds.isEmpty else {
        throw NativeQiemanError.noResults("请至少选择一位主理人。")
    }
    snapshot = try await nativeClient.fetchMultiGroupSnapshot(
        groupIds: groupIds, pages: ..., pageSize: ..., persist: false, outputDirectory: nil
    )
case .preciseParams:
    snapshot = try await nativeClient.fetchSnapshot(form: currentForm, persist: false, outputDirectory: nil)
}
```

### 4.5 ManagerWatch 零改动

ManagerWatch 继续用 prodCode/managerName + `fetchSnapshot`。它的 `fetchForumWatchSnapshot(prodCode:managerName:)` 不动。

## 5. UI 改造（ContentView 筛选面板）

### 5.1 新增 `ManagerPicker` 组件

`macos-app/Views/ManagerPicker.swift`：

- 搜索框 + 候选列表 + 已选芯片。
- 数据来自 `model.managerIndex`。
- 候选按 userName/userLabel/groupName 模糊匹配。
- 已选主理人显示为芯片（× 可删）。
- 加载中显示「正在加载主理人列表…」，失败显示错误 + 重试。
- 用现有 `FlowLayout`（`SharedComponents.swift` 已有）布局芯片。

### 5.2 ContentView 筛选面板：模式切换 + 互斥显示

筛选面板顶部加一个**分段控件**（Picker segmented）切换 filterMode：

```swift
Picker("筛选模式", selection: $model.form.filterMode) {
    Text("主理人订阅").tag(FilterMode.managerSubscription)
    Text("精确参数").tag(FilterMode.preciseParams)
}
.pickerStyle(.segmented)
```

下方内容**根据 filterMode 互斥显示**：

```swift
switch model.form.filterMode {
case .managerSubscription:
    ManagerPicker(
        managers: model.managerIndex,
        selectedIds: model.form.selectedManagerIds,
        isLoading: model.isLoadingManagerIndex,
        error: model.managerIndexError,
        onToggle: { id in
            if model.form.selectedManagerIds.contains(id) {
                model.form.selectedManagerIds.remove(id)
            } else {
                model.form.selectedManagerIds.insert(id)
            }
        },
        onRetry: { Task { await model.loadManagerIndex() } }
    )
case .preciseParams:
    // 现有的 prodCode/managerName/关键词/日期/页数文本框（原样搬过来）
    preciseParamsPanel
}
```

### 5.3 "同步到巡检"按钮的可见性

`syncManagerWatchTargetsFromCurrentForm` 在两处调用（SettingsWatchPanel、ManagerWatchControlCard）。在主理人订阅模式下，多选无法同步到单值巡检设置，按钮**隐藏**或**禁用**。精确参数模式下正常显示。

实现：调用点加 `if model.form.filterMode == .preciseParams` 守卫，或按钮的 `.disabled(model.form.filterMode == .managerSubscription)`。

### 5.4 默认模式

`filterMode` 默认 `.managerSubscription`（主理人订阅）——这是新用户的首选体验。高级用户可切到精确参数。

## 6. CLI（可选，本阶段不做）

本阶段不改 CLI。`group-posts` 保持现有 prodCode/managerName 参数。`fetchManagerIndex` 是 public 方法，未来 CLI 可加 `managers` 命令暴露。

## 7. 测试

### 7.1 新增 `ManagerPickerTests` 或 `ManagerIndexTests`

- 测 `fetchManagerIndex` 的解析（mock awesome-list + manager-info 响应，或抽纯函数测）。
- 测 `mergeAndSortPosts`（来自 Task 12）：去重、按时间排序、空输入。

### 7.2 不破坏现有测试

293 个现有测试保持通过。

## 8. 实施步骤（高层）

1. cherry-pick Task 11（ManagerSummary + fetchManagerIndex）到新分支。
2. 改造 Task 12：只取 `fetchMultiGroupSnapshot` + `fetchSingleGroupPosts` + `mergeAndSortPosts`，**不删** fetchSnapshot/resolveGroupID/postMatchesFilters/QueryFormState 字段。
3. AppModel 加 managerIndex 状态 + loadManagerIndex + refreshLatest 分支。
4. 新增 ManagerPicker 组件 + ContentView 插入。
5. 测试。
6. 全量验证 + 发版 v3.5.0。

## 9. 不在范围

- 不恢复登录态。
- 不改 ManagerWatch 数据模型（prodCode/managerName 保留）。
- 不改 CLI。
- 不删任何现有字段/方法（纯新增 + 一个 refreshLatest 分支）。
- 不做机构主理人（/m4/hand-picked 的 author）。

## 10. 风险

- **主理人只有 2 个有用**：多选控件的"多选"价值有限，但为未来扩展（新主理人加入社区）打基础。可接受。
- **fetchManagerIndex 拉 6 个小组要 7 个请求**：首次加载几百毫秒，可接受。失败有重试。
- ~~**selectedManagerIds 与 prodCode 并存**~~：已通过 filterMode 互斥模式解决（见 2.2、5.2），两套机制不再并存。
- **模式切换的状态保持**：用户在主理人订阅模式选了几个主理人，切到精确参数再切回来，selectedManagerIds 应保留（不丢失）。`filterMode` 和 `selectedManagerIds` 都是 QueryFormState 的字段，SwiftUI 状态自然保持。
