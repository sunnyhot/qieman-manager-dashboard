import Foundation

enum ImportPreviewChangeKind: String, Codable, CaseIterable, Hashable {
    case added
    case updated
    case unchanged
    case duplicate
    case removed
    case blocked
}

struct ImportPreviewRow: Identifiable, Codable, Hashable {
    let id: String
    let kind: ImportPreviewChangeKind
    let title: String
    let detail: String
    let beforeSummary: String?
    let afterSummary: String?
}

struct ImportPreviewSession: Identifiable, Codable, Hashable {
    let id: UUID
    let target: PersonalDataImportTarget
    let mode: PersonalDataSaveMode
    let createdAt: String
    let rows: [ImportPreviewRow]

    init(
        id: UUID = UUID(),
        target: PersonalDataImportTarget,
        mode: PersonalDataSaveMode,
        createdAt: String = "",
        rows: [ImportPreviewRow]
    ) {
        self.id = id
        self.target = target
        self.mode = mode
        self.createdAt = createdAt
        self.rows = rows
    }

    var canConfirm: Bool {
        !rows.isEmpty && !rows.contains { $0.kind == .blocked }
    }

    func count(for kind: ImportPreviewChangeKind) -> Int {
        rows.filter { $0.kind == kind }.count
    }

    static func makeHoldings(
        imported: [UserPortfolioHolding],
        existing: [UserPortfolioHolding],
        mode: PersonalDataSaveMode,
        store: UserPortfolioStore,
        createdAt: String = ""
    ) -> ImportPreviewSession {
        make(
            target: .holdings,
            imported: imported,
            existing: existing,
            mode: mode,
            createdAt: createdAt,
            key: store.previewKey(for:),
            title: { $0.normalizedName ?? $0.normalizedFundCode },
            summary: { "代码 \($0.normalizedFundCode) · 份额 \(decimalText($0.units)) · 成本 \($0.costPrice.map(decimalText) ?? "-")" }
        )
    }

    static func makePendingTrades(
        imported: [PersonalPendingTrade],
        existing: [PersonalPendingTrade],
        mode: PersonalDataSaveMode,
        store: PendingTradesStore,
        createdAt: String = ""
    ) -> ImportPreviewSession {
        make(
            target: .pendingTrades,
            imported: imported,
            existing: existing,
            mode: mode,
            createdAt: createdAt,
            key: store.previewKey(for:),
            title: { $0.displayTitle },
            summary: { "\($0.occurredAt) · \($0.actionLabel) · \($0.amountText) · \($0.status)" }
        )
    }

    static func makeInvestmentPlans(
        imported: [PersonalInvestmentPlan],
        existing: [PersonalInvestmentPlan],
        mode: PersonalDataSaveMode,
        store: InvestmentPlansStore,
        createdAt: String = ""
    ) -> ImportPreviewSession {
        make(
            target: .investmentPlans,
            imported: imported,
            existing: existing,
            mode: mode,
            createdAt: createdAt,
            key: store.previewKey(for:),
            title: { $0.fundName.isEmpty ? ($0.fundCode ?? "定投计划") : $0.fundName },
            summary: { "\($0.planTypeLabel) · \($0.scheduleText) · \($0.amountText) · \($0.status)" }
        )
    }

    private static func make<T>(
        target: PersonalDataImportTarget,
        imported: [T],
        existing: [T],
        mode: PersonalDataSaveMode,
        createdAt: String,
        key: (T) -> String,
        title: (T) -> String,
        summary: (T) -> String
    ) -> ImportPreviewSession {
        guard !imported.isEmpty else {
            return ImportPreviewSession(
                target: target,
                mode: mode,
                createdAt: createdAt,
                rows: [
                    ImportPreviewRow(
                        id: "\(target.id)-blocked-empty",
                        kind: .blocked,
                        title: "没有可导入记录",
                        detail: "请先导入或粘贴有效草稿。",
                        beforeSummary: nil,
                        afterSummary: nil
                    )
                ]
            )
        }

        let existingByKey = Dictionary(existing.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
        let importedKeys = imported.map(key)
        var seenImportedKeys: Set<String> = []
        var rows: [ImportPreviewRow] = []

        for item in imported {
            let itemKey = key(item)
            let itemTitle = title(item)
            let after = summary(item)
            if seenImportedKeys.contains(itemKey) {
                rows.append(
                    ImportPreviewRow(
                        id: "\(target.id)-duplicate-\(itemKey)-\(rows.count)",
                        kind: .duplicate,
                        title: itemTitle,
                        detail: "导入草稿中存在重复记录，确认后按现有合并规则处理。",
                        beforeSummary: nil,
                        afterSummary: after
                    )
                )
                continue
            }
            seenImportedKeys.insert(itemKey)

            if let existingItem = existingByKey[itemKey] {
                let before = summary(existingItem)
                rows.append(
                    ImportPreviewRow(
                        id: "\(target.id)-\(itemKey)",
                        kind: before == after ? .unchanged : .updated,
                        title: itemTitle,
                        detail: before == after ? "本地记录无需变化" : "本地记录将更新",
                        beforeSummary: before,
                        afterSummary: after
                    )
                )
            } else {
                rows.append(
                    ImportPreviewRow(
                        id: "\(target.id)-\(itemKey)",
                        kind: .added,
                        title: itemTitle,
                        detail: "将新增到本地数据",
                        beforeSummary: nil,
                        afterSummary: after
                    )
                )
            }
        }

        if mode == .replace {
            let importedKeySet = Set(importedKeys)
            for item in existing where !importedKeySet.contains(key(item)) {
                rows.append(
                    ImportPreviewRow(
                        id: "\(target.id)-removed-\(key(item))",
                        kind: .removed,
                        title: title(item),
                        detail: "替换模式会移除这条本地记录",
                        beforeSummary: summary(item),
                        afterSummary: nil
                    )
                )
            }
        }

        return ImportPreviewSession(target: target, mode: mode, createdAt: createdAt, rows: rows)
    }
}

struct ImportUndoSnapshot: Codable, Hashable {
    let target: PersonalDataImportTarget
    let mode: PersonalDataSaveMode
    let createdAt: String
    let beforeHoldings: [UserPortfolioHolding]
    let beforePendingTrades: [PersonalPendingTrade]
    let beforeInvestmentPlans: [PersonalInvestmentPlan]
    let afterFingerprint: ImportDataFingerprint

    var restoreHoldings: [UserPortfolioHolding] { beforeHoldings }
    var restorePendingTrades: [PersonalPendingTrade] { beforePendingTrades }
    var restoreInvestmentPlans: [PersonalInvestmentPlan] { beforeInvestmentPlans }

    static func make(
        target: PersonalDataImportTarget,
        mode: PersonalDataSaveMode,
        createdAt: String,
        beforeHoldings: [UserPortfolioHolding],
        beforePendingTrades: [PersonalPendingTrade],
        beforeInvestmentPlans: [PersonalInvestmentPlan],
        afterHoldings: [UserPortfolioHolding],
        afterPendingTrades: [PersonalPendingTrade],
        afterInvestmentPlans: [PersonalInvestmentPlan]
    ) -> ImportUndoSnapshot {
        ImportUndoSnapshot(
            target: target,
            mode: mode,
            createdAt: createdAt,
            beforeHoldings: beforeHoldings,
            beforePendingTrades: beforePendingTrades,
            beforeInvestmentPlans: beforeInvestmentPlans,
            afterFingerprint: ImportDataFingerprint.make(
                holdings: afterHoldings,
                pendingTrades: afterPendingTrades,
                investmentPlans: afterInvestmentPlans
            )
        )
    }

    func isValid(
        currentHoldings: [UserPortfolioHolding],
        currentPendingTrades: [PersonalPendingTrade],
        currentInvestmentPlans: [PersonalInvestmentPlan]
    ) -> Bool {
        afterFingerprint == ImportDataFingerprint.make(
            holdings: currentHoldings,
            pendingTrades: currentPendingTrades,
            investmentPlans: currentInvestmentPlans
        )
    }
}

struct ImportDataFingerprint: Codable, Hashable {
    let holdings: String
    let pendingTrades: String
    let investmentPlans: String

    static func make(
        holdings: [UserPortfolioHolding],
        pendingTrades: [PersonalPendingTrade],
        investmentPlans: [PersonalInvestmentPlan]
    ) -> ImportDataFingerprint {
        ImportDataFingerprint(
            holdings: encodedString(holdings),
            pendingTrades: encodedString(pendingTrades),
            investmentPlans: encodedString(investmentPlans)
        )
    }

    private static func encodedString<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard
            let data = try? encoder.encode(value),
            let text = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return text
    }
}

struct ImportUndoSnapshotStore {
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder

    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func load(from fileURL: URL) throws -> ImportUndoSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(ImportUndoSnapshot.self, from: data)
    }

    func save(_ snapshot: ImportUndoSnapshot, to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    func delete(at fileURL: URL) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
