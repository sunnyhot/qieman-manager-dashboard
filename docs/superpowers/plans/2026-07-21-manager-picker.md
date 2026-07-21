# 主理人多选控件 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给社区动态筛选加「主理人订阅（多选）」模式，与现有「精确参数」模式互斥切换；不破坏 ManagerWatch/CLI/现有测试。

**Architecture:** 纯新增——保留所有现有字段/方法，新增 `FilterMode` + `selectedManagerIds` + `fetchMultiGroupSnapshot` + `ManagerPicker` 组件。ManagerWatch 零改动。代码主体从 feat 分支已 review 过的 Task 11/12 cherry-pick + 改造。

**Tech Stack:** Swift 5（macOS 14+ SwiftUI），SPM 测试。

**Spec:** `docs/superpowers/specs/2026-07-21-manager-picker-design.md`

**基准 commit:** `334632e`（main，v3.4.1 + spec）

---

## 文件结构总览

### 新增文件（2）
- `macos-app/Core/Models/ManagerSummary.swift`（cherry-pick feat 29fdd60）
- `macos-app/Views/ManagerPicker.swift`

### 修改文件（5）
- `macos-app/Core/Models/Query.swift`（加 FilterMode + selectedManagerIds，不删旧字段）
- `macos-app/Core/QiemanNativeClient.swift`（加 fetchManagerIndex + fetchMultiGroupSnapshot + fetchSingleGroupPosts + mergeAndSortPosts + dateKeyForSort）
- `macos-app/Core/AppModel.swift`（加 managerIndex 状态 + loadManagerIndex + refreshLatest 分支 + start 触发）
- `macos-app/Views/ContentView.swift`（筛选面板加模式切换 + ManagerPicker）
- `scripts/build_qieman_cli.sh`（加 ManagerSummary.swift）

### 修改文件（同步到巡检按钮可见性，2 处）
- `macos-app/Views/SettingsWatchPanel.swift`
- `macos-app/Views/Overview/ManagerWatchControlCard.swift`

### 新增测试（1）
- `macos-app/Tests/QiemanDashboardTests/MultiGroupSnapshotTests.swift`

---

## Task 1: cherry-pick + 改造 NativeClient 层

**Files:**
- Create: `macos-app/Core/Models/ManagerSummary.swift`
- Modify: `macos-app/Core/QiemanNativeClient.swift`
- Modify: `scripts/build_qieman_cli.sh`

这一步从 feat 分支 cherry-pick Task 11（纯新增，无破坏），再手工添加 Task 12 的多小组抓取方法（只加不删）。

- [ ] **Step 1.1: 从 feat 分支 cherry-pick Task 11（ManagerSummary + fetchManagerIndex）**

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard
git cherry-pick 29fdd60
```

这个 commit 是纯新增（ManagerSummary.swift + fetchManagerIndex 方法 + build_qieman_cli.sh 加一行），不会冲突。cherry-pick 后验证：
```bash
ls macos-app/Core/Models/ManagerSummary.swift
grep -n "func fetchManagerIndex" macos-app/Core/QiemanNativeClient.swift
cd macos-app && swift build 2>&1 | tail -2
```
预期：文件存在、方法存在、编译通过（293 测试不受影响）。

- [ ] **Step 1.2: 在 QiemanNativeClient 加 fetchMultiGroupSnapshot + 辅助方法**

在 `macos-app/Core/QiemanNativeClient.swift` 的 `fetchSnapshot` 方法**之后**、`fetchComments` 方法**之前**，插入以下 4 个方法（来自 feat 分支 Task 12，已 review 通过）：

```swift
/// 多小组顺序抓取：遍历选定的主理人所在小组，依次抓帖子、合并去重、按时间倒序排序。
/// 单个小组失败不中断其他小组，失败信息累积到 failures。
func fetchMultiGroupSnapshot(groupIds: [Int], pages: Int, pageSize: Int, persist: Bool, outputDirectory: URL?) async throws -> SnapshotPayload {
    let uniqueIDs = Array(Set(groupIds)).sorted()
    guard !uniqueIDs.isEmpty else {
        throw NativeQiemanError.noResults("请至少选择一位主理人。")
    }

    var failures: [String] = []
    var allPosts: [[String: Any]] = []
    var groups: [[String: Any]] = []
    for groupId in uniqueIDs {
        do {
            let group = try await fetchGroupInfo(groupID: groupId, source: "manager-index")
            let posts = try await fetchSingleGroupPosts(groupId: groupId, group: group, pages: pages, pageSize: pageSize)
            groups.append(groupDictionary(group))
            allPosts.append(contentsOf: posts)
        } catch {
            failures.append("group \(groupId): \(error.localizedDescription)")
        }
    }

    let sorted = Self.mergeAndSortPosts(allPosts)

    guard !sorted.isEmpty else {
        throw NativeQiemanError.noResults(failures.isEmpty ? "没有抓到主理人发言。" : "抓取失败：\(failures.joined(separator: "; "))")
    }

    let raw: [String: Any] = [
        "groups": groups,
        "filters": ["group_ids": uniqueIDs.map(String.init).joined(separator: ",")],
        "posts": sorted,
    ]
    let fileStem = safeFileStem(groups.count == 1 ? (groups.first.flatMap { $0["manager_name"] as? String } ?? "managers") : "managers")
    return try buildSnapshot(raw: raw, fileStem: fileStem, suffix: "community", persist: persist, outputDirectory: outputDirectory)
}

private func fetchSingleGroupPosts(groupId: Int, group: NativeGroupInfo, pages: Int, pageSize: Int) async throws -> [[String: Any]] {
    var posts: [[String: Any]] = []
    let targetUserID = group.managerBrokerUserId
    for pageNum in 1...pages {
        let payload = try await requestJSON(
            path: "/community/post/list",
            params: [
                "pageNum": String(pageNum),
                "pageSize": String(pageSize),
                "groupId": String(groupId),
                "postType": "1",
                "queryStrategy": "ONLY_GROUP_POST",
                "orderBy": "TIME",
            ],
            cookie: nil
        )
        let items = extractItemsFromGroupList(payload)
        if items.isEmpty { break }
        for item in items {
            let post = parsePostItem(item, defaultGroup: group)
            if !targetUserID.isEmpty, normalizedString(post["broker_user_id"]) != targetUserID {
                continue
            }
            posts.append(post)
        }
        if pageNum < pages {
            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }
    return posts
}

static func mergeAndSortPosts(_ posts: [[String: Any]]) -> [[String: Any]] {
    var seen: Set<Int> = []
    let deduped = posts.filter { post in
        let postId: Int
        if let id = post["post_id"] as? Int {
            postId = id
        } else if let s = post["post_id"] as? String, let parsed = Int(s) {
            postId = parsed
        } else {
            postId = 0
        }
        if postId > 0 {
            if seen.contains(postId) { return false }
            seen.insert(postId)
        }
        return true
    }
    return deduped.sorted { lhs, rhs in
        Self.dateKeyForSort(lhs["created_at"]) > Self.dateKeyForSort(rhs["created_at"])
    }
}

private static func dateKeyForSort(_ value: Any?) -> Int {
    let str: String
    if let s = value as? String {
        str = s
    } else if let n = value as? NSNumber {
        str = n.stringValue
    } else {
        return 0
    }
    let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return 0 }
    let text = trimmed.count >= 10 ? String(trimmed.prefix(10)) : trimmed
    return Int(text.replacingOccurrences(of: "-", with: "")) ?? 0
}
```

**注意**：这些方法依赖现有的 `fetchGroupInfo`、`groupDictionary`、`requestJSON`、`extractItemsFromGroupList`、`parsePostItem`、`normalizedString`、`safeFileStem`、`buildSnapshot`、`NativeGroupInfo`——全部保留（不删任何现有方法）。插入前 grep 确认这些都还在：
```bash
grep -n "func fetchGroupInfo\|func groupDictionary\|func extractItemsFromGroupList\|func parsePostItem\|func buildSnapshot\|struct NativeGroupInfo" macos-app/Core/QiemanNativeClient.swift
```

- [ ] **Step 1.3: 编译验证**

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard/macos-app
swift build 2>&1 | tail -3
```
预期：`Build complete!`，0 错误。新增方法独立，不破坏现有。

- [ ] **Step 1.4: Commit**

```bash
git add -A
git commit -m "feat: NativeClient 新增多小组抓取（fetchMultiGroupSnapshot + mergeAndSortPosts）"
```

---

## Task 2: QueryFormState 加 FilterMode + selectedManagerIds

**Files:**
- Modify: `macos-app/Core/Models/Query.swift`

- [ ] **Step 2.1: 加 FilterMode 枚举 + selectedManagerIds 字段**

先读当前 Query.swift：
```bash
cat macos-app/Core/Models/Query.swift
```

在文件顶部（`enum QueryMode` 之前）加 FilterMode 枚举：
```swift
enum FilterMode: String, CaseIterable, Identifiable {
    case managerSubscription = "manager-subscription"
    case preciseParams = "precise-params"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .managerSubscription:
            return "主理人订阅"
        case .preciseParams:
            return "精确参数"
        }
    }
}
```

在 `struct QueryFormState` 的第一个字段位置加：
```swift
var filterMode: FilterMode = .managerSubscription
var selectedManagerIds: Set<String> = []
```

**保留**所有现有字段（mode/prodCode/managerName/userName/keyword/since/until/pages/pageSize/autoRefresh）不动。

在 `fetchPayload` 方法里加这两个新字段到返回字典（可选，保持一致性）：
```swift
"filter_mode": filterMode.rawValue,
"selected_manager_ids": selectedManagerIds.sorted(),
```

- [ ] **Step 2.2: 编译验证**

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard/macos-app
swift build 2>&1 | grep "error:" | head
```
预期：0 错误（纯新增字段，现有调用不破坏）。

- [ ] **Step 2.3: Commit**

```bash
git add macos-app/Core/Models/Query.swift
git commit -m "feat: QueryFormState 新增 FilterMode 和 selectedManagerIds 字段"
```

---

## Task 3: AppModel 加 managerIndex 状态 + refreshLatest 分支

**Files:**
- Modify: `macos-app/Core/AppModel.swift`

- [ ] **Step 3.1: 加 managerIndex 状态字段**

在 AppModel.swift 的 `@Published` 区域（其他 `@Published private(set) var` 附近）加：
```swift
@Published private(set) var managerIndex: [ManagerSummary] = []
@Published private(set) var isLoadingManagerIndex = false
@Published private(set) var managerIndexError: String?
```

- [ ] **Step 3.2: 加 loadManagerIndex 方法**

在 `macos-app/Core/AppModel/Auth.swift`（或合适的 extension，和其他 load 方法放一起）加：
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

- [ ] **Step 3.3: start() 触发首次加载**

在 AppModel.swift 的 `func start()` 里（其他 `Task { ... }` 附近）加：
```swift
Task { await loadManagerIndex() }
```

- [ ] **Step 3.4: refreshLatest 加 filterMode 分支**

定位 AppModel.swift 第 581 行附近 `async let snapshotTask = nativeClient.fetchSnapshot(form: currentForm, ...)`。

**改造**：把这个 `async let` 包进 filterMode 分支。先读 refreshLatest 完整逻辑（581 行附近的 do/catch 结构），理解 snapshotTask 怎么被 await 的。

改造方案（保持原有 async let + do/catch 结构）：
```swift
let currentForm = form
async let snapshotTask: SnapshotPayload = {
    switch currentForm.filterMode {
    case .managerSubscription:
        let groupIds = currentForm.selectedManagerIds.compactMap { id in
            await MainActor.run { self.managerIndex.first { $0.brokerUserId == id }?.groupId }
        }
        // 注意：managerIndex 是 @MainActor，访问要在主线程；上面 compactMap 的写法需调整
        // 更简单的写法：先在主线程算出 groupIds，再传进去
        return try await nativeClient.fetchMultiGroupSnapshot(
            groupIds: groupIds,
            pages: positiveInt(currentForm.pages, fallback: 5),
            pageSize: positiveInt(currentForm.pageSize, fallback: 10),
            persist: false,
            outputDirectory: nil
        )
    case .preciseParams:
        return try await nativeClient.fetchSnapshot(form: currentForm, persist: false, outputDirectory: nil)
    }
}()
```

**重要**：AppModel 是 @MainActor，managerIndex 访问没问题。但 `async let` 闭包里的 `self.managerIndex` 访问要注意线程。最安全的写法是**在 async let 之前先算出 groupIds**：

```swift
let currentForm = form
let selectedGroupIds: [Int] = currentForm.selectedManagerIds.compactMap { id in
    managerIndex.first { $0.brokerUserId == id }?.groupId
}
async let snapshotTask: SnapshotPayload = {
    switch currentForm.filterMode {
    case .managerSubscription:
        return try await nativeClient.fetchMultiGroupSnapshot(
            groupIds: selectedGroupIds,
            pages: positiveInt(currentForm.pages, fallback: 5),
            pageSize: positiveInt(currentForm.pageSize, fallback: 10),
            persist: false,
            outputDirectory: nil
        )
    case .preciseParams:
        return try await nativeClient.fetchSnapshot(form: currentForm, persist: false, outputDirectory: nil)
    }
}()
```

实施时先读 refreshLatest 的完整上下文，确认 async let 怎么和后面的 `try await snapshotTask` 配合，再按实际结构改造。如果 async let + switch 太复杂，可以把 snapshot 获取抽成一个私有方法 `fetchSnapshotForCurrentForm() async throws -> SnapshotPayload`，refreshLatest 里直接 `async let snapshotTask = fetchSnapshotForCurrentForm()`。

- [ ] **Step 3.5: 编译 + 测试验证**

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard/macos-app
swift build 2>&1 | grep "error:" | head
swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1
```
预期：0 编译错误，293 测试全过（filterMode 默认 .managerSubscription，但 selectedManagerIds 默认空，ManagerWatch 走自己路径不受影响——但 refreshLatest 默认分支变了，需确认现有测试不依赖 refreshLatest 的具体抓取路径）。

如果有测试因 refreshLatest 改造失败，分析原因（可能是 mock 了 fetchSnapshot 的测试），调整。

- [ ] **Step 3.6: Commit**

```bash
git add macos-app/Core/AppModel.swift macos-app/Core/AppModel/
git commit -m "feat: AppModel 加主理人索引，refreshLatest 按 filterMode 分支"
```

---

## Task 4: ManagerPicker 组件

**Files:**
- Create: `macos-app/Views/ManagerPicker.swift`

- [ ] **Step 4.1: 创建 ManagerPicker.swift**

```swift
import SwiftUI

/// 主理人多选 + 联想搜索控件。
struct ManagerPicker: View {
    let managers: [ManagerSummary]
    let selectedIds: Set<String>
    let isLoading: Bool
    let error: String?
    let onToggle: (String) -> Void
    let onRetry: () -> Void

    @State private var query: String = ""

    private var filtered: [ManagerSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return managers }
        return managers.filter {
            $0.userName.lowercased().contains(trimmed) ||
            $0.userLabel.lowercased().contains(trimmed) ||
            $0.groupName.lowercased().contains(trimmed)
        }
    }

    private var selectedManagers: [ManagerSummary] {
        managers.filter { selectedIds.contains($0.brokerUserId) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 已选主理人芯片
            if !selectedManagers.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(selectedManagers) { manager in
                        ManagerChip(manager: manager) {
                            onToggle(manager.brokerUserId)
                        }
                    }
                }
            }

            // 搜索框
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppPalette.muted)
                TextField("搜索主理人 / 小组", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppPalette.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                    .stroke(AppPalette.line, lineWidth: 1)
            )

            // 候选列表
            if isLoading {
                Text("正在加载主理人列表…")
                    .font(.system(size: 11))
                    .foregroundStyle(AppPalette.muted)
            } else if let error {
                VStack(alignment: .leading, spacing: 6) {
                    Text("加载失败：\(error)")
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.warning)
                    Button("重试") { onRetry() }
                        .font(.system(size: 11))
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filtered) { manager in
                        ManagerRow(
                            manager: manager,
                            isSelected: selectedIds.contains(manager.brokerUserId)
                        ) {
                            onToggle(manager.brokerUserId)
                        }
                    }
                    if filtered.isEmpty {
                        Text("没有匹配的主理人")
                            .font(.system(size: 11))
                            .foregroundStyle(AppPalette.muted)
                    }
                }
            }
        }
    }
}

private struct ManagerChip: View {
    let manager: ManagerSummary
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(manager.userName)
                .font(.system(size: 11, weight: .medium))
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppPalette.muted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppPalette.brand.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(AppPalette.brand.opacity(0.3), lineWidth: 1))
    }
}

private struct ManagerRow: View {
    let manager: ManagerSummary
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppPalette.brand : AppPalette.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.userName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppPalette.ink)
                    Text("\(manager.userLabel) · \(manager.groupName)")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

`FlowLayout` 已存在于 `Views/SharedComponents.swift:5`，直接复用。`AppPalette` 颜色用现有的（brand/card/line/muted/ink/warning）。

- [ ] **Step 4.2: 编译验证**

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard/macos-app
swift build 2>&1 | grep "ManagerPicker\|error:" | head
```
预期：0 错误。

- [ ] **Step 4.3: Commit**

```bash
git add macos-app/Views/ManagerPicker.swift
git commit -m "feat: 新增 ManagerPicker 主理人多选联想控件"
```

---

## Task 5: ContentView 筛选面板加模式切换

**Files:**
- Modify: `macos-app/Views/ContentView.swift`

- [ ] **Step 5.1: 读当前筛选面板结构**

```bash
cd macos-app
grep -n "collapsibleFilterPanel\|isQueryExpanded\|toolbarField\|社区动态筛选" Views/ContentView.swift | head
sed -n '224,310p' Views/ContentView.swift   # 看 collapsibleFilterPanel 完整结构
```

- [ ] **Step 5.2: 在筛选面板展开内容区加模式切换 + 互斥显示**

定位 `collapsibleFilterPanel` 里 `if isQueryExpanded { ... }` 的内容区（约 265 行起）。在现有「基本参数行」（toolbarField 那些）**之前**插入模式切换分段控件，并把现有文本框包进 `if model.form.filterMode == .preciseParams { ... }`。

改造后结构：
```swift
if isQueryExpanded {
    VStack(alignment: .leading, spacing: 10) {
        // 模式切换
        Picker("筛选模式", selection: $model.form.filterMode) {
            Text("主理人订阅").tag(FilterMode.managerSubscription)
            Text("精确参数").tag(FilterMode.preciseParams)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 320)

        // 互斥显示
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
            // 原有的 ViewThatFits { HStack { toolbarField... } LazyVGrid { ... } } 整块搬这里
            preciseParamsContent
        }

        // 日期范围行（两种模式都可能用？spec 说精确模式才有，先放 preciseParams 里）
    }
    ...
}
```

实施时把原有的 toolbarField ViewThatFits 那块抽成一个 `private var preciseParamsContent: some View`（或直接内联在 case 里），保持原样。

- [ ] **Step 5.3: 编译验证**

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard/macos-app
swift build 2>&1 | grep "ContentView\|error:" | head
```
预期：0 错误。

- [ ] **Step 5.4: Commit**

```bash
git add macos-app/Views/ContentView.swift
git commit -m "feat: 筛选面板加 filterMode 模式切换（主理人订阅/精确参数互斥）"
```

---

## Task 6: "同步到巡检"按钮可见性 + 测试 + 验证

**Files:**
- Modify: `macos-app/Views/SettingsWatchPanel.swift`
- Modify: `macos-app/Views/Overview/ManagerWatchControlCard.swift`
- Create: `macos-app/Tests/QiemanDashboardTests/MultiGroupSnapshotTests.swift`

- [ ] **Step 6.1: "同步到巡检"按钮在主理人订阅模式下禁用**

定位调用点：
```bash
cd macos-app
grep -n "syncManagerWatchTargetsFromCurrentForm" Views/SettingsWatchPanel.swift Views/Overview/ManagerWatchControlCard.swift
```

在两处的按钮上加 `.disabled(model.form.filterMode == .managerSubscription)`，或加 `if model.form.filterMode == .preciseParams` 守卫。同时在按钮旁加说明（可选）：`.help("切换到精确参数模式后可用")`。

- [ ] **Step 6.2: 写 MultiGroupSnapshotTests**

测 `mergeAndSortPosts` 纯函数（static，无需 mock 网络）：

```swift
import XCTest
@testable import QiemanDashboard

final class MultiGroupSnapshotTests: XCTestCase {
    func testMergeDeduplicatesByPostId() {
        let posts: [[String: Any]] = [
            ["post_id": 100, "created_at": "2026-07-21"],
            ["post_id": 100, "created_at": "2026-07-21"],  // 重复
            ["post_id": 200, "created_at": "2026-07-20"],
        ]
        let merged = QiemanNativeClient.mergeAndSortPosts(posts)
        XCTAssertEqual(merged.count, 2)
    }

    func testSortByCreatedAtDescending() {
        let posts: [[String: Any]] = [
            ["post_id": 1, "created_at": "2026-07-20"],
            ["post_id": 2, "created_at": "2026-07-22"],
            ["post_id": 3, "created_at": "2026-07-21"],
        ]
        let merged = QiemanNativeClient.mergeAndSortPosts(posts)
        XCTAssertEqual(merged[0]["post_id"] as? Int, 2)  // 最新在前
        XCTAssertEqual(merged[2]["post_id"] as? Int, 1)
    }

    func testEmptyInputReturnsEmpty() {
        let merged = QiemanNativeClient.mergeAndSortPosts([])
        XCTAssertTrue(merged.isEmpty)
    }

    func testPostsWithoutIdAreKept() {
        let posts: [[String: Any]] = [
            ["created_at": "2026-07-20"],  // 无 post_id
            ["created_at": "2026-07-21"],
        ]
        let merged = QiemanNativeClient.mergeAndSortPosts(posts)
        XCTAssertEqual(merged.count, 2)  // 都保留
    }
}
```

注意：`mergeAndSortPosts` 是 `QiemanNativeClient` 的 static 方法。测试里直接 `QiemanNativeClient.mergeAndSortPosts(...)` 调用。`QiemanNativeClient` 是否需要标记为 `@testable import`？是的——用 `@testable import QiemanDashboard`。

- [ ] **Step 6.3: 全量验证**

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard/macos-app
swift build 2>&1 | tail -2
swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1
```
预期：编译 0 错误，293 + 4 = 297 测试全过。

```bash
# App 构建
APP_VERSION=3.5.0 bash ../scripts/build_macos_app.sh 2>&1 | tail -3
```

- [ ] **Step 6.4: 手工 smoke（可选）**

```bash
open dist/macos-app/QiemanDashboard.app
```
检查：
- 筛选面板顶部有「主理人订阅 / 精确参数」分段切换
- 默认是主理人订阅模式，显示 ManagerPicker（启动几秒后加载出主理人列表）
- 搜索框输入"ETF"能联想出 ETF拯救世界
- 勾选主理人后显示芯片，点刷新能抓发言
- 切到精确参数模式，显示原来的文本框

- [ ] **Step 6.5: Commit**

```bash
git add -A
git commit -m "feat: 同步到巡检按钮在订阅模式禁用 + 多小组抓取测试"
```

---

## 完成标准

- [ ] App 编译 0 错误
- [ ] 297 测试全过（293 现有 + 4 新增）
- [ ] ManagerWatch 零改动（巡检功能正常）
- [ ] 现有 CLI 零改动
- [ ] 手工 smoke：模式切换、多选、搜索、抓取都正常

## 回滚

纯新增性提交，整体回滚只需 `git revert <commit-range>`。
