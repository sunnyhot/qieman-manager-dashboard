import Foundation

// MARK: - alfa 投顾组合管理

extension AppModel {

    var alfaPortfoliosFileURL: URL? {
        dataDirectoryURL?.appendingPathComponent("alfa-portfolios.json", isDirectory: false)
    }

    /// 所有组合 poCode（用于全选/默认选中）。
    var allAlfaPoCodes: Set<String> {
        Set(alfaPortfolios.map(\.poCode))
    }

    /// 当前筛选生效的调仓列表（按 selectedAlfaPoCodes 过滤 prodCode）。
    /// selectedAlfaPoCodes 为空时视为全选（避免空列表）。
    var filteredAlfaActions: [PlatformActionPayload] {
        let actions = alfaPayload?.actions ?? []
        guard !selectedAlfaPoCodes.isEmpty else { return actions }
        let codes = selectedAlfaPoCodes
        return actions.filter { codes.contains($0.sourcePoCode ?? "") }
    }

    /// 从磁盘加载已添加的投顾组合列表（首次落盘默认预置晓磊）。
    func loadAlfaPortfolios() {
        guard let url = alfaPortfoliosFileURL else { return }
        let loaded = alfaPortfolioStore.load(from: url)
        alfaPortfolios = loaded
        // 默认全选
        selectedAlfaPoCodes = Set(loaded.map(\.poCode))
        // 首次运行：落盘默认组合
        if !FileManager.default.fileExists(atPath: url.path) {
            try? alfaPortfolioStore.save(loaded, to: url)
        }
    }

    /// 并发抓取所有已添加组合的调仓，合并成一个汇总列表（按 txnDate 降序）。
    func fetchAllAlfaPayloads() async {
        let codes = alfaPortfolios.map(\.poCode)
        guard !codes.isEmpty else {
            alfaPayload = nil
            return
        }
        guard !isLoadingAlfa else { return }
        isLoadingAlfa = true
        alfaError = nil

        var payloads: [PlatformPayload] = []
        var firstError: String?
        await withTaskGroup(of: PlatformPayload?.self) { group in
            for code in codes {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    do {
                        return try await self.alfaClient.fetchAlfaPayload(poCode: code)
                    } catch {
                        return nil
                    }
                }
            }
            for await result in group {
                if let p = result {
                    payloads.append(p)
                }
            }
        }

        if payloads.isEmpty {
            // 全部失败时尝试单独拉一个拿错误信息
            if let first = codes.first {
                do {
                    let single = try await alfaClient.fetchAlfaPayload(poCode: first)
                    payloads.append(single)
                } catch {
                    firstError = error.localizedDescription
                }
            }
        }

        alfaPayload = Self.mergeAlfaPayloads(payloads)
        if let firstError {
            alfaError = firstError
        }
        isLoadingAlfa = false
    }

    /// 合并多个组合的 payload 为一个汇总 payload。
    private static func mergeAlfaPayloads(_ payloads: [PlatformPayload]) -> PlatformPayload {
        var allActions: [PlatformActionPayload] = []
        var adjustmentCount = 0
        for p in payloads {
            allActions.append(contentsOf: p.actions ?? [])
            adjustmentCount += p.adjustmentCount ?? 0
        }
        allActions.sort { ($0.txnDate ?? "") > ($1.txnDate ?? "") }

        let buyCount = allActions.filter { $0.side == "buy" }.count
        let sellCount = allActions.filter { $0.side == "sell" }.count

        return PlatformPayload(
            supported: true,
            prodCode: "aggregate",
            count: allActions.count,
            buyCount: buyCount,
            sellCount: sellCount,
            adjustmentCount: adjustmentCount,
            latest: allActions.first,
            actions: allActions,
            holdings: nil,
            timeline: nil,
            error: nil
        )
    }

    /// 刷新投顾调仓（抓取所有已添加组合）。
    func refreshAlfaPayload() async {
        await fetchAllAlfaPayloads()
    }

    /// 拉取可选组合目录（hand-picked），供"添加组合"使用。
    func loadAlfaCatalog() async {
        guard !isLoadingAlfaCatalog else { return }
        isLoadingAlfaCatalog = true
        do {
            alfaCatalog = try await alfaClient.fetchPortfolioCatalog()
        } catch {
            alfaCatalog = []
        }
        isLoadingAlfaCatalog = false
    }

    /// 切换某组合的筛选选中状态。
    func toggleAlfaPoCode(_ poCode: String) {
        if selectedAlfaPoCodes.contains(poCode) {
            selectedAlfaPoCodes.remove(poCode)
        } else {
            selectedAlfaPoCodes.insert(poCode)
        }
    }

    /// 全选 / 全不选切换。
    func toggleAllAlfaPoCodes() {
        if selectedAlfaPoCodes.count == allAlfaPoCodes.count {
            selectedAlfaPoCodes = []
        } else {
            selectedAlfaPoCodes = allAlfaPoCodes
        }
    }

    /// 添加投顾组合到本地列表并落盘（新增的默认选中）。
    func addAlfaPortfolio(_ item: AlfaPortfolioCatalogItem) {
        guard !alfaPortfolios.contains(where: { $0.poCode == item.poCode }) else { return }
        alfaPortfolios.append(item)
        selectedAlfaPoCodes.insert(item.poCode)
        persistAlfaPortfolios()
    }

    /// 通过组合码添加（校验存在性并拉取名称），用于 catalog 之外的手动添加。
    func addAlfaPortfolioByCode(_ poCode: String) async -> Bool {
        let trimmed = poCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !alfaPortfolios.contains(where: { $0.poCode == trimmed }) else {
            return false
        }
        do {
            let name = try await alfaClient.fetchPortfolioName(poCode: trimmed) ?? trimmed
            addAlfaPortfolio(
                AlfaPortfolioCatalogItem(poCode: trimmed, name: name, author: "", category: "")
            )
            return true
        } catch {
            return false
        }
    }

    /// 移除投顾组合。
    func removeAlfaPortfolio(_ poCode: String) {
        alfaPortfolios.removeAll { $0.poCode == poCode }
        selectedAlfaPoCodes.remove(poCode)
        persistAlfaPortfolios()
    }

    /// 组合名映射，便于列表行展示来源。
    func alfaPortfolioName(for poCode: String?) -> String? {
        guard let poCode else { return nil }
        return alfaPortfolios.first { $0.poCode == poCode }?.name
    }

    private func persistAlfaPortfolios() {
        guard let url = alfaPortfoliosFileURL else { return }
        try? alfaPortfolioStore.save(alfaPortfolios, to: url)
    }
}
