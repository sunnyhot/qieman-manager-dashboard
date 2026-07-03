import Foundation

extension AppModel {
    var tradeSignalSummary: TradeSignalSummary {
        TradeSignalSummary.make(
            report: trendReport,
            rows: personalAssetRows,
            settings: tradeSignalSettings,
            now: Self.timestampString()
        )
    }

    func loadTradeSignalState() {
        if let tradeSignalSettingsFileURL {
            do {
                tradeSignalSettings = try TradeSignalSettingsStore().load(from: tradeSignalSettingsFileURL)
            } catch {
                lastTrendError = error.localizedDescription
            }
        }

        if let tradeSignalNotificationStateFileURL {
            do {
                tradeSignalNotificationState = try TradeSignalNotificationStateStore().load(from: tradeSignalNotificationStateFileURL)
            } catch {
                lastTrendError = error.localizedDescription
            }
        }
    }

    func saveTradeSignalSettings() {
        guard let tradeSignalSettingsFileURL else { return }
        do {
            try TradeSignalSettingsStore().save(tradeSignalSettings, to: tradeSignalSettingsFileURL)
        } catch {
            lastTrendError = error.localizedDescription
        }
    }

    func saveTradeSignalNotificationState() {
        guard let tradeSignalNotificationStateFileURL else { return }
        do {
            try TradeSignalNotificationStateStore().save(tradeSignalNotificationState, to: tradeSignalNotificationStateFileURL)
        } catch {
            lastTrendError = error.localizedDescription
        }
    }

    func evaluateTradeSignalNotifications(now: String? = nil) async {
        let now = now ?? Self.timestampString()
        let summary = TradeSignalSummary.make(
            report: trendReport,
            rows: personalAssetRows,
            settings: tradeSignalSettings,
            now: now
        )
        let requests = TradeSignalNotificationDecision.makeRequests(
            summary: summary,
            settings: tradeSignalSettings,
            state: tradeSignalNotificationState,
            day: tradeSignalDayString(from: now)
        )
        guard !requests.isEmpty else { return }
        guard await notificationManager.requestAuthorizationIfNeeded() else { return }

        for request in requests {
            await notificationManager.send(
                title: request.title,
                body: request.body,
                deepLink: NotificationDeepLinkPayload(type: .workbenchTrend, targetID: "trade-signals")
            )
            tradeSignalNotificationState.markSent(request.key)
        }
        saveTradeSignalNotificationState()
    }

    private func tradeSignalDayString(from timestamp: String) -> String {
        let trimmed = timestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return trimmed }
        return String(trimmed.prefix(10))
    }
}
