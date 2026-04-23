import Foundation

struct QiemanCookieSaveResult {
    let saved: Bool
    let hasQiemanCookies: Bool
    let hasAccessToken: Bool
    let cookieCount: Int
    let cookieHeader: String
}

final class QiemanCookieManager {
    private let cookieFileURL: URL?

    init(cookieFileURL: URL?) {
        self.cookieFileURL = cookieFileURL
    }

    func loadCookieString() throws -> String {
        guard let cookieFileURL else { return "" }
        guard FileManager.default.fileExists(atPath: cookieFileURL.path) else { return "" }
        return try String(contentsOf: cookieFileURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func saveQiemanCookies(
        _ cookies: [HTTPCookie],
        accessTokenHint: String? = nil,
        documentCookie: String? = nil
    ) throws -> QiemanCookieSaveResult {
        let qiemanCookies = normalizedQiemanCookies(cookies)
        let tokenHint = normalizedToken(accessTokenHint)
        let headerPairs = mergedCookiePairs(
            from: qiemanCookies,
            documentCookie: documentCookie,
            accessTokenHint: tokenHint
        )
        let header = headerPairs.joined(separator: "; ")
        let hasAccessToken = headerPairs.contains(where: { $0.hasPrefix("access_token=") })
        let hasCookiePayload = !headerPairs.isEmpty

        guard let cookieFileURL, hasCookiePayload, hasAccessToken else {
            return QiemanCookieSaveResult(
                saved: false,
                hasQiemanCookies: hasCookiePayload,
                hasAccessToken: hasAccessToken,
                cookieCount: headerPairs.count,
                cookieHeader: header
            )
        }

        try FileManager.default.createDirectory(at: cookieFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try header.write(to: cookieFileURL, atomically: true, encoding: .utf8)
        return QiemanCookieSaveResult(
            saved: true,
            hasQiemanCookies: true,
            hasAccessToken: true,
            cookieCount: headerPairs.count,
            cookieHeader: header
        )
    }

    func persistCookieHeader(_ header: String) throws {
        guard let cookieFileURL else { return }
        let normalized = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        try FileManager.default.createDirectory(at: cookieFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try normalized.write(to: cookieFileURL, atomically: true, encoding: .utf8)
    }

    func clearCookieFile() throws {
        guard let cookieFileURL else { return }
        if FileManager.default.fileExists(atPath: cookieFileURL.path) {
            try FileManager.default.removeItem(at: cookieFileURL)
        }
    }

    private func normalizedQiemanCookies(_ cookies: [HTTPCookie]) -> [HTTPCookie] {
        let filtered = cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            return domain.contains("qieman.com")
        }

        let sorted = filtered.sorted { lhs, rhs in
            if lhs.name != rhs.name {
                return lhs.name < rhs.name
            }
            if lhs.domain != rhs.domain {
                return lhs.domain.count > rhs.domain.count
            }
            return lhs.path.count > rhs.path.count
        }

        var seen = Set<String>()
        var result: [HTTPCookie] = []
        for cookie in sorted {
            let key = "\(cookie.name)|\(cookie.domain)|\(cookie.path)"
            if seen.contains(key) {
                continue
            }
            seen.insert(key)
            result.append(cookie)
        }
        return result
    }

    private func mergedCookiePairs(
        from cookies: [HTTPCookie],
        documentCookie: String?,
        accessTokenHint: String?
    ) -> [String] {
        var result = cookies.map { "\($0.name)=\($0.value)" }
        var seenNames = Set(cookies.map(\.name))

        for pair in parseCookiePairs(documentCookie) {
            let name = cookieName(from: pair)
            if !seenNames.contains(name) {
                result.append(pair)
                seenNames.insert(name)
            }
        }

        if let accessTokenHint, !accessTokenHint.isEmpty, !seenNames.contains("access_token") {
            result.append("access_token=\(accessTokenHint)")
        }

        return result
    }

    private func parseCookiePairs(_ rawHeader: String?) -> [String] {
        guard let rawHeader else { return [] }
        return rawHeader
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.contains("=") }
    }

    private func cookieName(from pair: String) -> String {
        pair.split(separator: "=", maxSplits: 1).first.map(String.init) ?? pair
    }

    private func normalizedToken(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("bearer ") {
            return String(trimmed.dropFirst(7))
        }
        return trimmed
    }
}
