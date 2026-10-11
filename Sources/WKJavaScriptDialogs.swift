import UIKit
import WebKit

// All completion paths run on the main thread. Clear the handler before calling
// WebKit so an action, presentation failure or dismissal can only finish once.
@MainActor
private final class JavaScriptDialogCompletion<Value> {
    private var handler: ((Value) -> Void)?
    private let cancellationValue: Value

    init(cancellationValue: Value, handler: @escaping (Value) -> Void) {
        self.cancellationValue = cancellationValue
        self.handler = handler
    }

    var isPending: Bool { handler != nil }

    func complete(_ value: Value) {
        guard let handler else { return }
        self.handler = nil
        handler(value)
    }

    func unavailable(kind: String) {
        guard isPending else { return }
        // Never record the message, origin, default text or user's input.
        NativeDiagnostics.shared.record("js_dialog_unavailable", detail: kind)
        complete(cancellationValue)
    }
}

// The Float website uses JavaScript dialogs for plugin updates and deletions.
// Keep this bridge native: no injected JS, navigation or data-store changes.
extension BrowserViewController {
    // A file picker may still be closing when FileReader invokes confirm().
    // Retry for at most 12 * 120ms; never present over another native modal.
    private func presentJavaScriptDialog<Value>(
        _ alert: UIAlertController,
        kind: String,
        completion: JavaScriptDialogCompletion<Value>,
        retriesLeft: Int = 12
    ) {
        guard completion.isPending else { return }
        let window = viewIfLoaded?.window
        let canPresent = window?.windowScene?.activationState == .foregroundActive
            && presentedViewController == nil
            && !isBeingPresented && !isBeingDismissed && transitionCoordinator == nil
        guard canPresent else {
            guard retriesLeft > 0 else {
                completion.unavailable(kind: kind)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) { [weak self] in
                guard let self else {
                    completion.unavailable(kind: kind)
                    return
                }
                self.presentJavaScriptDialog(
                    alert, kind: kind, completion: completion, retriesLeft: retriesLeft - 1
                )
            }
            return
        }
        present(alert, animated: true)
        observeJavaScriptDialog(alert, kind: kind, completion: completion)
    }

    // UIKit can refuse present() without invoking its completion. Also handle
    // a dialog disappearing without an action. Do not time out a visible dialog
    // while the user is reading it or temporarily switches to another app.
    private func observeJavaScriptDialog<Value>(
        _ alert: UIAlertController,
        kind: String,
        completion: JavaScriptDialogCompletion<Value>,
        checksUntilVisible: Int = 12,
        wasVisible: Bool = false
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) { [weak self, weak alert] in
            guard completion.isPending else { return }
            guard let self, let alert else {
                completion.unavailable(kind: kind)
                return
            }
            let visible = alert.presentingViewController != nil && alert.viewIfLoaded?.window != nil
            if !visible && (wasVisible || checksUntilVisible == 0) {
                // Only dismiss our own JS alert; never close a picker/share sheet.
                if alert.presentingViewController != nil { alert.dismiss(animated: false) }
                completion.unavailable(kind: kind)
                return
            }
            self.observeJavaScriptDialog(
                alert, kind: kind, completion: completion,
                checksUntilVisible: max(0, checksUntilVisible - 1),
                wasVisible: wasVisible || visible
            )
        }
    }

    @objc func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let completion = JavaScriptDialogCompletion<Void>(cancellationValue: ()) { _ in completionHandler() }
        let alert = UIAlertController(title: frame.request.url?.host ?? "Float", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completion.complete(()) })
        presentJavaScriptDialog(alert, kind: "alert", completion: completion)
    }

    @objc func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let completion = JavaScriptDialogCompletion(cancellationValue: false, handler: completionHandler)
        let alert = UIAlertController(title: frame.request.url?.host ?? "Float", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completion.complete(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completion.complete(true) })
        presentJavaScriptDialog(alert, kind: "confirm", completion: completion)
    }

    @objc func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let completion = JavaScriptDialogCompletion<String?>(cancellationValue: nil, handler: completionHandler)
        let alert = UIAlertController(title: frame.request.url?.host ?? "Float", message: prompt, preferredStyle: .alert)
        alert.addTextField { field in field.text = defaultText ?? "" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completion.complete(nil) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak alert] _ in
            completion.complete(alert?.textFields?.first?.text ?? "")
        })
        presentJavaScriptDialog(alert, kind: "prompt", completion: completion)
    }
}
