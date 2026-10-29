import UIKit
import WebKit

/// Completes every WebKit dialog exactly once, including view teardown.
@MainActor final class CardScriptDialogs: NSObject, WKUIDelegate {
    var presentedChanged: ((Bool) -> Void)?
    let audioCapture = CardTemplateAudioCapture()
    private var alert: UIAlertController?
    private var invalidated = false
    private var pending: ((String?, Bool) -> Void)?
    override init() {
        super.init()
        audioCapture.presentedChanged = { [weak self] _ in self?.notifyPresented() }
    }
    private func notifyPresented() { presentedChanged?(pending != nil || audioCapture.isRequestPending) }
    private func show(in webView: WKWebView, message: String, defaultText: String? = nil, prompt: Bool = false, confirm: Bool, completion: @escaping (String?, Bool) -> Void) {
        guard !invalidated, pending == nil, !audioCapture.isRequestPending, var presenter = webView.window?.rootViewController else { completion(nil, false); return }
        while let next = presenter.presentedViewController { presenter = next }
        guard !(presenter is UIAlertController), !presenter.isBeingDismissed else { completion(nil, false); return }
        let dialog = UIAlertController(title: "AnkiPad", message: message, preferredStyle: .alert)
        if prompt {
            dialog.addTextField { field in
                field.text = defaultText
                field.autocapitalizationType = .none
                field.autocorrectionType = .no
                field.accessibilityIdentifier = "card-js-prompt-input"
            }
        }
        pending = completion
        alert = dialog
        dialog.addAction(UIAlertAction(title: "OK", style: .default) { [weak self, weak dialog] _ in
            self?.resolve(text: prompt ? dialog?.textFields?.first?.text : nil, accepted: true)
        })
        if confirm || prompt {
            dialog.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { [weak self] _ in self?.resolve(text: nil, accepted: false) })
        }
        notifyPresented()
        StudyMotion.present(dialog, from: presenter)
    }
    private func resolve(text: String?, accepted: Bool) {
        guard let alert else { finish(text: text, accepted: accepted); return }
        StudyMotion.dismiss(alert) { [weak self] in self?.finish(text: text, accepted: accepted) }
    }
    private func finish(text: String?, accepted: Bool) {
        guard let completion = pending else { return }
        pending = nil; alert = nil
        notifyPresented()
        completion(text, accepted)
    }
    func cancel() {
        invalidated = true
        audioCapture.cancel()
        let dialog = alert
        finish(text: nil, accepted: false)
        dialog?.dismiss(animated: false)
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        guard !invalidated, pending == nil else { decisionHandler(.deny); return }
        audioCapture.request(in: webView, type: type, decision: decisionHandler)
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        show(in: webView, message: message, confirm: false) { _, _ in completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        show(in: webView, message: message, confirm: true) { _, accepted in completionHandler(accepted) }
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        show(in: webView, message: prompt, defaultText: defaultText, prompt: true, confirm: true) { text, accepted in completionHandler(accepted ? text : nil) }
    }
}
