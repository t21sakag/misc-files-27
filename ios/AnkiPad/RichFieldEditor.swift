import SwiftUI
import WebKit

@MainActor final class RichFieldCommands: ObservableObject {
    weak var webView: WKWebView?
    func perform(_ command: String, value: String? = nil) {
        guard let data = try? JSONSerialization.data(withJSONObject: [command, value ?? ""]), let args = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("(()=>{const [command,value]=\(args);const field=document.getElementById('field');field.focus();document.execCommand(command,false,value);window.reportField();})();", completionHandler: nil)
    }
}
struct RichFieldEditor: View {
    @Binding var text: String
    let media: URL
    let label: String
    var fontName = "Arial"
    var fontSize = 20
    var rtl = false
    @StateObject private var commands = RichFieldCommands()
    @State private var linking = false
    @State private var link = ""
    var body: some View {
        VStack(spacing: 5) {
            ScrollView(.horizontal) {
                HStack {
                    formatButton("太字", icon: "bold", command: "bold")
                    formatButton("斜体", icon: "italic", command: "italic")
                    formatButton("下線", icon: "underline", command: "underline")
                    formatButton("取り消し線", icon: "strikethrough", command: "strikeThrough")
                    formatButton("下付き", icon: "textformat.subscript", command: "subscript")
                    formatButton("上付き", icon: "textformat.superscript", command: "superscript")
                    formatButton("箇条書き", icon: "list.bullet", command: "insertUnorderedList")
                    formatButton("番号付きリスト", icon: "list.number", command: "insertOrderedList")
                    Button { linking = true } label: { Image(systemName: "link") }.accessibilityLabel("リンクを挿入")
                    formatButton("書式を解除", icon: "textformat", command: "removeFormat")
                    formatButton("取り消す", icon: "arrow.uturn.backward", command: "undo")
                    formatButton("やり直す", icon: "arrow.uturn.forward", command: "redo")
                }.buttonStyle(.borderless)
            }
            RichFieldWebView(text: $text, media: media, label: label, fontName: fontName, fontSize: fontSize, rtl: rtl, commands: commands).frame(minHeight: 160)
        }
        .alert("リンクを挿入", isPresented: $linking) {
            TextField("https://…", text: $link).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("挿入") { if let url = URL(string: link), ["http", "https", "mailto"].contains(url.scheme ?? "") { commands.perform("createLink", value: link) } }
            Button("キャンセル", role: .cancel) {}
        }
    }
    private func formatButton(_ label: String, icon: String, command: String) -> some View {
        Button { commands.perform(command) } label: { Image(systemName: icon).frame(minWidth: 28, minHeight: 32) }.accessibilityLabel(label)
    }
}
private struct RichFieldWebView: UIViewRepresentable {
    @Binding var text: String
    let media: URL
    let label: String
    let fontName: String
    let fontSize: Int
    let rtl: Bool
    let commands: RichFieldCommands
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(MediaHandler(root: media), forURLScheme: "ankimedia")
        configuration.userContentController.add(context.coordinator, name: "fieldChanged")
        configuration.userContentController.addUserScript(WKUserScript(source: "window.reportField=()=>window.webkit.messageHandlers.fieldChanged.postMessage(document.getElementById('field').innerHTML);document.addEventListener('input',window.reportField);", injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        context.coordinator.value = text
        context.coordinator.label = label
        context.coordinator.fontName = fontName
        context.coordinator.fontSize = fontSize
        context.coordinator.rtl = rtl
        commands.webView = view
        // Note HTML is data: CSP prevents its script/event handlers from running.
        view.loadHTMLString("""
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src ankimedia: data: https:; media-src ankimedia: data:; style-src 'unsafe-inline'"><style>:root{color-scheme:light dark}body{margin:8px;font:20px -apple-system;overflow-wrap:anywhere}#field{min-height:140px;outline:none}img{max-width:100%;height:auto}</style></head><body><div id="field" contenteditable="true" role="textbox" aria-multiline="true"></div></body></html>
        """, baseURL: URL(string: "ankimedia://collection/"))
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.text = $text
        guard text != context.coordinator.value else { return }
        context.coordinator.value = text
        context.coordinator.apply(view)
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "fieldChanged")
        view.stopLoading()
    }
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var text: Binding<String>
        var value = ""
        var label = ""
        var fontName = "Arial"
        var fontSize = 20
        var rtl = false
        init(text: Binding<String>) { self.text = text }
        func apply(_ view: WKWebView) {
            guard let data = try? JSONSerialization.data(withJSONObject: [value, label, fontName, fontSize, rtl]), let args = String(data: data, encoding: .utf8) else { return }
            view.evaluateJavaScript("(()=>{const [html,label,font,size,rtl]=\(args);const field=document.getElementById('field');if(field.innerHTML!==html)field.innerHTML=html;field.setAttribute('aria-label',label);field.style.fontFamily=font;field.style.fontSize=size+'px';field.dir=rtl?'rtl':'ltr';})();", completionHandler: nil)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { apply(webView) }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let html = message.body as? String else { return }
            value = html
            text.wrappedValue = html
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(action.navigationType == .other && ["about", "ankimedia"].contains(action.request.url?.scheme ?? "") ? .allow : .cancel)
        }
    }
}
