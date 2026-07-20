import Foundation

struct PlatformActionAssetBuckets {
    let latestByAsset: [String: PlatformActionPayload]
    private let actionsByAsset: [String: [PlatformActionPayload]]

    init(actions: [PlatformActionPayload]) {
        var latestByAsset: [String: PlatformActionPayload] = [:]
        var actionsByAsset: [String: [PlatformActionPayload]] = [:]

        for action in actions {
            let assetKey = Self.assetKey(for: action)
            guard !assetKey.isEmpty else { continue }

            actionsByAsset[assetKey, default: []].append(action)

            if let current = latestByAsset[assetKey],
               Self.timestamp(action) <= Self.timestamp(current) {
                continue
            }
            latestByAsset[assetKey] = action
        }

        self.latestByAsset = latestByAsset
        self.actionsByAsset = actionsByAsset
    }

    func sortedActions(for assetKey: String) -> [PlatformActionPayload] {
        (actionsByAsset[assetKey] ?? []).sorted {
            Self.timestamp($0) < Self.timestamp($1)
        }
    }

    static func assetKey(for action: PlatformActionPayload) -> String {
        for value in [action.fundCode, action.title, action.fundName] {
            let text = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }
        }
        return ""
    }

    private static func timestamp(_ action: PlatformActionPayload) -> Int {
        if let txnTs = action.txnTs, txnTs > 0 {
            return txnTs
        }
        return action.createdTs ?? 0
    }
}
