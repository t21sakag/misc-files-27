import SwiftUI
import WebKit
import UniformTypeIdentifiers
import AVFoundation
import AVKit

final class MediaHandler: NSObject, WKURLSchemeHandler {
    let root: URL
    let host: String
    init(root: URL, host: String = "collection") {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.host = host
    }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        do {
            guard let url = task.request.url, url.host == host else { throw URLError(.badURL) }
            // URL.path is decoded once. Resolve symlinks before checking containment.
            let base: URL
            let path: String
            if host == "collection" && url.path.hasPrefix("/_anki/") {
                base = Bundle.main.resourceURL!.appendingPathComponent("backend").standardizedFileURL.resolvingSymlinksInPath()
                path = String(url.path.dropFirst(7))
            } else { base = root; path = url.path }
            let file = base.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
            guard file.path.hasPrefix(base.path + "/"), !file.hasDirectoryPath else { throw URLError(.noPermissionsToReadFile) }
            let data = try Data(contentsOf: file)
            let mime = file.pathExtension == "js" ? "text/javascript" : UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime, "Access-Control-Allow-Origin": "*", "Content-Length": String(data.count)])!
            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
        } catch { task.didFailWithError(error) }
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

struct ReviewerWebView: UIViewRepresentable {
    let html: String
    let css: String
    let cardID: String
    let ordinal: Int
    let typing: TypedAnswerSpec?
    let hideAudioButtons: Bool
    @AppStorage("imageZoom") private var imageZoom = 100
    @AppStorage("centerVertically") private var centerVertically = false
    @AppStorage("reviewZoom") private var reviewZoom = 1.0
    @AppStorage("autoFocusTypeInAnswer") private var autoFocusTypeInAnswer = true
    @AppStorage("dayTheme") private var dayTheme = "1"
    @AppStorage("nightTheme") private var nightTheme = "3"
    @Binding var typedAnswer: String
    let answer: Bool
    let media: URL
    let playTag: (Bool, Int) -> Void
    let reveal: () -> Void
    let scheduling: StudyCard?
    let schedulingRequest: (String, String) async throws -> String
    let schedulingError: (String) -> Void
    var cardAPI: ((String, [String: Any]) async throws -> String)? = nil
    var scriptEventScope: String? = nil
    var cardScriptEvents: [CardScriptEvent] = []
    var scriptEventDelivered: ((UUID) -> Void)? = nil
    var scriptEventError: ((String) -> Void)? = nil
    var scriptDialogChanged: ((Bool) -> Void)? = nil
    var swipeHandler: ((Double, Double) -> Void)? = nil
    var tapHandler: ((Double, Double) -> Void)? = nil
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(MediaHandler(root: media), forURLScheme: "ankimedia")
        configuration.setURLSchemeHandler(MediaHandler(root: Bundle.main.resourceURL!.appendingPathComponent("backend"), host: "backend"), forURLScheme: "ankibundle")
        configuration.userContentController.add(context.coordinator, name: "reviewTap")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.reviewTapScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.add(context.coordinator, name: "typedAnswer")
        configuration.userContentController.add(context.coordinator, name: "reveal")
        configuration.userContentController.add(context.coordinator, name: "schedulingError")
        configuration.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "scheduler")
        configuration.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "droidAPI")
        #if DEBUG
        if UITestIsolation.namespace() != nil {
            configuration.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "templateCaptureStatus")
        }
        #endif
        configuration.userContentController.addUserScript(WKUserScript(source: Self.schedulerBridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator.dialogs
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.reviewPanEnded(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delegate = context.coordinator
        context.coordinator.reviewPan = pan
        view.addGestureRecognizer(pan)
        context.coordinator.webView = view
        view.isOpaque = false
        view.backgroundColor = .systemBackground
        view.scrollView.backgroundColor = .systemBackground
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        view.pageZoom = reviewZoom
        context.coordinator.swipeHandler = swipeHandler
        context.coordinator.tapHandler = tapHandler
        context.coordinator.dialogs.presentedChanged = scriptDialogChanged
        context.coordinator.playTag = playTag
        context.coordinator.cardID = cardID
        context.coordinator.onTyped = { typedAnswer = $0 }
        context.coordinator.reveal = reveal
        if context.coordinator.scheduling?.mutationKey != scheduling?.mutationKey { context.coordinator.timeout?.cancel() }
        context.coordinator.scheduling = scheduling
        context.coordinator.schedulingRequest = schedulingRequest
        context.coordinator.schedulingError = schedulingError
        context.coordinator.isAnswer = answer
        context.coordinator.shouldFocusTyping = !answer && typing != nil && autoFocusTypeInAnswer
        context.coordinator.cardAPI = cardAPI
        context.coordinator.scriptEventScope = scriptEventScope ?? scheduling?.mutationKey
        context.coordinator.pendingScriptEvents = cardScriptEvents
        context.coordinator.scriptEventDelivered = scriptEventDelivered
        context.coordinator.scriptEventError = scriptEventError
        context.coordinator.deliveredScriptEvents.formIntersection(Set(cardScriptEvents.map(\.id)))
        let dark = view.traitCollection.userInterfaceStyle == .dark
        let theme = StudyTheme.resolve(dark: dark, day: dayTheme, night: nightTheme)
        view.backgroundColor = theme.nativeBackground
        view.scrollView.backgroundColor = theme.nativeBackground
        let key = "\(cardID)-\(answer)-\(html)-\(css)-\(dark)-\(hideAudioButtons)-\(imageZoom)-\(centerVertically)-\(autoFocusTypeInAnswer)-\(theme.rawValue)"
        guard context.coordinator.loaded != key else { context.coordinator.deliverScriptEvent(view); return }
        context.coordinator.dialogs.audioCapture.documentChanged()
        context.coordinator.loaded = key
        context.coordinator.tapToken = UUID().uuidString
        let audioLabel = NSRegularExpression.escapedTemplate(for: TypedAnswerMarkup.escape(AppText.localized("音声を再生")))
        var content = "<script>window.__ankiPadTapToken='" + context.coordinator.tapToken + "';</script>" + html.replacingOccurrences(of: #"\[anki:play:([qa]):([0-9]+)\]"#, with: #"<a href="ankiplay://$1/$2" aria-label="\#(audioLabel)">▶︎</a>"#, options: .regularExpression)
        if hideAudioButtons { content = content.replacingOccurrences(of: #"<a href="ankiplay://[^"]+"[^>]*>.*?</a>"#, with: "", options: .regularExpression) }
        if !answer, let typing {
            let answerLabel = TypedAnswerMarkup.escape(AppText.localized("解答を入力"))
            let field = "<input id=\"typeans\" type=\"text\" aria-label=\"\(answerLabel)\" autocomplete=\"off\" autocorrect=\"\(typing.noSuggest ? "off" : "on")\" spellcheck=\"false\" value=\"\(TypedAnswerMarkup.escape(typedAnswer))\" style=\"font-size:\(typing.size)px;font-family:'\(TypedAnswerMarkup.escape(typing.font))';max-width:95%\" oninput=\"window.webkit.messageHandlers.typedAnswer.postMessage({cardID:'\(cardID)',value:this.value})\" onkeydown=\"if(event.key==='Enter'){event.preventDefault();window.webkit.messageHandlers.reveal.postMessage('\(cardID)')}\">"
            content = TypedAnswerMarkup.replace(in: content, with: field)
        }
        let needsMath = html.contains("\\(") || html.contains("\\[") || html.contains("$$")
        let math = needsMath ? """
        <script src="ankibundle://backend/js/mathjax.js"></script>
        <script>window.MathJax.loader.paths.mathjax='ankibundle://backend/js/vendor/mathjax';</script>
        <script src="ankibundle://backend/js/vendor/mathjax/tex-chtml-full.js"></script>
        """ : ""
        view.loadHTMLString("""
        <!doctype html><html class="mobile ios \(dark ? "night-mode" : "")"><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <base href="ankimedia://collection/">
        <link rel="stylesheet" href="ankibundle://backend/css/root-vars.css">
        <link rel="stylesheet" href="ankibundle://backend/css/reviewer_extras.css">
        <style>:root{color-scheme:light dark}body{margin:24px;font-family:-apple-system;font-size:24px;overflow-wrap:anywhere}img{max-width:100%;height:auto}audio,video{max-width:100%}.cloze{font-weight:bold;color:#3478f6}.typeGood{background:#aaffaa;color:#000}.typeBad{background:#ffaaaa;color:#000}.typeMissed{background:#ccc;color:#000}\(StudyTheme.cardCSS)\(css)
        img{zoom:\(Double(min(300, max(50, imageZoom))) / 100)}
        body.vertically_centered{min-height:calc(100vh - 48px);display:flex;flex-direction:column;justify-content:center}
        body.vertically_centered>#qa{width:100%;flex-shrink:0}
        </style>
        <script src="ankibundle://backend/js/ankidroid-js-api.js"></script>
        <script src="ankibundle://backend/js/jquery.min.js"></script>
        <script src="ankibundle://backend/js/reviewer_extras_bundle.js"></script>
        \(math)
        </head><body data-study-theme="\(theme.rawValue)" class="card card\(ordinal + 1) \(centerVertically ? "vertically_centered" : "") \(theme.cardClasses)"><div id="qa">\(content)</div>
        <script>if(window.MathJax?.startup?.promise){window.MathJax.startup.promise.then(()=>window.MathJax.typesetPromise()).catch(()=>{});}</script>
        </body></html>
        """, baseURL: URL(string: "ankimedia://collection/"))
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        coordinator.tapHandler = nil
        view.configuration.userContentController.removeScriptMessageHandler(forName: "reviewTap")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "typedAnswer")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "reveal")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "schedulingError")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "scheduler", contentWorld: .page)
        view.configuration.userContentController.removeScriptMessageHandler(forName: "droidAPI", contentWorld: .page)
        #if DEBUG
        view.configuration.userContentController.removeScriptMessageHandler(forName: "templateCaptureStatus", contentWorld: .page)
        #endif
        coordinator.dialogs.cancel()
        coordinator.timeout?.cancel()
    }

    private static let schedulerBridge: String = {
        let missingAction = String(decoding: (try? JSONEncoder().encode(AppText.localized("カードに userJs{number} が定義されていません。"))) ?? Data("\"\"".utf8), as: UTF8.self)
        return """
    (()=>{
      window.userAction = number => {
        const action=globalThis['userJs'+number];
        if(typeof action==='function') action();
        else throw new Error(\(missingAction).replace('{number}', String(number)));
      };
      window.showHint = () => document.querySelector("a.hint:not([style*='display: none'])")?.click();
      window.showAllHints = () => document.querySelectorAll('a.hint').forEach(hint=>hint.click());
      window.ankidroid = window.ankidroid || {};
      window.ankidroid.userAction = window.userAction;
      window.ankidroid.showHint = window.showHint;
      window.ankidroid.showAllHints = window.showAllHints;
      window.ankiPadUserAction = value => {
        const number=Number(value);
        if(Number.isInteger(number)&&number>=1&&number<=9) window.userAction(number);
      };
      window.ankiPadShowHint = value => value==='all' ? window.showAllHints() : window.showHint();
      const callbacks = {ankiSearchCard:[], ankiSttResult:[]};
      window.addHook = (name, callback) => { if(callbacks[name] && typeof callback === 'function') callbacks[name].push(callback); };
      window.ankiSearchCard = json => { const result=JSON.parse(json); for(const callback of callbacks.ankiSearchCard) callback(result); };
      window.ankiSttResult = json => {
        const result=JSON.parse(json);
        if(typeof result.value === 'string') { try { result.value=JSON.parse(result.value); } catch(_) {} }
        for(const callback of callbacks.ankiSttResult) callback(result);
      };
      const originalFetch = window.fetch.bind(window);
      window.fetch = async (url, options={}) => {
        const path = String(url);
        const method = path.split('/').pop();
        if (options.method === 'POST' && path.startsWith('/jsapi/')) {
          try {
            const request = JSON.parse(options.body || '{}');
            const result = await window.webkit.messageHandlers.droidAPI.postMessage({endpoint:method,request});
            return new Response(result,{status:200,headers:{'Content-Type':'application/json'}});
          } catch(error) { return new Response(String(error),{status:500}); }
        }
        if (options.method === 'POST' && ['getSchedulingStatesWithContext','setSchedulingStates'].includes(method)) {
          const bytes = new Uint8Array(options.body || []); let str='';
          for(let offset=0;offset<bytes.length;offset+=8192) str+=String.fromCharCode(...bytes.subarray(offset,offset+8192));
          try { const result=await window.webkit.messageHandlers.scheduler.postMessage({method,data:btoa(str)});
            return new Response(Uint8Array.from(atob(result),c=>c.charCodeAt(0)),{status:200});
          } catch(error) { return new Response(String(error),{status:500}); }
        }
        return originalFetch(url,options);
      };
    })();
    """
    }()
    static let reviewTapScript = #"""
    (()=>{
      let pending;
      document.addEventListener('pointerdown',()=>clearTimeout(pending),true);
      document.addEventListener('click',event=>{
        clearTimeout(pending);
        if(!event.isTrusted||event.defaultPrevented||event.detail!==1||event.button!==0)return;
        if(event.composedPath().some(node=>node instanceof Element&&node.matches('a,button,input,select,textarea,label,summary,[contenteditable],[role="button"],audio,video,iframe,canvas')))return;
        if(!getSelection()?.isCollapsed)return;
        const x=event.clientX/innerWidth,y=event.clientY/innerHeight,token=window.__ankiPadTapToken;
        pending=setTimeout(()=>{
          if(!getSelection()?.isCollapsed||token!==window.__ankiPadTapToken)return;
          window.webkit.messageHandlers.reviewTap.postMessage({x,y,token});
        },400);
      });
    })();
    """#
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKScriptMessageHandlerWithReply, UIGestureRecognizerDelegate {
        weak var webView: WKWebView?
        var scheduling: StudyCard?
        var schedulingRequest: ((String, String) async throws -> String)?
        var schedulingError: ((String) -> Void)?
        weak var reviewPan: UIPanGestureRecognizer?
        var swipeHandler: ((Double, Double) -> Void)?
        var tapHandler: ((Double, Double) -> Void)?
        var tapToken = ""
        @objc func reviewPanEnded(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .ended else { return }
            let value = gesture.translation(in: gesture.view)
            swipeHandler?(Double(value.x), Double(value.y))
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer !== reviewPan || swipeHandler != nil
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer === reviewPan || otherGestureRecognizer === reviewPan
        }
        let dialogs = CardScriptDialogs()
        var cardAPI: ((String, [String: Any]) async throws -> String)?
        var scriptEventScope: String?
        var pendingScriptEvents: [CardScriptEvent] = []
        var deliveredScriptEvents: Set<UUID> = []
        var scriptEventDelivered: ((UUID) -> Void)?
        var scriptEventError: ((String) -> Void)?
        var isAnswer = false
        var lastMutationKey: String?
        var timeout: Task<Void, Never>?
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
            #if DEBUG
            if message.name == "templateCaptureStatus", UITestIsolation.namespace() != nil, message.frameInfo.isMainFrame {
                let state: String
                switch webView?.microphoneCaptureState {
                case .some(.none): state = "none"
                case .some(.active): state = "active"
                case .some(.muted): state = "muted"
                default: state = "unavailable"
                }
                replyHandler(["state": state, "backgroundStops": dialogs.audioCapture.backgroundStopCount], nil)
                return
            }
            #endif
            if message.name == "droidAPI" {
                guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any],
                      let endpoint = body["endpoint"] as? String, let request = body["request"] as? [String: Any], let cardAPI else {
                    replyHandler(nil, "AnkiDroid API is unavailable in this view"); return
                }
                Task { @MainActor in
                    do {
                        var nativeRequest = request
                        if let view = self.webView { nativeRequest["__nativeNightMode"] = view.traitCollection.userInterfaceStyle == .dark }
                        let output = try await cardAPI(endpoint, nativeRequest)
                        if ["enableHorizontalScrollbar", "enableVerticalScrollbar"].contains(endpoint),
                           let data = output.data(using: .utf8), let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           response["success"] as? Bool == true, response["value"] as? Bool == true {
                            let enabled = (request["data"] as? String ?? String(describing: request["data"] ?? false)).lowercased() == "true"
                            if endpoint == "enableHorizontalScrollbar" { self.webView?.scrollView.showsHorizontalScrollIndicator = enabled }
                            else { self.webView?.scrollView.showsVerticalScrollIndicator = enabled }
                        }
                        replyHandler(output, nil)
                    }
                    catch { replyHandler(nil, error.localizedDescription) }
                }
                return
            }
            guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any],
                  let method = body["method"] as? String, let data = body["data"] as? String,
                  ["getSchedulingStatesWithContext", "setSchedulingStates"].contains(method), let schedulingRequest else {
                replyHandler(nil, "Invalid scheduling request"); return
            }
            Task { @MainActor in
                do { replyHandler(try await schedulingRequest(method, data), nil) }
                catch { replyHandler(nil, error.localizedDescription) }
            }
        }
        func deliverScriptEvent(_ view: WKWebView) {
            guard !view.isLoading else { return }
            for event in pendingScriptEvents where event.mutationKey == scriptEventScope && !deliveredScriptEvents.contains(event.id) {
                guard let data = try? JSONSerialization.data(withJSONObject: [event.json]), let argument = String(data: data, encoding: .utf8) else { continue }
                deliveredScriptEvents.insert(event.id)
                view.evaluateJavaScript("window.\(event.kind.rawValue)?.(\(argument)[0]);") { [weak self] _, error in
                    if let error { self?.scriptEventError?(error.localizedDescription) }
                    // A throwing card hook must not replay earlier hook side effects.
                    self?.scriptEventDelivered?(event.id)
                }
            }
        }
        #if DEBUG
        private func traceTypingFocus(_ phase: String, view: WKWebView, domFocused: Bool? = nil, error: Error? = nil) {
            guard UITestIsolation.namespace() != nil,
                  ProcessInfo.processInfo.arguments.contains("--uitest-typing-focus") else { return }
            func firstResponder(in root: UIView) -> UIView? {
                if root.isFirstResponder { return root }
                for child in root.subviews { if let found = firstResponder(in: child) { return found } }
                return nil
            }
            let native = view.window.flatMap { firstResponder(in: $0) }
            // Only structural state from the synthetic test. No card/input text.
            let nativeType = native.map { String(describing: type(of: $0)) } ?? "none"
            let nativeInWeb = native.map { $0 === view || $0.isDescendant(of: view) } ?? false
            let errorIdentity = error.map { ($0 as NSError).domain + ":" + String(($0 as NSError).code) } ?? "none"
            NSLog("typing.focus.trace phase=%@ window=%d key=%d enabled=%d native=%@ inWeb=%d dom=%@ error=%@",
                  phase, view.window != nil ? 1 : 0, view.window?.isKeyWindow == true ? 1 : 0,
                  view.isUserInteractionEnabled ? 1 : 0, nativeType, nativeInWeb ? 1 : 0,
                  domFocused.map(String.init) ?? "unobserved", errorIdentity)
        }
        #endif
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if shouldFocusTyping {
                #if DEBUG
                if UITestIsolation.namespace() != nil, ProcessInfo.processInfo.arguments.contains("--uitest-typing-focus") {
                    traceTypingFocus("before-focus", view: webView)
                    webView.evaluateJavaScript("(()=>{const field=document.getElementById('typeans');field?.focus();return !!field && document.activeElement===field;})()") { [weak self, weak webView] result, error in
                        if let webView { self?.traceTypingFocus("after-focus", view: webView, domFocused: result as? Bool, error: error) }
                    }
                } else {
                    webView.evaluateJavaScript("document.getElementById('typeans')?.focus();")
                }
                #else
                webView.evaluateJavaScript("document.getElementById('typeans')?.focus();")
                #endif
            }
            deliverScriptEvent(webView)
            guard !isAnswer, let card = scheduling, !card.customScheduling.isEmpty, card.mutationKey != lastMutationKey else { return }
            lastMutationKey = card.mutationKey
            let script = "(()=>{anki.mutateNextCardStates('\(card.mutationKey)',async(states,customData,ctx)=>{\(card.customScheduling)\n}).catch(error=>window.webkit.messageHandlers.schedulingError.postMessage({key:'\(card.mutationKey)',message:String(error)}));return null;})();"
            webView.evaluateJavaScript(script) { [weak self] _, error in if let error { self?.schedulingError?(error.localizedDescription) } }
            timeout?.cancel()
            timeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 15_000_000_000); self?.schedulingError?(AppText.localized("実行時間を超えました。")) } catch {}
            }
        }
        var cardID = ""
        var shouldFocusTyping = false
        var onTyped: ((String) -> Void)?
        var reveal: (() -> Void)?
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "reviewTap" {
                guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any],
                      body["token"] as? String == tapToken, let x = body["x"] as? Double, let y = body["y"] as? Double,
                      x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else { return }
                tapHandler?(x, y)
                return
            }
            guard message.frameInfo.isMainFrame else { return }
            if message.name == "typedAnswer", let body = message.body as? [String: Any], body["cardID"] as? String == cardID,
               let value = body["value"] as? String, value.utf8.count < 1_000_000 { onTyped?(value) }
            if message.name == "reveal", message.body as? String == cardID { reveal?() }
            if message.name == "schedulingError", let body = message.body as? [String: Any], body["key"] as? String == scheduling?.mutationKey,
               let error = body["message"] as? String { schedulingError?(error) }
        }
        var loaded = ""
        private var externalLaunchDenials = 0
        var playTag: ((Bool, Int) -> Void)?
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if url.scheme == "ankiplay", let index = Int(url.lastPathComponent), let side = url.host {
                if action.sourceFrame.isMainFrame { playTag?(side == "a", index) }
                decisionHandler(.cancel)
                return
            }
            if action.targetFrame?.isMainFrame == false, ["https", "http", "data", "blob"].contains(url.scheme ?? "") {
                decisionHandler(.allow); return
            }
            if ["ankimedia", "about"].contains(url.scheme ?? "") { decisionHandler(.allow); return }
            decisionHandler(.cancel)
            switch CardExternalLaunchPolicy.decision(for: url, allowed: UserDefaults.standard.bool(forKey: "allowCardExternalLaunch")) {
            case .browser, .application:
                UIApplication.shared.open(url, options: [:]) { [weak self] opened in
                    if !opened { self?.scriptEventError?(AppText.localized("このリンクを開けるアプリが見つかりませんでした。")) }
                }
            case .denied:
                if externalLaunchDenials < 2 {
                    externalLaunchDenials += 1
                    scriptEventError?(AppText.localized("カードから外部アプリを開く操作は許可されていません。「設定」で変更できます。"))
                }
            case .unsupported: break
            }
        }
    }
}
