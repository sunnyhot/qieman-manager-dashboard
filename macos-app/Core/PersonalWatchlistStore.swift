import Foundation

struct PersonalWatchlistStore {
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder

    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func load(from fileURL: URL) throws -> [PersonalWatchlistRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([PersonalWatchlistRecord].self, from: data).map {
            PersonalWatchlistRecord(
                item: $0.item,
                baseline: $0.baseline,
                dailyPoints: $0.dailyPoints,
                alertRules: $0.alertRules,
                alertState: $0.alertState
            )
        }
    }

    func save(_ records: [PersonalWatchlistRecord], to fileURL: URL) throws {
        let normalized = records.map {
            PersonalWatchlistRecord(
                item: $0.item,
                baseline: $0.baseline,
                dailyPoints: $0.dailyPoints,
                alertRules: $0.alertRules,
                alertState: $0.alertState
            )
        }
        let data = try encoder.encode(normalized)
        try data.write(to: fileURL, options: .atomic)
    }

    func delete(at fileURL: URL) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
