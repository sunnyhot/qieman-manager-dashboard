import Foundation

enum QiemanCommandLineError: LocalizedError {
    case usage(String)
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .usage(let message): return message
        case .invalidJSON: return "无法生成 JSON 输出。"
        }
    }
}

struct QiemanCommandArguments {
    let command: String
    private let values: [String: [String]]
    private let flags: Set<String>

    init(_ arguments: [String]) throws {
        guard let command = arguments.first, !command.hasPrefix("-") else {
            throw QiemanCommandLineError.usage(QiemanCommandLine.helpText)
        }
        self.command = command

        var parsedValues: [String: [String]] = [:]
        var parsedFlags: Set<String> = []
        var index = 1
        while index < arguments.count {
            let token = arguments[index]
            guard token.hasPrefix("--") else {
                throw QiemanCommandLineError.usage("无法识别参数：\(token)")
            }
            let key = String(token.dropFirst(2))
            if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
                parsedValues[key, default: []].append(arguments[index + 1])
                index += 2
            } else {
                parsedFlags.insert(key)
                index += 1
            }
        }
        values = parsedValues
        flags = parsedFlags
    }

    func string(_ key: String, default fallback: String = "") -> String {
        values[key]?.last ?? fallback
    }

    func strings(_ key: String) -> [String] {
        values[key] ?? []
    }

    func int(_ key: String, default fallback: Int) -> Int {
        Int(string(key)) ?? fallback
    }

    func bool(_ key: String) -> Bool {
        flags.contains(key)
    }
}

struct QiemanCommandLine {
    static let helpText = """
    qieman-cli — 且慢原生命令行工具（macOS）

    用法：qieman-cli <command> [options]

      auth-status          验证登录态
      following-posts      查询关注动态
      following-users      查询关注用户
      my-groups            查询已加入小组
      group-lookup         解析小组
      group-posts          查询公开小组动态
      space-items          查询个人空间动态
      public-items         查询公开主理人动态（原生小组源）
      post-comments        查询帖子评论
      platform-actions     查询平台调仓
      platform-holdings    查询平台持仓
      platform-timeline    查询标的调仓时间线
      platform-monthly     查询月度调仓汇总
      valuation            查询基金实时估值
      updates-watch        增量巡检调仓与动态
      signal-extract       从 JSON 文件提取交易关键词
      app-open             打开原生 macOS App

    通用登录参数：--cookie-file PATH 或环境变量 QIEMAN_COOKIE。
    所有数据命令默认输出 JSON；不输出 Cookie 原文。
    """

    private let arguments: QiemanCommandArguments
    private let environment: [String: String]

    init(arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        self.arguments = try QiemanCommandArguments(arguments)
        self.environment = environment
    }

    func run() async throws -> [String: Any] {
        switch arguments.command {
        case "help", "--help", "-h":
            return ["help": Self.helpText]
        case "version":
            return ["version": "1", "runtime": "swift", "platform": "macos"]
        case "auth-status":
            return await authStatus()
        case "following-posts":
            return try await snapshot(mode: .followingPosts)
        case "following-users":
            return try await snapshot(mode: .followingUsers)
        case "my-groups":
            return try await snapshot(mode: .myGroups)
        case "group-lookup":
            return try await groupLookup()
        case "group-posts":
            return try await snapshot(mode: .groupManager)
        case "space-items":
            return try await snapshot(mode: .spaceItems)
        case "public-items":
            return try await publicItems()
        case "post-comments":
            return try await comments()
        case "platform-actions":
            return try await platformActions()
        case "platform-holdings":
            return try await platformHoldings()
        case "platform-timeline":
            return try await platformTimeline()
        case "platform-monthly":
            return try await platformMonthly()
        case "valuation":
            return try await valuation()
        case "updates-watch":
            return try await updatesWatch()
        case "signal-extract":
            return try signalExtract()
        case "app-open":
            return try openApp()
        default:
            throw QiemanCommandLineError.usage("未知命令：\(arguments.command)\n\n\(Self.helpText)")
        }
    }

    static func JSONData(_ payload: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw QiemanCommandLineError.invalidJSON
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    private func authStatus() async -> [String: Any] {
        let payload = await nativeClient().validateAuth()
        return [
            "ok": payload.ok,
            "error": payload.ok ? "" : payload.message,
            "user_name": payload.userName,
            "broker_user_id": payload.brokerUserId,
            "user_label": payload.userLabel,
            "user_avatar_url": "",
        ]
    }

    private func snapshot(mode: QueryMode) async throws -> [String: Any] {
        let payload = try await fetchSnapshot(mode: mode)
        let limit = max(1, arguments.int("limit", default: 100))
        let includeContent = arguments.bool("include-content")
        let records = payload.records.prefix(limit).map { recordRow($0, includeContent: includeContent) }
        var result: [String: Any] = ["count": records.count, "items": records]
        if let group = payload.group {
            result["group"] = groupRow(group)
        }
        return result
    }

    private func publicItems() async throws -> [String: Any] {
        let payload = try await fetchSnapshot(mode: .groupManager, keywordOverride: arguments.string("query"))
        let limit = max(1, arguments.int("preview", default: arguments.int("limit", default: 40)))
        let rows = payload.records.prefix(limit).map { record -> [String: Any] in
            [
                "query": arguments.string("query"),
                "title": record.title ?? record.intro ?? "",
                "author": record.userName ?? record.managerName ?? "",
                "publish_date": record.createdAt ?? "",
                "url": record.detailUrl ?? "",
                "source": "qieman-native-group",
                "snippet": record.intro ?? record.contentText ?? "",
                "content": arguments.bool("include-content") ? (record.contentText ?? "") : "",
            ]
        }
        return ["count": rows.count, "items": rows]
    }

    private func groupLookup() async throws -> [String: Any] {
        let payload = try await fetchSnapshot(mode: .groupManager)
        guard let group = payload.group, let groupID = group.groupId else {
            throw QiemanCommandLineError.usage("无法解析 groupId")
        }
        let source: String
        if !arguments.string("group-id").isEmpty { source = "group-id" }
        else if !arguments.string("group-url").isEmpty { source = "group-url" }
        else if !arguments.string("manager-name").isEmpty { source = "manager-name" }
        else { source = "prod-code" }
        var result: [String: Any] = ["group_id": groupID, "source": source]
        if arguments.bool("with-group-info") { result["group"] = groupRow(group) }
        return result
    }

    private func comments() async throws -> [String: Any] {
        let postID = arguments.int("post-id", default: 0)
        guard postID > 0 else { throw QiemanCommandLineError.usage("请提供 --post-id") }
        let payload = try await nativeClient().fetchComments(
            postID: postID,
            sortType: arguments.string("sort-type", default: "hot"),
            pageNum: max(1, arguments.int("page-num", default: 1)),
            pageSize: max(1, arguments.int("page-size", default: 10)),
            managerBrokerUserID: arguments.string("manager-broker-user-id")
        )
        return [
            "post_id": payload.postId,
            "page_num": payload.pageNum,
            "page_size": payload.pageSize,
            "sort_type": payload.sortType,
            "has_more": payload.hasMore,
            "comments": payload.comments.map(commentRow),
        ]
    }

    private func platformActions() async throws -> [String: Any] {
        let prodCode = arguments.string("prod-code", default: "LONG_WIN")
        let payload = try await QiemanPlatformNativeClient().fetchPlatformPayload(prodCode: prodCode)
        let rows = filteredActions(payload.actions ?? []).prefix(max(1, arguments.int("limit", default: 20))).map(actionRow)
        return [
            "prod_code": prodCode,
            "side": arguments.string("side", default: "all"),
            "since": arguments.string("since"),
            "until": arguments.string("until"),
            "count": rows.count,
            "items": Array(rows),
        ]
    }

    private func platformHoldings() async throws -> [String: Any] {
        let prodCode = arguments.string("prod-code", default: "LONG_WIN")
        let payload = try await QiemanPlatformNativeClient().fetchPlatformPayload(prodCode: prodCode)
        let requestedCode = arguments.string("fund-code")
        let minUnits = max(0, arguments.int("min-units", default: 1))
        let limit = max(1, arguments.int("limit", default: 100))
        let items = (payload.holdings?.items ?? []).filter {
            ($0.currentUnits ?? 0) >= minUnits && (requestedCode.isEmpty || $0.fundCode == requestedCode)
        }.prefix(limit).map(holdingRow)
        return [
            "prod_code": prodCode,
            "asset_count": payload.holdings?.assetCount ?? 0,
            "total_units": payload.holdings?.totalUnits ?? 0,
            "pricing_summary": [:] as [String: Any],
            "count": items.count,
            "items": Array(items),
        ]
    }

    private func platformTimeline() async throws -> [String: Any] {
        let prodCode = arguments.string("prod-code", default: "LONG_WIN")
        let payload = try await QiemanPlatformNativeClient().fetchPlatformPayload(prodCode: prodCode)
        let actions = filteredActions(payload.actions ?? [])
        let assetFilter = arguments.string("asset").lowercased()
        let perAssetLimit = max(1, arguments.int("limit-entries", default: 10))
        let assetLimit = max(1, arguments.int("limit-assets", default: 20))
        let groups = Dictionary(grouping: actions) { $0.fundName ?? $0.fundCode ?? "未知标的" }
        let rows = groups.map { label, entries -> [String: Any] in
            let sorted = entries.sorted { actionDate($0) > actionDate($1) }
            return [
                "label": label,
                "event_count": entries.count,
                "buy_count": entries.filter { normalizedSide($0) == "buy" }.count,
                "sell_count": entries.filter { normalizedSide($0) == "sell" }.count,
                "latest_time": sorted.first.map(actionDate) ?? "",
                "entries": sorted.prefix(perAssetLimit).map(actionRow),
            ]
        }.filter { assetFilter.isEmpty || String(describing: $0["label"] ?? "").lowercased().contains(assetFilter) }
         .sorted { String(describing: $0["latest_time"] ?? "") > String(describing: $1["latest_time"] ?? "") }
        return [
            "prod_code": prodCode,
            "side": arguments.string("side", default: "all"),
            "since": arguments.string("since"),
            "until": arguments.string("until"),
            "count": min(rows.count, assetLimit),
            "items": Array(rows.prefix(assetLimit)),
        ]
    }

    private func platformMonthly() async throws -> [String: Any] {
        let prodCode = arguments.string("prod-code", default: "LONG_WIN")
        let payload = try await QiemanPlatformNativeClient().fetchPlatformPayload(prodCode: prodCode)
        let actions = filteredActions(payload.actions ?? [])
        let groups = Dictionary(grouping: actions) { String(actionDate($0).prefix(7)) }
        let monthLimit = max(1, arguments.int("months", default: 12))
        let items = groups.keys.sorted(by: >).prefix(monthLimit).map { month -> [String: Any] in
            let rows = groups[month] ?? []
            let days = Set(rows.map { String(actionDate($0).prefix(10)) })
            return [
                "month": month,
                "total_count": rows.count,
                "buy_count": rows.filter { normalizedSide($0) == "buy" }.count,
                "sell_count": rows.filter { normalizedSide($0) == "sell" }.count,
                "active_day_count": days.count,
                "trades_per_active_day": days.isEmpty ? 0 : Double(rows.count) / Double(days.count),
            ]
        }
        let buyCount = actions.filter { normalizedSide($0) == "buy" }.count
        let sellCount = actions.filter { normalizedSide($0) == "sell" }.count
        let monthCount = items.count
        return [
            "prod_code": prodCode,
            "side": arguments.string("side", default: "all"),
            "since": arguments.string("since"),
            "until": arguments.string("until"),
            "months": monthLimit,
            "summary": [
                "month_count": monthCount,
                "total_count": actions.count,
                "buy_count": buyCount,
                "sell_count": sellCount,
                "avg_total_per_month": monthCount == 0 ? 0 : Double(actions.count) / Double(monthCount),
                "avg_buy_per_month": monthCount == 0 ? 0 : Double(buyCount) / Double(monthCount),
                "avg_sell_per_month": monthCount == 0 ? 0 : Double(sellCount) / Double(monthCount),
            ],
            "items": items,
        ]
    }

    private func valuation() async throws -> [String: Any] {
        guard arguments.string("at-date").isEmpty else {
            throw QiemanCommandLineError.usage("--at-date 历史日期估值已移除；valuation 仅返回当前实时估值或官方净值。")
        }
        var codes = arguments.strings("fund-code")
        codes += arguments.string("fund-codes").split(separator: ",").map(String.init)
        codes = Array(Set(codes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        guard !codes.isEmpty else { throw QiemanCommandLineError.usage("请提供 --fund-code 或 --fund-codes") }
        let holdings = codes.map { UserPortfolioHolding(fundCode: $0, units: 1, costPrice: nil, displayName: nil) }
        let snapshot = try await QiemanPlatformNativeClient().fetchUserPortfolioSnapshot(holdings: holdings, forceQuoteRefresh: true)
        let rows = snapshot.rows.map { row -> [String: Any] in
            [
                "fund_code": row.holding.normalizedFundCode,
                "fund_name": row.fundName,
                "current_valuation": JSONValue(row.currentPrice ?? row.officialNav),
                "current_source": row.priceSource ?? "未知",
                "current_time": row.priceTime ?? row.officialNavDate ?? "",
                "valuation_at_date": NSNull(),
                "valuation_at_actual_date": "",
                "change_pct": JSONValue(row.estimateChangePct),
            ]
        }
        return ["count": rows.count, "items": rows]
    }

    private func updatesWatch() async throws -> [String: Any] {
        let prodCode = arguments.string("prod-code", default: "LONG_WIN")
        let managerName = arguments.string("manager-name", default: "ETF拯救世界")
        let forumMode = arguments.string("forum-mode", default: "auto")
        guard ["auto", "following", "public"].contains(forumMode) else {
            throw QiemanCommandLineError.usage("--forum-mode 仅支持 auto、following 或 public")
        }
        async let platformTask = QiemanPlatformNativeClient().fetchPlatformPayload(prodCode: prodCode)
        let forumResult = try await watchForumSnapshot(mode: forumMode, managerName: managerName)
        let platform = try await platformTask
        let forum = forumResult.payload
        let trades = Array((platform.actions ?? []).prefix(max(1, arguments.int("max-trades", default: 120)))).map(actionRow)
        let posts = Array(forum.records.prefix(max(1, arguments.int("max-posts", default: 120)))).map { recordRow($0, includeContent: false) }
        let stateURL = watchStateURL(prodCode: prodCode, managerName: managerName)
        let previous = loadJSONObject(at: stateURL)
        let seenTrades = Set(previous["seen_trade_ids"] as? [String] ?? [])
        let seenPosts = Set(previous["seen_post_ids"] as? [String] ?? [])
        let tradeIDs = trades.map(tradeID)
        let postIDs = posts.map(postID)
        let firstRun = previous.isEmpty
        let emitInitial = arguments.bool("emit-initial")
        let preview = max(1, arguments.int("preview", default: 8))
        let newTrades = firstRun && !emitInitial ? [] : Array(trades.filter { !seenTrades.contains(tradeID($0)) }.prefix(preview))
        let newPosts = firstRun && !emitInitial ? [] : Array(posts.filter { !seenPosts.contains(postID($0)) }.prefix(preview))
        let checkedAt = ISO8601DateFormatter().string(from: Date())
        try saveJSONObject([
            "updated_at": checkedAt,
            "forum_source": forumResult.source,
            "seen_trade_ids": Array(tradeIDs.prefix(2000)),
            "seen_post_ids": Array(postIDs.prefix(2000)),
            "prod_code": prodCode,
            "manager_name": managerName,
        ], at: stateURL)
        return [
            "checked_at": checkedAt,
            "state_file": stateURL.path,
            "forum_source": forumResult.source,
            "forum_note": forumResult.note,
            "initialized": firstRun && !emitInitial,
            "emit_initial": emitInitial,
            "has_updates": !newTrades.isEmpty || !newPosts.isEmpty,
            "trade_total": trades.count,
            "post_total": posts.count,
            "new_trade_count": newTrades.count,
            "new_post_count": newPosts.count,
            "new_trades": newTrades,
            "new_posts": newPosts,
        ]
    }

    private func signalExtract() throws -> [String: Any] {
        let path = arguments.string("json-path")
        guard !path.isEmpty else { throw QiemanCommandLineError.usage("请提供 --json-path") }
        let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let rawItems: [[String: Any]]
        if let payload = object as? [String: Any], let items = payload["posts"] as? [[String: Any]] { rawItems = items }
        else if let items = object as? [[String: Any]] { rawItems = items }
        else { throw QiemanCommandLineError.usage("JSON 需要是数组或包含 posts 数组") }
        let limit = max(1, arguments.int("limit-items", default: 20))
        let keywords: [(String, [String])] = [
            ("buy", ["买入", "加仓", "申购", "定投", "发车"]),
            ("sell", ["卖出", "减仓", "赎回", "止盈"]),
            ("hold", ["持有", "观望", "不动"]),
        ]
        var counts = ["buy": 0, "sell": 0, "hold": 0]
        var items: [[String: Any]] = []
        for row in rawItems {
            let text = [row["title"], row["intro"], row["content_text"], row["content"], row["snippet"]]
                .compactMap { $0 as? String }.joined(separator: " ")
            for (action, words) in keywords where words.contains(where: text.contains) {
                counts[action, default: 0] += 1
                items.append([
                    "action": action,
                    "title": row["title"] as? String ?? row["intro"] as? String ?? "",
                    "created_at": row["created_at"] as? String ?? row["publish_date"] as? String ?? "",
                    "detail_url": row["detail_url"] as? String ?? row["url"] as? String ?? "",
                ])
                break
            }
        }
        let limited = Array(items.prefix(limit))
        return [
            "source": url.path,
            "record_count": rawItems.count,
            "signal_count": items.count,
            "event_count": items.count,
            "counts": counts,
            "top_actions": counts.map { ["action": $0.key, "count": $0.value] }.sorted { ($0["count"] as? Int ?? 0) > ($1["count"] as? Int ?? 0) },
            "top_assets": [] as [[String: Any]],
            "latest": limited.first ?? [:],
            "items": limited,
            "timeline": [] as [[String: Any]],
        ]
    }

    private func openApp() throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        let appPath = arguments.string("app-path")
        process.arguments = appPath.isEmpty ? ["-a", "且慢主理人"] : [appPath]
        try process.run()
        process.waitUntilExit()
        return ["opened": process.terminationStatus == 0, "app_path": appPath]
    }

    private func nativeClient() -> QiemanNativeClient {
        QiemanNativeClient(cookieFileURL: cookieFileURL(), rawCookie: rawCookie())
    }

    private func rawCookie() -> String? {
        let direct = arguments.string("cookie")
        if !direct.isEmpty { return direct }
        let envName = arguments.string("cookie-env", default: "QIEMAN_COOKIE")
        return environment[envName]
    }

    private func cookieFileURL() -> URL? {
        let explicit = arguments.string("cookie-file")
        if !explicit.isEmpty { return URL(fileURLWithPath: NSString(string: explicit).expandingTildeInPath) }
        if let dataDirectory = environment["QIEMAN_DATA_DIR"], !dataDirectory.isEmpty {
            return URL(fileURLWithPath: dataDirectory).appendingPathComponent("qieman.cookie")
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return appSupport?.appendingPathComponent("QiemanDashboard/qieman.cookie")
    }

    private func fetchSnapshot(
        mode: QueryMode,
        keywordOverride: String? = nil,
        userNameOverride: String? = nil
    ) async throws -> SnapshotPayload {
        var form = QueryFormState()
        form.mode = mode
        form.prodCode = arguments.string("prod-code", default: "LONG_WIN")
        let managerName = arguments.string("manager-name")
        form.managerName = managerName.isEmpty ? arguments.string("author") : managerName
        form.groupURL = arguments.string("group-url")
        form.groupID = arguments.string("group-id")
        form.userName = userNameOverride ?? arguments.string("user-name")
        form.brokerUserID = arguments.string("broker-user-id")
        form.spaceUserID = arguments.string("space-user-id")
        form.keyword = keywordOverride ?? arguments.string("keyword")
        form.since = arguments.string("since")
        form.until = arguments.string("until")
        form.pages = String(max(1, arguments.int("pages", default: 5)))
        form.pageSize = String(max(1, arguments.int("page-size", default: 20)))
        return try await nativeClient().fetchSnapshot(form: form, persist: false, outputDirectory: nil)
    }

    private func watchForumSnapshot(
        mode: String,
        managerName: String
    ) async throws -> (payload: SnapshotPayload, source: String, note: String) {
        if mode == "public" {
            return (
                try await fetchSnapshot(mode: .groupManager, userNameOverride: nil),
                "public-group",
                ""
            )
        }
        do {
            return (
                try await fetchSnapshot(mode: .followingPosts, userNameOverride: managerName),
                "following-posts",
                ""
            )
        } catch {
            guard mode == "auto" else { throw error }
            let publicPayload = try await fetchSnapshot(mode: .groupManager, userNameOverride: nil)
            return (
                publicPayload,
                "public-group",
                "关注流不可用，已回退到且慢公开小组源。"
            )
        }
    }

    private func JSONValue(_ value: Double?) -> Any {
        if let value { return value }
        return NSNull()
    }

    private func filteredActions(_ actions: [PlatformActionPayload]) -> [PlatformActionPayload] {
        let side = arguments.string("side", default: "all")
        let since = arguments.string("since")
        let until = arguments.string("until")
        return actions.filter { action in
            let currentSide = normalizedSide(action)
            let date = actionDate(action)
            if side != "all" && side != currentSide { return false }
            if !since.isEmpty && date < since { return false }
            if !until.isEmpty && date > until + "T99" { return false }
            return true
        }
    }

    private func actionDate(_ action: PlatformActionPayload) -> String {
        action.txnDate ?? action.createdAt ?? ""
    }

    private func normalizedSide(_ action: PlatformActionPayload) -> String {
        let raw = (action.side ?? action.action ?? "").lowercased()
        if raw.contains("buy") || raw.contains("买") || raw.contains("加") { return "buy" }
        if raw.contains("sell") || raw.contains("卖") || raw.contains("减") { return "sell" }
        return raw
    }

    private func recordRow(_ record: SnapshotRecordPayload, includeContent: Bool) -> [String: Any] {
        var row: [String: Any] = [
            "post_id": record.postId ?? 0,
            "group_id": record.groupId ?? 0,
            "group_name": record.groupName ?? "",
            "broker_user_id": record.brokerUserId ?? "",
            "space_user_id": record.spaceUserId ?? "",
            "user_name": record.userName ?? "",
            "user_label": record.userLabel ?? "",
            "created_at": record.createdAt ?? "",
            "title": record.title ?? record.intro ?? "",
            "like_count": record.likeCount ?? 0,
            "comment_count": record.commentCount ?? 0,
            "detail_url": record.detailUrl ?? "",
        ]
        if includeContent { row["content_text"] = record.contentText ?? "" }
        return row
    }

    private func groupRow(_ group: GroupPayload) -> [String: Any] {
        [
            "group_id": group.groupId ?? 0,
            "group_name": group.groupName ?? "",
            "manager_name": group.managerName ?? "",
            "manager_broker_user_id": group.managerBrokerUserId ?? "",
        ]
    }

    private func commentRow(_ comment: CommentPayload) -> [String: Any] {
        [
            "id": comment.id,
            "post_id": comment.postId ?? 0,
            "user_name": comment.userName ?? "",
            "broker_user_id": comment.brokerUserId ?? "",
            "content": comment.content ?? "",
            "created_at": comment.createdAt ?? "",
            "like_count": comment.likeCount ?? 0,
            "reply_count": comment.replyCount ?? 0,
            "ip_location": comment.ipLocation ?? "",
            "to_user_name": comment.toUserName ?? "",
            "children": comment.children.map(commentRow),
        ]
    }

    private func actionRow(_ action: PlatformActionPayload) -> [String: Any] {
        [
            "uid": action.actionKey ?? action.id,
            "date": actionDate(action),
            "adjustment_id": action.adjustmentId ?? 0,
            "action": action.action ?? "",
            "action_title": action.actionTitle ?? action.displayTitle,
            "side": normalizedSide(action),
            "fund_code": action.fundCode ?? "",
            "fund_name": action.fundName ?? "",
            "trade_unit": action.tradeUnit ?? 0,
            "trade_valuation": action.tradeValuation ?? 0,
            "trade_valuation_date": action.tradeValuationDate ?? "",
            "current_valuation": action.currentValuation ?? 0,
            "current_valuation_source": action.currentValuationSource ?? "",
            "current_valuation_time": action.currentValuationTime ?? "",
            "valuation_change_pct": action.valuationChangePct ?? 0,
            "article_url": action.articleUrl ?? "",
        ]
    }

    private func holdingRow(_ holding: HoldingItemPayload) -> [String: Any] {
        [
            "label": holding.label ?? holding.fundName ?? "",
            "fund_name": holding.fundName ?? "",
            "fund_code": holding.fundCode ?? "",
            "category": holding.largeClass ?? "未分类",
            "current_units": holding.currentUnits ?? 0,
            "avg_cost": holding.avgCost ?? 0,
            "current_price": holding.currentPrice ?? 0,
            "price_source_label": holding.priceSourceLabel ?? holding.priceSource ?? "",
            "price_time": holding.priceTime ?? "",
            "position_value": holding.positionValue ?? holding.estimatedValue ?? 0,
            "profit_amount": holding.profitAmount ?? 0,
            "profit_ratio": holding.profitRatio ?? holding.profitPct ?? 0,
            "latest_action_title": holding.latestActionTitle ?? holding.latestAction ?? "",
            "latest_time": holding.latestTime ?? "",
        ]
    }

    private func watchStateURL(prodCode: String, managerName: String) -> URL {
        let explicit = arguments.string("state-file")
        if !explicit.isEmpty { return URL(fileURLWithPath: NSString(string: explicit).expandingTildeInPath) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("QiemanDashboard/output", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let slug = (prodCode + "-" + managerName).replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: "-", options: .regularExpression)
        return base.appendingPathComponent("watch-state-\(slug).json")
    }

    private func loadJSONObject(at url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    private func saveJSONObject(_ object: [String: Any], at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.JSONData(object).write(to: url, options: .atomic)
    }

    private func tradeID(_ row: [String: Any]) -> String {
        row["uid"] as? String ?? ["adjustment_id", "side", "fund_code", "date", "trade_unit"]
            .map { String(describing: row[$0] ?? "") }.joined(separator: "|")
    }

    private func postID(_ row: [String: Any]) -> String {
        let value = row["post_id"] as? Int ?? 0
        if value > 0 { return "post:\(value)" }
        return "url:\(row["detail_url"] as? String ?? "")"
    }
}
