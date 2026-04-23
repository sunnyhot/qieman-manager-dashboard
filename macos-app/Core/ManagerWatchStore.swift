import Foundation

struct ManagerWatchStore {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load(from fileURL: URL) throws -> ManagerWatchSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .default
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(ManagerWatchSettings.self, from: data)
    }

    func save(_ settings: ManagerWatchSettings, to fileURL: URL) throws {
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }
}
