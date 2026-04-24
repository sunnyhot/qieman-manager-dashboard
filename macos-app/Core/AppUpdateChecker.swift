import Foundation

struct AppUpdateAsset: Equatable {
    let name: String
    let downloadURL: URL
    let size: Int
    let contentType: String?

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

struct AppUpdateRelease: Identifiable, Equatable {
    var id: String { tagName }

    let tagName: String
    let version: String
    let title: String
    let notes: String
    let htmlURL: URL
    let publishedAt: Date?
    let asset: AppUpdateAsset?
    let currentVersion: String

    var downloadURL: URL {
        asset?.downloadURL ?? htmlURL
    }

    var displayTitle: String {
        title.isEmpty ? "版本 \(version)" : title
    }
}

enum AppUpdateCheckError: LocalizedError {
    case invalidFeedURL(String)
    case noGitHubRelease
    case requestFailed(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidFeedURL(let value):
            return "更新源地址无效：\(value)"
        case .noGitHubRelease:
            return "GitHub 上还没有可用的 Release。发布一个新版本并上传 App 压缩包后，这里就能检查到。"
        case .requestFailed(let statusCode):
            return "检查更新失败，GitHub 返回 HTTP \(statusCode)。"
        case .invalidResponse:
            return "检查更新失败，GitHub 返回的数据格式不完整。"
        }
    }
}

struct AppUpdateChecker {
    private struct GitHubReleasePayload: Decodable {
        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: URL
        let publishedAt: Date?
        let assets: [GitHubAssetPayload]

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case htmlURL = "html_url"
            case publishedAt = "published_at"
            case assets
        }
    }

    private struct GitHubAssetPayload: Decodable {
        let name: String
        let browserDownloadURL: URL
        let size: Int
        let contentType: String?

        private enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
            case contentType = "content_type"
        }
    }

    let feedURL: URL
    let currentVersion: String

    init(
        feedURLString: String = AppUpdateChecker.defaultFeedURLString,
        currentVersion: String = AppUpdateChecker.bundleVersion
    ) throws {
        guard let url = URL(string: feedURLString) else {
            throw AppUpdateCheckError.invalidFeedURL(feedURLString)
        }
        self.feedURL = url
        self.currentVersion = currentVersion
    }

    func check() async throws -> AppUpdateRelease? {
        var request = URLRequest(url: feedURL, timeoutInterval: 12)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("QiemanDashboard/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppUpdateCheckError.invalidResponse
        }
        if httpResponse.statusCode == 404 {
            throw AppUpdateCheckError.noGitHubRelease
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AppUpdateCheckError.requestFailed(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(GitHubReleasePayload.self, from: data)
        let releaseVersion = Self.normalizedVersion(payload.tagName)
        guard Self.compareVersions(releaseVersion, currentVersion) == .orderedDescending else {
            return nil
        }

        return AppUpdateRelease(
            tagName: payload.tagName,
            version: releaseVersion,
            title: payload.name ?? "",
            notes: payload.body ?? "",
            htmlURL: payload.htmlURL,
            publishedAt: payload.publishedAt,
            asset: Self.preferredAsset(from: payload.assets),
            currentVersion: currentVersion
        )
    }

    static var defaultRepository: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "QiemanUpdateRepository") as? String
        return nonEmpty(value) ?? "sunnyhot/qieman-manager-dashboard"
    }

    static var defaultFeedURLString: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "QiemanUpdateFeedURL") as? String
        return nonEmpty(value) ?? "https://api.github.com/repos/\(defaultRepository)/releases/latest"
    }

    static var bundleVersion: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return nonEmpty(value) ?? "0.0.0"
    }

    static func normalizedVersion(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("version-") {
            return String(trimmed.dropFirst("version-".count))
        }
        if trimmed.lowercased().hasPrefix("release-") {
            return String(trimmed.dropFirst("release-".count))
        }
        if trimmed.lowercased().hasPrefix("v") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = versionParts(lhs)
        let rhsParts = versionParts(rhs)
        let count = max(lhsParts.count, rhsParts.count)

        for index in 0..<count {
            let left = index < lhsParts.count ? lhsParts[index] : 0
            let right = index < rhsParts.count ? rhsParts[index] : 0
            if left > right { return .orderedDescending }
            if left < right { return .orderedAscending }
        }
        return .orderedSame
    }

    private static func preferredAsset(from assets: [GitHubAssetPayload]) -> AppUpdateAsset? {
        let preferred = assets.first { asset in
            let name = asset.name.lowercased()
            return name.contains("qiemandashboard") && name.hasSuffix(".zip")
        } ?? assets.first { asset in
            asset.name.lowercased().hasSuffix(".zip")
        } ?? assets.first

        guard let preferred else { return nil }
        return AppUpdateAsset(
            name: preferred.name,
            downloadURL: preferred.browserDownloadURL,
            size: preferred.size,
            contentType: preferred.contentType
        )
    }

    private static func versionParts(_ value: String) -> [Int] {
        normalizedVersion(value)
            .split { character in
                !(character.isNumber)
            }
            .map { Int($0) ?? 0 }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
