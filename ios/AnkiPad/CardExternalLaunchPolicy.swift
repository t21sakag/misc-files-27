import Foundation

enum CardExternalLaunchPolicy {
    enum Decision: Equatable { case browser, application, denied, unsupported }

    // Classify dispatch to another app, not resources loaded inside WebKit.
    static func decision(for url: URL, allowed: Bool) -> Decision {
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else { return .unsupported }
        if ["http", "https"].contains(scheme) { return .browser }
        // Never send private files, executable documents or Android intents to
        // a system URL handler. Internal media routes are handled by the view.
        if ["file", "content", "javascript", "data", "blob", "intent", "android-app", "ankimedia", "ankibundle", "ankiplay", "about"].contains(scheme) {
            return .unsupported
        }
        return allowed ? .application : .denied
    }
}
