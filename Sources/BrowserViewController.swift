import UIKit
import WebKit

/// Remote Float loader. The Netlify deployment owns all web app logic and updates.
/// We deliberately do not inject JS, mutate the UA, or clear WebKit's data store.
final class BrowserViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    private static let homeURL = URL(string: "https://aivirtualphone1130.netlify.app/")!
    private static let allowedHost = "aivirtualphone1130.netlify.app"

    private var browser: WKWebView!
    private var recoveryView: UIView?
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBackground

        let configuration = WKWebViewConfiguration()
        // CRITICAL: persistent cookies / localStorage / IndexedDB; NEVER .nonPersistent().
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        configuration.allowsInlineMediaPlayback = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        browser = webView
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Invisible to everyday touches: hold THREE fingers for 1.5s to export native logs.
        // Using a diagnostic gesture avoids covering Float's input bar or UI.
        let diagnosticsGesture = UILongPressGestureRecognizer(target: self, action: #selector(showDiagnosticMenu(_:)))
        diagnosticsGesture.numberOfTouchesRequired = 3
        diagnosticsGesture.minimumPressDuration = 1.5
        diagnosticsGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(diagnosticsGesture)

        NativeDiagnostics.shared.record("shell_opened")
        webView.load(URLRequest(url: Self.homeURL, cachePolicy: .useProtocolCachePolicy))
    }

    @objc private func showDiagnosticMenu(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        let alert = UIAlertController(title: "Float iOS Test", message: "原生诊断只记录 App 生命周期和网页进程事件，不含聊天内容。", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "导出原生诊断", style: .default) { [weak self] _ in self?.shareDiagnostics() })
        alert.addAction(UIAlertAction(title: "检查网站更新（手动刷新）", style: .default) { [weak self] _ in
            self?.confirmReload()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    private func confirmReload() {
        let alert = UIAlertController(title: "刷新 Float？", message: "刷新会中断当前正在进行的 AI 生成。请确认当前没有未完成的回复。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "刷新", style: .destructive) { [weak self] _ in
            guard let self else { return }
            NativeDiagnostics.shared.record("manual_reload")
            self.hideRecovery()
            self.browser.reload()
        })
        present(alert, animated: true)
    }

    private func shareDiagnostics() {
        do {
            let fileURL = try NativeDiagnostics.shared.makeExport()
            presentShareSheet(fileURL)
        } catch {
            presentNotice(title: "导出失败", message: error.localizedDescription)
        }
    }

    private func presentShareSheet(_ url: URL) {
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(sheet, animated: true)
    }

    private func presentNotice(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private func showRecovery(title: String, detail: String) {
        hideRecovery()
        let panel = UIView()
        panel.backgroundColor = UIColor.systemBackground
        panel.translatesAutoresizingMaskIntoConstraints = false

        let heading = UILabel()
        heading.font = .preferredFont(forTextStyle: .title2)
        heading.text = title
        heading.textAlignment = .center
        heading.numberOfLines = 0

        let body = UILabel()
        body.font = .preferredFont(forTextStyle: .body)
        body.textColor = .secondaryLabel
        body.text = detail
        body.textAlignment = .center
        body.numberOfLines = 0

        let refresh = UIButton(type: .system)
        refresh.setTitle("手动重新加载网页", for: .normal)
        refresh.addTarget(self, action: #selector(recoverByReload), for: .touchUpInside)

        let export = UIButton(type: .system)
        export.setTitle("导出原生诊断", for: .normal)
        export.addTarget(self, action: #selector(exportFromRecovery), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [heading, body, refresh, export])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 22
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.topAnchor.constraint(equalTo: view.topAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: panel.centerYAnchor)
        ])
        recoveryView = panel
    }

    private func hideRecovery() {
        recoveryView?.removeFromSuperview()
        recoveryView = nil
    }

    @objc private func recoverByReload() {
        confirmReload()
    }

    @objc private func exportFromRecovery() {
        shareDiagnostics()
    }

    // MARK: Navigation

    private func isFloatSite(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == Self.allowedHost
    }

    private func openExternalIfSafe(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        // No arbitrary custom-scheme dispatch from untrusted webpage content.
        guard ["https", "http", "mailto", "tel", "sms"].contains(scheme) else {
            NativeDiagnostics.shared.record("external_scheme_blocked", detail: scheme)
            return
        }
        UIApplication.shared.open(url)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if url.scheme == "blob" {
            // WebKit may turn blob: exports into a download; never redirect them to Safari.
            decisionHandler(.allow)
            return
        }
        if url.scheme == "about" {
            decisionHandler(.allow)
            return
        }

        // Only constrain top-level navigation, not fetch/image/audio/API subresources.
        if navigationAction.targetFrame == nil {
            if isFloatSite(url) {
                webView.load(navigationAction.request)
            } else {
                openExternalIfSafe(url)
            }
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true && !isFloatSite(url) {
            // External login/auth providers are opened in Safari for safety.
            // OAuth callbacks back into this shell need separate integration.
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let header = (navigationResponse.response as? HTTPURLResponse)?.allHeaderFields.first(where: {
            String(describing: $0.key).lowercased() == "content-disposition"
        }).map { String(describing: $0.value).lowercased() } ?? ""
        if header.contains("attachment") || !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hideRecovery()
        NativeDiagnostics.shared.record("navigation_finished", detail: webView.url?.host)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // -999 = cancelled navigation, e.g. a popup being handled externally.
        if (error as NSError).code == NSURLErrorCancelled { return }
        NativeDiagnostics.shared.record("navigation_failed", detail: "code:\((error as NSError).code)")
        showRecovery(title: "Float 加载失败", detail: "未修改或清除本地数据。请检查网络，准备好后手动重试。")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // This callback proves WebContent was terminated, but NOT why (OOM/Jetsam unknown).
        NativeDiagnostics.shared.record("web_content_process_terminated")
        showRecovery(title: "Float 网页进程已结束", detail: "已记录原生进程事件。不会自动刷新，以免中断尚未保存的操作。你可以先导出诊断，再手动重新加载。")
    }

    // MARK: Popups + permissions

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if isFloatSite(url) { webView.load(navigationAction.request) }
            else { openExternalIfSafe(url) }
        }
        return nil
    }
    // Do not auto-grant microphone/camera: WKWebView's default behavior prompts.

    // MARK: Downloads

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        do {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("FloatExports", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let baseName = URL(fileURLWithPath: suggestedFilename).lastPathComponent
                .replacingOccurrences(of: "\\", with: "_")
            let safeName = baseName.isEmpty || baseName == "." || baseName == ".." ? "float-export.bin" : baseName
            let ext = (safeName as NSString).pathExtension
            let stem = (safeName as NSString).deletingPathExtension
            var target = dir.appendingPathComponent(safeName)
            var n = 1
            while FileManager.default.fileExists(atPath: target.path) {
                let name = ext.isEmpty ? "\(stem)-\(n)" : "\(stem)-\(n).\(ext)"
                target = dir.appendingPathComponent(name)
                n += 1
            }
            downloadDestinations[ObjectIdentifier(download)] = target
            completionHandler(target)
        } catch {
            NativeDiagnostics.shared.record("download_destination_failed", detail: String(describing: (error as NSError).code))
            completionHandler(nil)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        NativeDiagnostics.shared.record("download_finished", detail: url.pathExtension)
        presentShareSheet(url)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        NativeDiagnostics.shared.record("download_failed", detail: "code:\((error as NSError).code)")
        presentNotice(title: "下载失败", message: "未清除任何网页或聊天数据。请重试导出。")
    }
}
