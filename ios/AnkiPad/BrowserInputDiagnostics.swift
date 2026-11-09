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
    var identifier = "browser-native-input-state"
    let readValue: () -> String
    func makeUIView(context: Context) -> BrowserInputDiagnosticsLabel {
        let label = BrowserInputDiagnosticsLabel()
        label.text = "Native browser input state"
        label.isUserInteractionEnabled = false
        label.isAccessibilityElement = true
        label.accessibilityTraits = .staticText
        label.accessibilityIdentifier = identifier
        label.readValue = readValue
        return label
    }
    func updateUIView(_ view: BrowserInputDiagnosticsLabel, context: Context) { view.readValue = readValue }
    static func dismantleUIView(_ view: BrowserInputDiagnosticsLabel, coordinator: ()) { view.readValue = nil }
}

@MainActor final class BrowserInputDiagnosticsLabel: UILabel {
    var readValue: (() -> String)?
    private var touchObserver: BrowserInputTouchObserver?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let observer = touchObserver { observer.view?.removeGestureRecognizer(observer) }
        touchObserver = nil
        guard let window, UITestIsolation.namespace() != nil,
              (ProcessInfo.processInfo.arguments.contains("--uitest-browser-undo-trace")
               || ProcessInfo.processInfo.arguments.contains("--uitest-browser-input-trace")) else { return }
        let observer = BrowserInputTouchObserver(target: nil, action: nil)
        observer.cancelsTouchesInView = false
        observer.delaysTouchesBegan = false
        observer.delaysTouchesEnded = false
        window.addGestureRecognizer(observer)
        touchObserver = observer
    }

    override var accessibilityValue: String? {
        get { readValue.map { $0() + "\nnativeTouches=" + (touchObserver?.summary ?? "unavailable") } }
        set { /* Read-only diagnostic. */ }
    }
}

/// Records delivery without recognizing, delaying or cancelling an input.
/// A failed observer leaves the native control's gesture arbitration intact.
@MainActor private final class BrowserInputTouchObserver: UIGestureRecognizer {
    private(set) var summary = "none"
    private var receivedCount = 0

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        receivedCount += touches.count
        if let touch = touches.first {
            let point = touch.location(in: view)
            let target = touch.view.map { String(describing: type(of: $0)) } ?? "none"
            summary = "observer=\(ObjectIdentifier(self));count=\(receivedCount);point=\(point);target=\(target);type=\(touch.type.rawValue)"
            let prefix = ProcessInfo.processInfo.arguments.contains("--uitest-browser-undo-trace")
                ? "browser.undo.trace" : "browser.input.trace"
            NSLog("%@ phase=native.touch %@", prefix, summary)
            var ancestor = touch.view
            while let current = ancestor, !(current is UISwitch) { ancestor = current.superview }
            if let control = ancestor as? UISwitch {
                // Observe the actual control reached by this input. Replacing
                // our registration avoids duplicate callbacks on later taps.
                control.removeTarget(self, action: #selector(controlEvent(_:event:)), for: .allEvents)
                control.addTarget(self, action: #selector(controlEvent(_:event:)),
                                  for: [.touchDown, .touchUpInside, .touchUpOutside, .touchCancel, .valueChanged])
                NSLog("%@ phase=switch.delivery observer=%@ on=%@ frame=%@", prefix,
                      String(describing: ObjectIdentifier(self)), String(control.isOn),
                      String(describing: control.convert(control.bounds, to: view)))
            }
        }
        state = .failed
    }

    @objc private func controlEvent(_ control: UISwitch, event: UIEvent?) {
        let phases = event?.allTouches?.map { String($0.phase.rawValue) }.sorted().joined(separator: ",") ?? "none"
        NSLog("browser.input.trace phase=switch.event observer=%@ on=%@ phases=%@ tracking=%@",
              String(describing: ObjectIdentifier(self)), String(control.isOn), phases, String(control.isTracking))
    }
}
#endif
