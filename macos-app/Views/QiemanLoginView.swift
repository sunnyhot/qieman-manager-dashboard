import AppKit
import SwiftUI
import WebKit

private struct QiemanLoginCaptureState {
    let currentURLText: String
    let documentCookie: String
    let accessToken: String
}

final class QiemanLoginPopupContext: Identifiable {
    let id = UUID()
    let webView: WKWebView
    let title: String

    init(webView: WKWebView, title: String) {
        self.webView = webView
        self.title = title
    }
}

struct QiemanLoginView: View {
    let cookieFileURL: URL?
    let onCookieSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var session: QiemanLoginSession

    init(cookieFileURL: URL?, onCookieSaved: @escaping () -> Void) {
        self.cookieFileURL = cookieFileURL
        self.onCookieSaved = onCookieSaved
        _session = StateObject(wrappedValue: QiemanLoginSession(cookieFileURL: cookieFileURL, onCookieSaved: onCookieSaved))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            QiemanLoginWebView(session: session)
                .frame(minWidth: 980, minHeight: 680)
        }
        .frame(minWidth: 1040, minHeight: 760)
        .background(AppPalette.paper)
        .sheet(item: $session.popupContext) { context in
            QiemanLoginPopupSheet(context: context) {
                session.dismissPopup(webView: context.webView)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("登录且慢")
                        .font(.title2.bold())
                    Text("直接在 App 内完成登录。只要检测到可用的且慢登录态，App 就会自动保存到本地 `qieman.cookie`，不需要你再手工复制粘贴。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.brand)
            }

            HStack(spacing: 10) {
                statusBadge(title: session.statusTitle, tint: session.statusTint)
                if session.hasSavedCookie {
                    statusBadge(title: "已保存 \(session.savedCookieCount) 项登录态", tint: .green)
                }
                if session.popupContext != nil {
                    statusBadge(title: "登录弹窗已打开", tint: AppPalette.info)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("常用入口")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.muted)

                    HStack(spacing: 10) {
                        loginActionButton("打开官网", systemImage: "house") {
                            session.navigate(to: session.rootURL)
                        }
                        loginActionButton("打开社区", systemImage: "person.3") {
                            session.navigate(to: session.communityURL)
                        }
                        loginActionButton("重新检测", systemImage: "waveform.path.ecg") {
                            session.requestCookieCapture()
                        }
                        loginActionButton("清除登录态", systemImage: "trash") {
                            Task { await session.clearLocalLogin() }
                        }
                    }

                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(session.statusTint)
                            .frame(width: 4)
                        Text(session.statusMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(AppPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppPalette.cardStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Spacer()

                VStack(alignment: .leading, spacing: 10) {
                    Text("登录诊断")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.muted)

                    VStack(alignment: .leading, spacing: 6) {
                        loginFactRow("当前页面", value: session.currentURLText)
                        loginFactRow("默认入口", value: session.rootURL.absoluteString)
                        if let cookieFileURL {
                            loginFactRow("Cookie 文件", value: cookieFileURL.path)
                        }
                    }
                }
                .frame(width: 360, alignment: .leading)
                .padding(14)
                .background(AppPalette.card.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppPalette.line.opacity(0.75), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            Text("验证码登录完成后如果页面跳回首页，App 会继续自动检查 Cookie、本地存储和回跳参数。微信登录会在独立弹窗里显示二维码，扫码成功后也会自动检测并保存登录态。")
                .font(.system(size: 11))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(AppPalette.paper)
    }

    private func loginActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minWidth: 120)
                .background(AppPalette.cardStrong)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressResponsiveButtonStyle())
    }

    private func loginFactRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(AppPalette.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusBadge(title: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.1))
        .clipShape(Capsule())
    }
}

@MainActor
final class QiemanLoginSession: ObservableObject {
    let rootURL: URL
    let communityURL: URL

    @Published var currentURL: URL
    @Published var currentURLText: String
    @Published var statusMessage = "在页面里完成登录即可。只要检测到可用登录态，App 就会自动保存。"
    @Published var hasSavedCookie = false
    @Published var savedCookieCount = 0
    @Published var captureNonce = UUID()
    @Published var clearNonce = UUID()
    @Published var popupContext: QiemanLoginPopupContext?

    private let cookieManager: QiemanCookieManager
    private let onCookieSaved: () -> Void
    private var lastSavedCookieHeader = ""

    init(cookieFileURL: URL?, onCookieSaved: @escaping () -> Void) {
        self.rootURL = URL(string: "https://qieman.com/")!
        self.communityURL = URL(string: "https://qieman.com/community")!
        self.cookieManager = QiemanCookieManager(cookieFileURL: cookieFileURL)
        self.onCookieSaved = onCookieSaved
        self.currentURL = self.rootURL
        self.currentURLText = self.rootURL.absoluteString
        if let existing = try? cookieManager.loadCookieString(), !existing.isEmpty {
            self.hasSavedCookie = true
            self.savedCookieCount = existing.split(separator: ";").count
            self.statusMessage = "已发现本地登录态。你也可以在这里重新登录，新的登录态会自动覆盖保存。"
            self.lastSavedCookieHeader = existing
        }
    }

    var statusTitle: String {
        if hasSavedCookie {
            return "登录态已保存"
        }
        if statusMessage.contains("失败") {
            return "保存失败"
        }
        if statusMessage.contains("继续完成登录") || statusMessage.contains("尚未") || statusMessage.contains("完整写出") {
            return "等待登录"
        }
        return "登录进行中"
    }

    var statusTint: Color {
        if hasSavedCookie {
            return .green
        }
        if statusMessage.contains("失败") {
            return .red
        }
        if statusMessage.contains("继续完成登录") || statusMessage.contains("尚未") || statusMessage.contains("完整写出") {
            return .orange
        }
        return AppPalette.brand
    }

    func navigate(to url: URL) {
        currentURL = url
        currentURLText = url.absoluteString
    }

    func requestCookieCapture() {
        captureNonce = UUID()
    }

    func requestWebCookieClear() {
        clearNonce = UUID()
    }

    func updateCurrentURL(_ url: URL?) {
        guard let url else { return }
        currentURLText = url.absoluteString
    }

    func presentPopup(webView: WKWebView, requestURL: URL?) {
        let urlText = requestURL?.absoluteString.lowercased() ?? ""
        let title = (urlText.contains("wechat") || urlText.contains("wx")) ? "微信登录" : "登录弹窗"
        popupContext = QiemanLoginPopupContext(webView: webView, title: title)
        statusMessage = "登录弹窗已打开。验证码确认页、微信二维码和第三方登录页会显示在这里；完成后 App 会自动检测登录态。"
    }

    func dismissPopup(webView: WKWebView? = nil) {
        guard let popupContext else { return }
        if let webView, popupContext.webView !== webView {
            return
        }
        popupContext.webView.stopLoading()
        self.popupContext = nil
        requestCookieCapture()
    }

    func captureLoginState(from webView: WKWebView) async {
        let captureState = await evaluateLoginState(in: webView)
        await persistCookies(
            from: webView.configuration.websiteDataStore.httpCookieStore,
            accessTokenHint: captureState.accessToken,
            documentCookie: captureState.documentCookie,
            currentURL: captureState.currentURLText
        )
    }

    func persistCookies(
        from cookieStore: WKHTTPCookieStore,
        accessTokenHint: String? = nil,
        documentCookie: String? = nil,
        currentURL: String? = nil
    ) async {
        do {
            if let currentURL, !currentURL.isEmpty {
                currentURLText = currentURL
            }
            let cookies = await allCookies(from: cookieStore)
            let result = try cookieManager.saveQiemanCookies(
                cookies,
                accessTokenHint: accessTokenHint,
                documentCookie: documentCookie
            )
            if result.saved {
                try finishSavingCookieHeader(result.cookieHeader, cookieCount: result.cookieCount)
                return
            }

            if result.hasQiemanCookies {
                let authPayload = await QiemanNativeClient(cookieFileURL: nil, rawCookie: result.cookieHeader).validateAuth()
                if authPayload.ok {
                    try cookieManager.persistCookieHeader(result.cookieHeader)
                    try finishSavingCookieHeader(result.cookieHeader, cookieCount: result.cookieCount)
                } else if result.hasAccessToken {
                    statusMessage = "检测到了登录态，但还没通过鉴权校验。你可以继续完成登录流程，或点一次“重新检测”。"
                } else {
                    statusMessage = "已进入且慢页面，但登录态还没完整写出。可以继续完成登录，或切到社区页后再重新检测。"
                }
            } else {
                statusMessage = "尚未发现可用登录态，请继续在页面里完成登录。"
            }
        } catch {
            statusMessage = "保存登录态失败：\(error.localizedDescription)"
        }
    }

    func clearLocalLogin() async {
        do {
            try cookieManager.clearCookieFile()
            hasSavedCookie = false
            savedCookieCount = 0
            lastSavedCookieHeader = ""
            popupContext = nil
            statusMessage = "本地 qieman.cookie 已清除，正在清理登录页里的且慢 Cookie。"
            requestWebCookieClear()
            requestCookieCapture()
        } catch {
            statusMessage = "清除本地登录态失败：\(error.localizedDescription)"
        }
    }

    private func allCookies(from cookieStore: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private func evaluateLoginState(in webView: WKWebView) async -> QiemanLoginCaptureState {
        let script = #"""
        (() => {
          const normalizeToken = (value) => {
            if (!value || typeof value !== 'string') return '';
            const trimmed = value.trim();
            if (!trimmed) return '';
            const cleaned = trimmed.replace(/^Bearer\s+/i, '');
            try {
              const parsed = JSON.parse(cleaned);
              if (parsed && typeof parsed === 'object') {
                for (const key of ['access_token', 'accessToken', 'token', 'jwt', 'authorization']) {
                  const nested = parsed[key];
                  if (typeof nested === 'string' && nested.trim()) {
                    return nested.trim().replace(/^Bearer\s+/i, '');
                  }
                }
              }
            } catch (error) {}
            return cleaned;
          };

          const scanStorage = (storage) => {
            try {
              const keys = [];
              for (let index = 0; index < storage.length; index += 1) {
                const key = storage.key(index);
                if (key) keys.push(key);
              }
              const candidateKeys = Array.from(new Set([
                'access_token',
                'ACCESS_TOKEN',
                'token',
                'TOKEN',
                'auth_token',
                'AuthToken',
                'userToken',
                'authorization',
                ...keys,
              ]));
              for (const key of candidateKeys) {
                const token = normalizeToken(storage.getItem(key) || '');
                if (token && token.length > 16) {
                  return token;
                }
              }
            } catch (error) {}
            return '';
          };

          const scanUrl = () => {
            try {
              const url = new URL(location.href || '');
              const candidates = [
                url.searchParams.get('access_token'),
                url.searchParams.get('token'),
              ];
              const hashParams = new URLSearchParams((url.hash || '').replace(/^#/, ''));
              candidates.push(hashParams.get('access_token'));
              candidates.push(hashParams.get('token'));
              for (const value of candidates) {
                const token = normalizeToken(value || '');
                if (token) return token;
              }
            } catch (error) {}
            return '';
          };

          const scanDocumentCookie = () => {
            const raw = document.cookie || '';
            for (const chunk of raw.split(';')) {
              const index = chunk.indexOf('=');
              if (index <= 0) continue;
              const name = chunk.slice(0, index).trim();
              const value = chunk.slice(index + 1).trim();
              if (name === 'access_token' && value) {
                return value;
              }
            }
            return '';
          };

          return {
            href: location.href || '',
            documentCookie: document.cookie || '',
            accessToken: scanStorage(window.localStorage) || scanStorage(window.sessionStorage) || scanUrl() || scanDocumentCookie(),
          };
        })()
        """#

        do {
            let value = try await webView.evaluateJavaScriptAsync(script)
            let object = value as? [String: Any]
            return QiemanLoginCaptureState(
                currentURLText: object?["href"] as? String ?? (webView.url?.absoluteString ?? currentURLText),
                documentCookie: object?["documentCookie"] as? String ?? "",
                accessToken: object?["accessToken"] as? String ?? ""
            )
        } catch {
            return QiemanLoginCaptureState(
                currentURLText: webView.url?.absoluteString ?? currentURLText,
                documentCookie: "",
                accessToken: ""
            )
        }
    }

    private func finishSavingCookieHeader(_ header: String, cookieCount: Int) throws {
        guard header != lastSavedCookieHeader || !hasSavedCookie else { return }
        lastSavedCookieHeader = header
        hasSavedCookie = true
        savedCookieCount = cookieCount
        popupContext = nil
        statusMessage = "已自动保存登录态。现在可以关闭窗口，回到主界面直接验证登录态或刷新关注动态。"
        onCookieSaved()
    }
}

private struct QiemanLoginWebView: NSViewRepresentable {
    @ObservedObject var session: QiemanLoginSession

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.attach(webView)
        webView.load(URLRequest(url: session.currentURL))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.session = session
        if webView.url?.absoluteString != session.currentURL.absoluteString {
            webView.load(URLRequest(url: session.currentURL))
        }
        if context.coordinator.lastCaptureNonce != session.captureNonce {
            context.coordinator.lastCaptureNonce = session.captureNonce
            Task { await session.captureLoginState(from: webView) }
        }
        if context.coordinator.lastClearNonce != session.clearNonce {
            context.coordinator.lastClearNonce = session.clearNonce
            context.coordinator.clearQiemanCookies(in: webView.configuration.websiteDataStore.httpCookieStore)
        }
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.detach(from: nsView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        var session: QiemanLoginSession
        var lastCaptureNonce: UUID
        var lastClearNonce: UUID
        private weak var primaryWebView: WKWebView?
        private weak var lastInteractiveWebView: WKWebView?
        private var observedCookieStores: [ObjectIdentifier: WKHTTPCookieStore] = [:]

        init(session: QiemanLoginSession) {
            self.session = session
            self.lastCaptureNonce = session.captureNonce
            self.lastClearNonce = session.clearNonce
        }

        deinit {
            for store in observedCookieStores.values {
                store.remove(self)
            }
        }

        func attach(_ webView: WKWebView) {
            configure(webView, asPrimary: primaryWebView == nil)
        }

        func detach(from webView: WKWebView) {
            if primaryWebView === webView {
                primaryWebView = nil
            }
            if lastInteractiveWebView === webView {
                lastInteractiveWebView = primaryWebView
            }
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task { @MainActor in
                if let webView = lastInteractiveWebView ?? primaryWebView {
                    await session.captureLoginState(from: webView)
                } else {
                    await session.persistCookies(from: cookieStore)
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            session.updateCurrentURL(webView.url)
            lastInteractiveWebView = webView
            Task { @MainActor in
                await session.captureLoginState(from: webView)
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            session.updateCurrentURL(webView.url)
            lastInteractiveWebView = webView
        }

        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            session.updateCurrentURL(webView.url)
            lastInteractiveWebView = webView
            Task { @MainActor in
                await session.captureLoginState(from: webView)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            session.updateCurrentURL(navigationAction.request.url)
            lastInteractiveWebView = webView
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            let popupWebView = WKWebView(frame: .zero, configuration: configuration)
            popupWebView.setValue(false, forKey: "drawsBackground")
            configure(popupWebView, asPrimary: false)
            lastInteractiveWebView = popupWebView
            Task { @MainActor in
                session.presentPopup(webView: popupWebView, requestURL: navigationAction.request.url)
            }
            return popupWebView
        }

        func webViewDidClose(_ webView: WKWebView) {
            detach(from: webView)
            Task { @MainActor in
                session.dismissPopup(webView: webView)
            }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            let alert = NSAlert()
            alert.messageText = "且慢"
            alert.informativeText = message
            alert.addButton(withTitle: "确定")
            alert.runModal()
            completionHandler()
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            let alert = NSAlert()
            alert.messageText = "且慢"
            alert.informativeText = message
            alert.addButton(withTitle: "确定")
            alert.addButton(withTitle: "取消")
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (String?) -> Void
        ) {
            let alert = NSAlert()
            alert.messageText = "且慢"
            alert.informativeText = prompt
            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
            textField.stringValue = defaultText ?? ""
            alert.accessoryView = textField
            alert.addButton(withTitle: "确定")
            alert.addButton(withTitle: "取消")
            let response = alert.runModal()
            completionHandler(response == .alertFirstButtonReturn ? textField.stringValue : nil)
        }

        func clearQiemanCookies(in cookieStore: WKHTTPCookieStore) {
            cookieStore.getAllCookies { cookies in
                let qiemanCookies = cookies.filter { $0.domain.lowercased().contains("qieman.com") }
                for cookie in qiemanCookies {
                    cookieStore.delete(cookie)
                }
                Task { @MainActor in
                    self.session.hasSavedCookie = false
                    self.session.savedCookieCount = 0
                    self.session.popupContext = nil
                    self.session.statusMessage = "已清除本地与页面内登录态。现在可以重新登录新的且慢账号。"
                    self.session.navigate(to: self.session.rootURL)
                }
            }
        }

        private func configure(_ webView: WKWebView, asPrimary: Bool) {
            webView.navigationDelegate = self
            webView.uiDelegate = self
            if asPrimary {
                primaryWebView = webView
            }
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            let key = ObjectIdentifier(cookieStore)
            if observedCookieStores[key] == nil {
                cookieStore.add(self)
                observedCookieStores[key] = cookieStore
            }
        }
    }
}

private struct QiemanLoginPopupSheet: View {
    let context: QiemanLoginPopupContext
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                    Text("微信登录二维码、短信确认页和第三方跳转页都会显示在这里。")
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
                Button("关闭") {
                    onClose()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.brand)
            }
            .padding(16)

            Divider()

            QiemanPopupWebViewContainer(webView: context.webView)
                .frame(minWidth: 520, minHeight: 620)
        }
        .frame(minWidth: 560, minHeight: 700)
        .background(AppPalette.paper)
    }
}

private struct QiemanPopupWebViewContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

private extension WKWebView {
    func evaluateJavaScriptAsync(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value)
                }
            }
        }
    }
}
