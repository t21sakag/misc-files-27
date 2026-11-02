#if DEBUG
import SwiftUI

/// On-demand, read-only synthetic diagnostics: no timer, input, focus changes,
/// state writes or user content. Native frames can be compared with AX/events.
@MainActor enum BrowserInputDiagnostics {
    static func read(loaded: Bool, busy: Bool, notes: Bool) -> String {
        func views(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap(views) }
        func name(_ view: UIView) -> String { String(describing: type(of: view)) }
        func ancestors(_ view: UIView) -> [UIView] {
            var result: [UIView] = [], current: UIView? = view
            while let value = current { result.append(value); current = value.superview }
            return result
        }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        var result = ["loaded=\(loaded);busy=\(busy);notes=\(notes)"]
        for (index, window) in windows.enumerated() where !window.isHidden {
            let all = views(window)
            let responder = all.first(where: \.isFirstResponder).map(name) ?? "none"
            result.append("window\(index):key=\(window.isKeyWindow);level=\(window.windowLevel.rawValue);responder=\(responder)")
            for control in all.compactMap({ $0 as? UISwitch }) {
                let frame = control.convert(control.bounds, to: window)
                let center = CGPoint(x: frame.midX, y: frame.midY)
                let hit = window.hitTest(center, with: nil)
                let chain = ancestors(control)
                let hitChain = hit.map { ancestors($0).prefix(8).map(name).joined(separator: ">") } ?? "none"
                let gestures = chain.flatMap { $0.gestureRecognizers ?? [] }.map {
                    "\(String(describing: type(of: $0))):state=\($0.state.rawValue),enabled=\($0.isEnabled),cancels=\($0.cancelsTouchesInView)"
                }.joined(separator: ",")
                result.append("switch:frame=\(frame);on=\(control.isOn);enabled=\(control.isEnabled);interactive=\(chain.allSatisfy(\.isUserInteractionEnabled));hit=\(hitChain);gestures=\(gestures)")
            }
        }
        return result.joined(separator: "\n")
    }
}

@MainActor struct BrowserInputDiagnosticsView: UIViewRepresentable {
    let readValue: () -> String
    func makeUIView(context: Context) -> BrowserInputDiagnosticsLabel {
        let label = BrowserInputDiagnosticsLabel()
        label.text = "Native browser input state"
        label.isUserInteractionEnabled = false
        label.isAccessibilityElement = true
        label.accessibilityTraits = .staticText
        label.accessibilityIdentifier = "browser-native-input-state"
        label.readValue = readValue
        return label
    }
    func updateUIView(_ view: BrowserInputDiagnosticsLabel, context: Context) { view.readValue = readValue }
    static func dismantleUIView(_ view: BrowserInputDiagnosticsLabel, coordinator: ()) { view.readValue = nil }
}

@MainActor final class BrowserInputDiagnosticsLabel: UILabel {
    var readValue: (() -> String)?
    override var accessibilityValue: String? {
        get { readValue?() }
        set { /* Read-only diagnostic. */ }
    }
}
#endif
