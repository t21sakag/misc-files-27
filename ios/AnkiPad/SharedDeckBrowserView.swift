import SwiftUI
import WebKit

struct SharedDeckBrowserView: View {
    @ObservedObject var model: StudyModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controls = SharedDeckBrowserState()
    @State private var pending: URL?
    @State private var importing = false
    @State private var confirmImport = false
    @State private var error: String?
    private var startURL: URL {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest-shared-decks") { return URL(string: "http://127.0.0.1:18892/shared")! }
        #endif
        return URL(string: "https://ankiweb.net/shared/decks")!
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SharedDeckWebView(url: startURL, state: controls, downloaded: { clearPending(); pending = $0; confirmImport = true }, failed: { error = $0 })
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--uitest-shared-decks"), UITestIsolation.namespace() != nil {
                    Text("Transport state").font(.caption2).accessibilityIdentifier("shared-browser-state")
                        .accessibilityValue(controls.diagnostics.joined(separator: " | "))
                }
                #endif
                if controls.downloading || importing || controls.loading {
                    ProgressView(importing ? AppText.localized("デッキを取り込んでいます…") : controls.downloading ? AppText.localized("ダウンロードしています…") : AppText.localized("ページを読み込んでいます…")).padding()
                }
            }
            .studyThemeSurface().navigationTitle(AppText.localized("共有デッキ")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppText.localized("閉じる")) { controls.cancel(); clearPending(); dismiss() }.disabled(importing).accessibilityIdentifier("shared-decks-close") }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { controls.webView?.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!controls.canGoBack || importing || controls.downloading).accessibilityIdentifier("shared-browser-back")
                    Button { controls.webView?.load(URLRequest(url: startURL)) } label: { Image(systemName: "house") }.disabled(importing || controls.downloading)
                    if pending != nil && !importing { Button(AppText.localized("取り込みを確認")) { confirmImport = true } }
                    if controls.downloading { Button(AppText.localized("中止")) { controls.cancel() } }
                    else { Button { controls.webView?.reload() } label: { Image(systemName: "arrow.clockwise") }.disabled(importing) }
                }
            }
            .confirmationDialog(AppText.localized("ダウンロードしたデッキを取り込みますか？"), isPresented: $confirmImport, titleVisibility: .visible) {
                Button(AppText.localized("取り込む")) { importPending() }.accessibilityIdentifier("shared-deck-import")
                Button(AppText.localized("キャンセル"), role: .cancel) { clearPending() }
            } message: { Text(pending?.lastPathComponent ?? "") }
            .alert(AppText.localized("共有デッキを開けませんでした"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(AppText.localized("閉じる"), role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
            .interactiveDismissDisabled(importing || controls.downloading)
            .onDisappear { controls.cancel(); if !importing { clearPending() } }
        }
    }
    private func clearPending() {
        if let pending { try? FileManager.default.removeItem(at: pending.deletingLastPathComponent()) }
        pending = nil
    }
    private func importPending() {
        guard let local = pending, !importing else { return }
        guard !model.busy else { error = AppText.localized("処理が終わってからデッキを取り込んでください。"); return }
        importing = true; model.busy = true
        Task {
            defer { clearPending(); importing = false; model.busy = false }
            do {
                try await model.engine.importPackage(local)
                model.decks = try await model.engine.decks()
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
@MainActor final class SharedDeckBrowserState: ObservableObject {
    @Published var canGoBack = false
    @Published var downloading = false
    @Published var loading = false
    #if DEBUG
    @Published var diagnostics: [String] = []
    #endif
    weak var webView: WKWebView?
    var cancel: () -> Void = {}
}
struct SharedDeckWebView: UIViewRepresentable {
    @AppStorage("dayTheme") private var dayTheme = "1"
    @AppStorage("nightTheme") private var nightTheme = "3"
    @Environment(\.colorScheme) private var colorScheme
    private var theme: StudyTheme { StudyTheme.resolve(dark: colorScheme == .dark, day: dayTheme, night: nightTheme) }
    let url: URL
    let state: SharedDeckBrowserState
    let downloaded: (URL) -> Void
    let failed: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(state: state, downloaded: downloaded, failed: failed) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        applyTheme(view)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        context.coordinator.observeHistory(view)
        state.webView = view
        state.cancel = { [weak coordinator = context.coordinator] in coordinator?.cancel() }
        view.load(URLRequest(url: url))
        return view
    }
    private func applyTheme(_ view: WKWebView) {
        view.overrideUserInterfaceStyle = theme.backendIsDark ? .dark : .light
        view.backgroundColor = theme.nativeBackground
        view.scrollView.backgroundColor = theme.nativeBackground
    }
    func updateUIView(_ view: WKWebView, context: Context) { applyTheme(view) }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) { coordinator.cancel(); coordinator.dialogs.cancel(); view.stopLoading() }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKDownloadDelegate, WKUIDelegate {
        let state: SharedDeckBrowserState
        let downloaded: (URL) -> Void
        let failed: (String) -> Void
        let dialogs = CardScriptDialogs()
        private var active: WKDownload?
        private func record(_ event: String) {
            #if DEBUG
            guard ProcessInfo.processInfo.arguments.contains("--uitest-shared-decks"), UITestIsolation.namespace() != nil else { return }
            state.diagnostics.append(event)
            if state.diagnostics.count > 16 { state.diagnostics.removeFirst() }
            #endif
        }
        private var historyObservation: NSKeyValueObservation?
        func observeHistory(_ view: WKWebView) {
            historyObservation = view.observe(\.canGoBack, options: [.initial, .new]) { [weak state = self.state] view, _ in
                DispatchQueue.main.async { state?.canGoBack = view.canGoBack }
            }
        }
        private var destination: URL?
        // WebKit reports a frame-policy interruption when navigation becomes a
        // download. Keep this scoped to a policy we actually selected; genuine
        // navigation and WKDownload failures must still reach the user.
        private var downloadNavigationURL: URL?
        private func expectedDownloadInterruption(_ error: Error) -> Bool {
            let error = error as NSError
            guard error.domain == "WebKitErrorDomain", error.code == 102,
                  let expected = downloadNavigationURL else { return false }
            let failing = (error.userInfo[NSURLErrorFailingURLErrorKey] as? URL)
                ?? (error.userInfo[NSURLErrorFailingURLStringErrorKey] as? String).flatMap(URL.init(string:))
            return failing == nil || failing == expected
        }
        init(state: SharedDeckBrowserState, downloaded: @escaping (URL) -> Void, failed: @escaping (String) -> Void) { self.state = state; self.downloaded = downloaded; self.failed = failed }
        func cancel() {
            let download = active
            active = nil; state.downloading = false; state.loading = false
            if let destination { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()) }
            destination = nil
            download?.cancel { _ in }
        }
        private func attach(_ download: WKDownload) {
            guard active == nil else { download.cancel { _ in }; return }
            record("download attached")
            active = download; state.downloading = true; state.loading = false; download.delegate = self
        }
        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { attach(download) }
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { attach(download) }
        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            record("destination " + suggestedFilename)
            guard active === download else { completionHandler(nil); return }
            let name = (suggestedFilename as NSString).lastPathComponent
            guard (name as NSString).pathExtension.lowercased() == "apkg" else { completionHandler(nil); cancel(); failed(AppText.localized("共有デッキ（.apkg）を選んでください。")); return }
            do {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shared-deck-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let local = folder.appendingPathComponent(name)
                destination = local
                completionHandler(local)
            } catch { completionHandler(nil); cancel(); failed(error.localizedDescription) }
        }
        func downloadDidFinish(_ download: WKDownload) {
            guard active === download, let local = destination else { return }
            record("download finished")
            active = nil; destination = nil; state.downloading = false; state.loading = false
            downloaded(local)
        }
        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            guard active === download else { return }
            record("download failed: " + error.localizedDescription)
            cancel(); failed(error.localizedDescription)
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let target = action.request.url else { decisionHandler(.cancel); return }
            let scheme = target.scheme?.lowercased() ?? ""
            var trusted = scheme == "https" && (target.host == "ankiweb.net" || target.host?.hasSuffix(".ankiweb.net") == true)
            if scheme == "blob", action.shouldPerformDownload, action.sourceFrame.isMainFrame,
               let source = action.sourceFrame.request.url {
                trusted = source.scheme == "https" && (source.host == "ankiweb.net" || source.host?.hasSuffix(".ankiweb.net") == true)
            }
            #if DEBUG
            trusted = trusted || (ProcessInfo.processInfo.arguments.contains("--uitest-shared-decks") && target.host == "127.0.0.1" && target.port == 18892)
            #endif
            record("action " + target.path + " download=" + String(action.shouldPerformDownload))
            if trusted {
                if action.shouldPerformDownload { downloadNavigationURL = target }
                decisionHandler(action.shouldPerformDownload ? .download : .allow)
            }
            else { if action.navigationType == .linkActivated && ["http", "https"].contains(scheme) { UIApplication.shared.open(target) }; decisionHandler(.cancel) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")?
                .split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let shouldDownload = disposition == "attachment" || !response.canShowMIMEType
            record("response " + (response.response.url?.path ?? "") + " show=" + String(response.canShowMIMEType) + " disposition=" + (disposition ?? "none"))
            if shouldDownload { downloadNavigationURL = response.response.url }
            decisionHandler(shouldDownload ? .download : .allow)
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            if webView.url != downloadNavigationURL { downloadNavigationURL = nil }
            state.loading = true
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { state.loading = false; state.canGoBack = webView.canGoBack }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            state.loading = false
            record("navigation error " + (error as NSError).domain + ":" + String((error as NSError).code))
            if !expectedDownloadInterruption(error), !((error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled) { failed(error.localizedDescription) }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            state.loading = false
            record("navigation error " + (error as NSError).domain + ":" + String((error as NSError).code))
            if !expectedDownloadInterruption(error), !((error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled) { failed(error.localizedDescription) }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { if action.targetFrame == nil { webView.load(action.request) }; return nil }
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) { dialogs.webView(webView, runJavaScriptAlertPanelWithMessage: message, initiatedByFrame: frame, completionHandler: completionHandler) }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) { dialogs.webView(webView, runJavaScriptConfirmPanelWithMessage: message, initiatedByFrame: frame, completionHandler: completionHandler) }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) { dialogs.webView(webView, runJavaScriptTextInputPanelWithPrompt: prompt, defaultText: defaultText, initiatedByFrame: frame, completionHandler: completionHandler) }
    }
}
