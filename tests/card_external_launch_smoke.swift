import Foundation

@main struct CardExternalLaunchSmoke {
    static func main() {
        for allowed in [false, true] {
            for raw in ["http://example.test", "https://example.test/path", "HTTPS://example.test"] {
                precondition(CardExternalLaunchPolicy.decision(for: URL(string: raw)!, allowed: allowed) == .browser)
            }
            for raw in ["file:///private/data", "content://contacts/1", "javascript:alert(1)", "data:text/html,test", "blob:https://example.test/id", "intent://test", "android-app://test", "ankimedia://collection/test", "ankibundle://backend/test", "ankiplay://q/0", "about:blank", "relative-path"] {
                precondition(CardExternalLaunchPolicy.decision(for: URL(string: raw)!, allowed: allowed) == .unsupported)
            }
            for raw in ["mailto:fixture@example.test", "maps://?q=fixture", "app-settings:", "custom-study-app://note/1"] {
                precondition(CardExternalLaunchPolicy.decision(for: URL(string: raw)!, allowed: allowed) == (allowed ? .application : .denied))
            }
        }
        print("PASS: web links, opt-in app schemes, unsupported/private routes and relative URLs")
    }
}
