import SwiftUI
import WebKit

struct BackendPageRequest: Identifiable {
    let id = UUID()
    let path: String
    let title: String
    var noteIDs: [String] = []
}
struct BackendPageView: View {
    @ObservedObject var model: StudyModel
    let request: BackendPageRequest
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var server: StaticAssetServer?
    @State private var url: URL?
    @State private var error: String?
    @State private var closeRequest: (() -> Void)?
    @State private var showDiscard = false
    @State private var saveRequest: (() -> Void)?
    var body: some View {
        NavigationStack {
            Group {
                if let url { BackendWebView(url: url, model: model, noteIDs: request.noteIDs, close: finish, ready: { closeRequest = $0 }, saveReady: { saveRequest = $0 }) }
                else if let error { ContentUnavailableView("画面を開けませんでした", systemImage: "exclamationmark.triangle", description: Text(error)) }
                else { ProgressView() }
            }
            .navigationTitle(request.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if request.path.hasPrefix("image-occlusion/") {
                    ToolbarItem(placement: .primaryAction) { Button("保存") { saveRequest?() }.disabled(saveRequest == nil).accessibilityIdentifier("occlusion-save") }
                }
                ToolbarItem(placement: .confirmationAction) { Button("閉じる") {
                    if request.path.hasPrefix("image-occlusion/") { showDiscard = true }
                    else if let closeRequest { closeRequest() } else { finish() }
                }.accessibilityIdentifier("backend-close") } }
            .interactiveDismissDisabled(request.path.hasPrefix("deck-options") || request.path.hasPrefix("image-occlusion/"))
            .alert("マスクの変更を破棄しますか？", isPresented: $showDiscard) {
                Button("編集を続ける", role: .cancel) {}.accessibilityIdentifier("occlusion-continue")
                Button("破棄", role: .destructive) { finish() }.accessibilityIdentifier("occlusion-discard")
            } message: { Text("保存していない画像穴埋めの変更は失われます。") }
            .task {
                do {
                    let server = StaticAssetServer(root: Bundle.main.resourceURL!.appendingPathComponent("backend"))
                    self.server = server
                    let base = try await server.start()
                    url = URL(string: "/" + request.path, relativeTo: base)?.absoluteURL
                } catch { self.error = error.localizedDescription }
            }
        }
    }
    private func finish() {
        if let onClose { onClose() } else { dismiss() }
        model.refreshAfterEditing()
    }
}

struct BackendWebView: UIViewRepresentable {
    let url: URL
    let model: StudyModel
    let noteIDs: [String]
    let close: () -> Void
    let ready: (@escaping () -> Void) -> Void
    let saveReady: (@escaping () -> Void) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(model: model, origin: url, noteIDs: noteIDs, close: close) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "ankiBackend")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.load(URLRequest(url: url))
        DispatchQueue.main.async {
            saveReady { [weak view] in
                view?.evaluateJavaScript("if (typeof globalThis.anki?.imageOcclusion?.save === 'function') { globalThis.anki.imageOcclusion.save(); } else { throw new Error('画像穴埋めの準備ができていません。'); }") { _, error in
                    if let error { context.coordinator.model.error = error.localizedDescription }
                }
            }
            ready { [weak view] in
                guard let view else { context.coordinator.close(); return }
                view.evaluateJavaScript("typeof globalThis.anki?.deckOptionsPendingChanges === 'function'") { value, _ in
                    if value as? Bool == true { view.evaluateJavaScript("globalThis.anki.deckOptionsPendingChanges()", completionHandler: nil) }
                    else { context.coordinator.close() }
                }
            }
        }
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "ankiBackend", contentWorld: .page)
    }
    private static let bridge = """
    (() => {
      const originalFetch = window.fetch.bind(window);
      window.fetch = async (input, options = {}) => {
        const url = new URL(typeof input === 'string' ? input : input.url, location.href);
        if (url.origin === location.origin && url.pathname.startsWith('/_anki/') && options.method === 'POST') {
          const bytes = new Uint8Array(options.body || []);
          let string = ''; for (let offset = 0; offset < bytes.length; offset += 8192) string += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
          try {
            const result = await window.webkit.messageHandlers.ankiBackend.postMessage({method: url.pathname.slice(7).replace(/[A-Z]/g, letter => '_' + letter.toLowerCase()), data: btoa(string)});
            const binary = atob(result);
            return new Response(Uint8Array.from(binary, c => c.charCodeAt(0)), {status:200, headers:{'Content-Type':'application/binary'}});
          } catch(error) { return new Response(String(error), {status:500}); }
        }
        return originalFetch(input, options);
      };
      window.bridgeCommand = (command, callback) => window.webkit.messageHandlers.ankiBackend.postMessage({command}).then(value => callback?.(value));
    })();
    """
    @MainActor final class Coordinator: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate, WKUIDelegate {
        let model: StudyModel
        let origin: URL
        let noteIDs: [String]
        private let completeClose: () -> Void
        private var closed = false
        func close() {
            guard !closed else { return }
            closed = true
            completeClose()
        }
        init(model: StudyModel, origin: URL, noteIDs: [String], close: @escaping () -> Void) { self.model = model; self.origin = origin; self.noteIDs = noteIDs; self.completeClose = close }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
            guard message.frameInfo.isMainFrame,
                  message.frameInfo.request.url?.host == origin.host,
                  message.frameInfo.request.url?.port == origin.port,
                  let body = message.body as? [String: Any] else { replyHandler(nil, "Invalid application frame"); return }
            if let command = body["command"] as? String {
                if command.hasPrefix("browserSearch:") {
                    model.browserSearch = String(command.dropFirst("browserSearch:".count)).trimmingCharacters(in: .whitespaces)
                    close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.model.showingBrowser = true }
                }
                replyHandler("", nil)
                return
            }
            guard let method = body["method"] as? String, let input = body["data"] as? String else { replyHandler(nil, "Invalid request"); return }
            Task { @MainActor in
                do {
                    if method == "deck_options_ready" { replyHandler("", nil); return }
                    if ["deck_options_require_close", "import_done", "import_dialog_require_close", "close_edit_current", "close_add_cards"].contains(method) { close(); replyHandler("", nil); return }
                    if method == "ask_user" || method == "show_message_box" {
                        let request = try await model.engine.call("_decode/" + method, ["data": input])
                        let response = await dialog(title: request["title"] as? String ?? "AnkiPad", text: request["text"] as? String ?? "", confirm: method == "ask_user")
                        let encoded = try await model.engine.call("_encode/" + method, method == "ask_user" ? ["val": response] : [:])
                        replyHandler(encoded["data"] as? String ?? "", nil)
                        return
                    }
                    if method == "get_change_notetype_info" && !noteIDs.isEmpty {
                        let request = try await model.engine.call("_decode/" + method, ["data": input])
                        var response = try await model.engine.call("NotetypesService.GetChangeNotetypeInfo", request)
                        var mapping = response["input"] as? [String: Any] ?? [:]
                        mapping["noteIds"] = noteIDs
                        response["input"] = mapping
                        let encoded = try await model.engine.call("_encode/" + method, response)
                        replyHandler(encoded["data"] as? String ?? "", nil)
                        return
                    }
                    if method == "change_notetype" {
                        let request = try await model.engine.call("_decode/" + method, ["data": input])
                        guard !noteIDs.isEmpty, Set(request["noteIds"] as? [String] ?? []) == Set(noteIDs) else { throw EngineError(message: "変更対象のノートが一致しません。") }
                        try await model.engine.backup()
                        let response = try await model.engine.call("NotetypesService.ChangeNotetype", request)
                        let encoded = try await model.engine.call("_encode/" + method, response)
                        replyHandler(encoded["data"] as? String ?? "", nil)
                        close()
                        return
                    }
                    if method == "search_in_browser" {
                        let search = try await model.engine.call("_decode/" + method, ["data": input])
                        let built = try await model.engine.call("SearchService.BuildSearchString", search)
                        model.browserSearch = built["val"] as? String ?? ""
                        close()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.model.showingBrowser = true }
                        replyHandler("", nil)
                        return
                    }
                    if method == "open_link" {
                        let request = try await model.engine.call("_decode/" + method, ["data": input])
                        if let value = request["val"] as? String, let link = URL(string: value), ["http", "https"].contains(link.scheme ?? "") { _ = await UIApplication.shared.open(link) }
                        replyHandler("", nil)
                        return
                    }
                    if ["update_deck_configs", "update_image_occlusion_note"].contains(method) { try await model.engine.backup() }
                    let output = try await model.engine.webProtobuf(method, input: input)
                    replyHandler(output, nil)
                    if ["update_deck_configs", "add_image_occlusion_note", "update_image_occlusion_note"].contains(method) { close() }
                } catch { replyHandler(nil, error.localizedDescription) }
            }
        }
        private func dialog(title: String, text: String, confirm: Bool) async -> Bool {
            await withCheckedContinuation { continuation in
                guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      var presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { continuation.resume(returning: false); return }
                while let presented = presenter.presentedViewController { presenter = presented }
                let alert = UIAlertController(title: title, message: text, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in continuation.resume(returning: true) })
                if confirm { alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { _ in continuation.resume(returning: false) }) }
                StudyMotion.present(alert, from: presenter)
            }
        }
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            Task { @MainActor in _ = await dialog(title: "AnkiPad", text: message, confirm: false); completionHandler() }
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            Task { @MainActor in completionHandler(await dialog(title: "AnkiPad", text: message, confirm: true)) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if url.host == origin.host && url.port == origin.port { decisionHandler(.allow) }
            else {
                if action.navigationType == .linkActivated && ["https", "http"].contains(url.scheme ?? "") { UIApplication.shared.open(url) }
                decisionHandler(.cancel)
            }
        }
    }
}
