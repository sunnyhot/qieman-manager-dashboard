import Foundation

// MARK: - alfa 投顾组合管理

extension AppModel {

    var alfaPortfoliosFileURL: URL? {
        dataDirectoryURL?.appendingPathComponent("alfa-portfolios.json", isDirectory: false)
    }

    /// 从磁盘加载已添加的投顾组合列表（首次落盘默认预置晓磊）。
    func loadAlfaPortfolios() {
        guard let url = alfaPortfoliosFileURL else { return }
        let loaded = alfaPortfolioStore.load(from: url)
        alfaPortfolios = loaded
        if selectedAlfaPoCode == nil {
            selectedAlfaPoCode = loaded.first?.poCode
        }
        // 首次运行：落盘默认组合
        if !FileManager.default.fileExists(atPath: url.path) {
            try? alfaPortfolioStore.save(loaded, to: url)
        }
    }

    /// 拉取当前选中组合的调仓数据。
    func fetchAlfaPayload(poCode: String) async {
        guard !isLoadingAlfa else { return }
        isLoadingAlfa = true
        alfaError = nil
        do {
            alfaPayload = try await alfaClient.fetchAlfaPayload(poCode: poCode)
            selectedAlfaPoCode = poCode
        } catch {
            alfaError = error.localizedDescription
        }
        isLoadingAlfa = false
    }

    /// 刷新当前选中的投顾组合调仓。
    func refreshAlfaPayload() async {
        guard let poCode = selectedAlfaPoCode else { return }
        await fetchAlfaPayload(poCode: poCode)
    }

    /// 拉取可选组合目录（hand-picked），供"添加组合"使用。
    func loadAlfaCatalog() async {
        guard !isLoadingAlfaCatalog else { return }
        isLoadingAlfaCatalog = true
        do {
            alfaCatalog = try await alfaClient.fetchPortfolioCatalog()
        } catch {
            // 目录加载失败不阻塞主流程，保持空列表
            alfaCatalog = []
        }
        isLoadingAlfaCatalog = false
    }

    /// 添加投顾组合到本地列表并落盘。
    func addAlfaPortfolio(_ item: AlfaPortfolioCatalogItem) {
        guard !alfaPortfolios.contains(where: { $0.poCode == item.poCode }) else { return }
        alfaPortfolios.append(item)
        persistAlfaPortfolios()
        if selectedAlfaPoCode == nil {
            selectedAlfaPoCode = item.poCode
        }
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
        persistAlfaPortfolios()
        if selectedAlfaPoCode == poCode {
            selectedAlfaPoCode = alfaPortfolios.first?.poCode
        }
    }

    /// 当前选中的投顾组合项。
    var selectedAlfaPortfolio: AlfaPortfolioCatalogItem? {
        guard let poCode = selectedAlfaPoCode else { return nil }
        return alfaPortfolios.first { $0.poCode == poCode }
    }

    private func persistAlfaPortfolios() {
        guard let url = alfaPortfoliosFileURL else { return }
        try? alfaPortfolioStore.save(alfaPortfolios, to: url)
    }
}
