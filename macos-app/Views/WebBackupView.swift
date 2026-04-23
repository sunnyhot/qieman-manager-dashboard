import SwiftUI
import WebKit

struct WebBackupView: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                WebView(url: url)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "globe")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("网页备份未就绪")
                        .font(.headline)
                    Text("切到这个页面后，App 会按需启动本地网页备份服务。")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct WebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard nsView.url != url else { return }
        nsView.load(URLRequest(url: url))
    }
}
