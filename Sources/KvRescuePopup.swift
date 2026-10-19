import UIKit
import WebKit

/// Native second-window host for exactly one Float KV cache handoff.
///
/// window.open('/float-kv-rescue#cache-snapshot', '_blank') MUST return a real
/// same-origin WKWebView. Navigating the original view destroys the hydrated
/// in-memory cache before the rescue child can read it.
///
/// This class does not read, copy, persist or inspect the KV payload. WebKit's
/// supplied WKWebViewConfiguration is used unchanged so the child stays in the
/// opener's website-data / window-opener context.
@MainActor
final class KvRescuePopup {
    private static let allowedHost = "aivirtualphone1130.netlify.app"
    private weak var host: BrowserViewController?
    private var child: WKWebView?
    private var overlay: UIView?

    init(host: BrowserViewController) {
        self.host = host
    }

    var isOpen: Bool { child != nil }

    static func isRequest(_ action: WKNavigationAction,
                          from source: WKWebView,
                          main: WKWebView) -> Bool {
        guard source === main,
              action.targetFrame == nil,
              let url = action.request.url else { return false }
        return url.scheme?.lowercased() == "https"
            && (url.port == nil || url.port == 443)
            && url.user == nil && url.password == nil
            && url.host?.lowercased() == allowedHost
            && url.path == "/float-kv-rescue"
            && url.fragment == "cache-snapshot"
    }

    /// WKUIDelegate returns this *new* view, rather than loading the request in
    /// the opener. Do NOT call child.load(request): WebKit performs that load.
    func open(configuration: WKWebViewConfiguration) -> WKWebView? {
        guard let host, host.isViewLoaded, !isOpen else {
            NativeDiagnostics.shared.record("kv_popup_rejected", detail: "already_open_or_inactive")
            return nil
        }

        let panel = UIView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.backgroundColor = .systemBackground

        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.backgroundColor = .secondarySystemBackground

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .preferredFont(forTextStyle: .headline)
        title.text = "KV 应急缓存快照"
        title.textAlignment = .left
        title.lineBreakMode = .byTruncatingTail

        let close = UIButton(type: .system)
        close.translatesAutoresizingMaskIntoConstraints = false
        close.setTitle("关闭", for: .normal)
        close.accessibilityLabel = "关闭 KV 救援窗口"
        close.addTarget(self, action: #selector(confirmClose), for: .touchUpInside)

        // The configuration is supplied by WebKit and must NOT be replaced.
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.navigationDelegate = host
        popup.uiDelegate = host
        popup.scrollView.contentInsetAdjustmentBehavior = .never
        popup.allowsBackForwardNavigationGestures = false

        header.addSubview(title)
        header.addSubview(close)
        panel.addSubview(header)
        panel.addSubview(popup)
        host.view.addSubview(panel)

        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            panel.topAnchor.constraint(equalTo: host.view.topAnchor),
            panel.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
            header.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            header.topAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 48),
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -12),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            close.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            close.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            close.heightAnchor.constraint(equalToConstant: 44),
            popup.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            popup.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            popup.topAnchor.constraint(equalTo: header.bottomAnchor),
            popup.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
        ])

        child = popup
        overlay = panel
        NativeDiagnostics.shared.record("kv_popup_created")
        return popup
    }

    func owns(_ webView: WKWebView) -> Bool { child === webView }

    @discardableResult
    func dismissIfOwned(_ webView: WKWebView) -> Bool {
        guard owns(webView) else { return false }
        // Releases only the auxiliary window. Never clears website data,
        // runs a migration or reloads the opener.
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        overlay?.removeFromSuperview()
        child = nil
        overlay = nil
        NativeDiagnostics.shared.record("kv_popup_closed")
        return true
    }

    @objc private func confirmClose() {
        guard let host, let webView = child else { return }
        // An unsaved generated part lives only in the rescue page's memory.
        let alert = UIAlertController(
            title: "关闭 KV 救援窗口？",
            message: "未保存的分卷和当前导出进度可能丢失。此操作不会删除 Float 源数据。请先保存并验证全部文件。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "继续救援", style: .cancel))
        alert.addAction(UIAlertAction(title: "确认关闭", style: .destructive) { [weak self, weak webView] _ in
            guard let self, let webView else { return }
            _ = self.dismissIfOwned(webView)
        })
        if host.presentedViewController == nil { host.present(alert, animated: true) }
    }

    func reportFailure(_ error: Error) {
        NativeDiagnostics.shared.record("kv_popup_navigation_failed", detail: "code:\((error as NSError).code)")
        showFailureNotice("救援窗口加载失败。原存档未修改。可关闭此窗口后从 Float 重新发起。")
    }

    func reportProcessTermination() {
        NativeDiagnostics.shared.record("kv_popup_process_terminated")
        showFailureNotice("KV 救援网页进程已结束。未保存的分卷可能丢失，请关闭窗口后重新进入；不会自动刷新或清除数据。")
    }

    private func showFailureNotice(_ message: String) {
        guard let host, host.presentedViewController == nil else { return }
        let alert = UIAlertController(title: "KV 救援提示", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        host.present(alert, animated: true)
    }
}
