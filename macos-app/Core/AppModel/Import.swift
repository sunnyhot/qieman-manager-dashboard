import Foundation

// MARK: - Draft Routing & Import

extension AppModel {
    func draft(for target: PersonalDataImportTarget) -> String {
        switch target {
        case .holdings:
            return portfolioDraft
        case .pendingTrades:
            return pendingTradesDraft
        case .investmentPlans:
            return investmentPlansDraft
        }
    }

    func updateDraft(_ value: String, for target: PersonalDataImportTarget) {
        switch target {
        case .holdings:
            portfolioDraft = value
        case .pendingTrades:
            pendingTradesDraft = value
        case .investmentPlans:
            investmentPlansDraft = value
        }
    }

    func saveDraft(for target: PersonalDataImportTarget, mode: PersonalDataSaveMode = .merge) {
        switch target {
        case .holdings:
            savePortfolioFromDraft(mode: mode)
        case .pendingTrades:
            savePendingTradesFromDraft(mode: mode)
        case .investmentPlans:
            saveInvestmentPlansFromDraft(mode: mode)
        }
    }

    func reloadDraftTargetFromDisk(_ target: PersonalDataImportTarget) {
        switch target {
        case .holdings:
            reloadPortfolioFromDisk()
        case .pendingTrades:
            reloadPendingTradesFromDisk()
        case .investmentPlans:
            reloadInvestmentPlansFromDisk()
        }
    }

    func hasImportedData(for target: PersonalDataImportTarget) -> Bool {
        switch target {
        case .holdings:
            return hasAnyPortfolioRecords
        case .pendingTrades:
            return hasPendingTrades
        case .investmentPlans:
            return hasInvestmentPlans
        }
    }

    func importExternalFile(at fileURL: URL, source: PersonalDataImportSource, target: PersonalDataImportTarget) async {
        isProcessingImport = true
        errorMessage = ""
        defer { isProcessingImport = false }

        let hasAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            _ = try serverController.prepareEnvironment()
            guard let projectDirectory = serverController.projectDirectory else {
                throw LocalServerError.projectMissing
            }

            let preparedInputURL: URL
            if source == .image {
                let recognizedText = try await importRecognizer.recognizeText(from: fileURL)
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("qieman-image-ocr-\(UUID().uuidString).txt")
                try recognizedText.write(to: tempURL, atomically: true, encoding: .utf8)
                preparedInputURL = tempURL
            } else {
                preparedInputURL = fileURL
            }

            let draft = try runPrepareImportScript(
                projectDirectory: projectDirectory,
                target: target,
                source: source,
                inputURL: preparedInputURL
            )
            updateDraft(draft, for: target)
            noticeMessage = source == .image ? "图片已识别到草稿区，请核对后保存。" : "表格已导入草稿区，请核对后保存。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func normalizedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func shouldUsePortfolioSummaryImport(for text: String) -> Bool {
        text
            .split(whereSeparator: \.isNewline)
            .contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.isEmpty && !trimmed.hasPrefix("#") && trimmed.contains("|")
            }
    }

    func importedPortfolioHoldings(from text: String) throws -> [UserPortfolioHolding] {
        if shouldUsePortfolioSummaryImport(for: text) {
            let outputURL = temporaryJSONURL(prefix: "qieman-holdings-import")
            defer { try? FileManager.default.removeItem(at: outputURL) }
            try runPortfolioSummaryImport(text: text, outputURL: outputURL)
            return try portfolioStore.load(from: outputURL)
        }
        return try portfolioStore.parseDraft(text)
    }

    func importedPendingTrades(from text: String) throws -> [PersonalPendingTrade] {
        let outputURL = temporaryJSONURL(prefix: "qieman-pending-import")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        try runTextImportScript(
            scriptRelativePath: "scripts/import_alipay_pending_trades.py",
            text: text,
            additionalArguments: ["--output", outputURL.path]
        )
        return try pendingTradesStore.load(from: outputURL)
    }

    func importedInvestmentPlans(from text: String) throws -> [PersonalInvestmentPlan] {
        let outputURL = temporaryJSONURL(prefix: "qieman-plan-import")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        try runTextImportScript(
            scriptRelativePath: "scripts/import_alipay_investment_plans.py",
            text: text,
            additionalArguments: ["--output", outputURL.path]
        )
        return try investmentPlansStore.load(from: outputURL)
    }

    func runPortfolioSummaryImport(text: String, outputURL: URL) throws {
        try runTextImportScript(
            scriptRelativePath: "scripts/import_alipay_portfolio.py",
            text: text,
            additionalArguments: ["--output", outputURL.path]
        )
    }

    @discardableResult
    func runTextImportScript(scriptRelativePath: String, text: String, additionalArguments: [String] = []) throws -> String {
        _ = try serverController.prepareEnvironment()
        guard let projectDirectory = serverController.projectDirectory else {
            throw LocalServerError.projectMissing
        }
        let inputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("qieman-import-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: inputURL) }
        try text.write(to: inputURL, atomically: true, encoding: .utf8)
        return try runPythonScript(
            projectDirectory: projectDirectory,
            scriptRelativePath: scriptRelativePath,
            arguments: ["--input", inputURL.path] + additionalArguments
        )
    }

    func temporaryJSONURL(prefix: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(prefix)-\(UUID().uuidString).json")
    }

    func runPrepareImportScript(
        projectDirectory: URL,
        target: PersonalDataImportTarget,
        source: PersonalDataImportSource,
        inputURL: URL
    ) throws -> String {
        try runPythonScript(
            projectDirectory: projectDirectory,
            scriptRelativePath: "scripts/prepare_personal_import.py",
            arguments: [
                "--target", target.prepareTargetValue,
                "--source", source.prepareSourceValue,
                "--input", inputURL.path,
            ]
        )
    }

    func runPythonScript(projectDirectory: URL, scriptRelativePath: String, arguments: [String]) throws -> String {
        let env = ProcessInfo.processInfo.environment
        let pythonPath = env["QIEMAN_PYTHON"].flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/bin/python3"
        let scriptURL = projectDirectory.appendingPathComponent(scriptRelativePath)

        guard FileManager.default.isExecutableFile(atPath: pythonPath) else {
            throw LocalServerError.pythonMissing(pythonPath)
        }
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw LocalServerError.startupFailed("缺少导入脚本：\(scriptURL.lastPathComponent)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptURL.path] + arguments
        process.currentDirectoryURL = projectDirectory
        process.environment = env

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw LocalServerError.startupFailed(stderr.isEmpty ? stdout : stderr)
        }
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func fetchPlatformIfPossible() async throws -> PlatformPayload? {
        let prodCode = form.prodCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prodCode.isEmpty else {
            return nil
        }
        return try await platformClient.fetchPlatformPayload(prodCode: prodCode)
    }
}
