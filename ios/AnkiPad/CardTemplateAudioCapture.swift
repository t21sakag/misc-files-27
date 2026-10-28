import AVFoundation
import UIKit
import WebKit

/// Holds one WebKit request through both app consent and OS microphone consent.
@MainActor final class CardTemplateAudioCapture {
    static let preferenceKey = "allowTemplateAudioRecording"
    var presentedChanged: ((Bool) -> Void)?
    var isRequestPending: Bool { completion != nil }
    private var completion: ((WKPermissionDecision) -> Void)?
    private var alert: UIAlertController?
    private var permissionTask: Task<Void, Never>?
    private weak var webView: WKWebView?
    private var generation = UUID()
    private var invalidated = false
    private var declined = false
    private var backgroundObserver: NSObjectProtocol?

    init() {
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.documentChanged() }
        }
    }
    deinit {
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
    }
    func request(in view: WKWebView, type: WKMediaCaptureType, decision: @escaping (WKPermissionDecision) -> Void) {
        // A recording permission never authorizes a camera or a combined request.
        guard type == .microphone, !invalidated, !declined, completion == nil,
              view.window != nil else { decision(.deny); return }
        webView = view
        completion = decision
        generation = UUID()
        presentedChanged?(true)
        if UserDefaults.standard.bool(forKey: Self.preferenceKey) {
            requestMicrophone(persistConsent: false)
            return
        }
        guard var presenter = view.window?.rootViewController else { finish(.deny); return }
        while let next = presenter.presentedViewController { presenter = next }
        guard !(presenter is UIAlertController), !presenter.isBeingDismissed else { finish(.deny); return }
        let dialog = UIAlertController(title: "カードの録音", message: "このカードがマイクで録音しようとしています。許可すると、ほかのカードのテンプレートも録音できます。設定で取り消せます。", preferredStyle: .alert)
        dialog.addAction(UIAlertAction(title: "許可", style: .default) { [weak self] _ in self?.resolveConsent(true) })
        dialog.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { [weak self] _ in self?.resolveConsent(false) })
        alert = dialog
        presenter.present(dialog, animated: true)
    }
    private func resolveConsent(_ accepted: Bool) {
        let token = generation
        let dialog = alert
        alert = nil
        dialog?.dismiss(animated: true) { [weak self] in
            guard let self, self.generation == token, self.completion != nil else { return }
            if accepted { self.requestMicrophone(persistConsent: true) }
            else { self.declined = true; self.finish(.deny) }
        }
    }
    private func requestMicrophone(persistConsent: Bool) {
        let token = generation
        permissionTask = Task {
            let allowed = await AVAudioApplication.requestRecordPermission()
            guard !Task.isCancelled, !invalidated, generation == token, completion != nil else { return }
            guard allowed, webView?.window != nil else { declined = true; finish(.deny); return }
            if persistConsent { UserDefaults.standard.set(true, forKey: Self.preferenceKey) }
            finish(.grant)
        }
    }
    private func finish(_ decision: WKPermissionDecision) {
        guard let callback = completion else { return }
        completion = nil
        permissionTask = nil
        presentedChanged?(false)
        callback(decision)
    }
    func documentChanged() {
        generation = UUID()
        permissionTask?.cancel()
        permissionTask = nil
        let dialog = alert
        alert = nil
        finish(.deny)
        dialog?.dismiss(animated: false)
        webView?.setMicrophoneCaptureState(.none, completionHandler: nil)
    }
    func cancel() { invalidated = true; documentChanged() }
}
