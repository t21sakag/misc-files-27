#if DEBUG
import SwiftUI
import ObjectiveC

/// On-demand, read-only synthetic diagnostics: no timer, input, focus changes,
/// application state writes or user content. Native frames can be compared with AX/events.
@MainActor enum BrowserInputDiagnostics {
    private static var windowTraceInstalled = false
    private static var switchTouches: [ObjectIdentifier: (control: ObjectIdentifier, window: ObjectIdentifier, beganAt: TimeInterval)] = [:]
    private(set) static var lastSwitchEvent = "none"

    static func installWindowTrace() {
        guard !windowTraceInstalled, UITestIsolation.namespace() != nil,
              ProcessInfo.processInfo.arguments.contains("--uitest-browser-input-trace"),
              let original = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.sendEvent(_:))),
              let traced = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.browserInputSendEvent(_:))) else { return }
        method_exchangeImplementations(original, traced)
        windowTraceInstalled = true
    }

    static func recordWindowEvent(_ event: UIEvent, window: UIWindow, stage: String) {
        guard event.type == .touches else { return }
        for touch in event.allTouches ?? [] {
            let touchID = ObjectIdentifier(touch)
            let windowID = ObjectIdentifier(window)
            guard touch.window === window || switchTouches[touchID]?.window == windowID else { continue }
            var ancestor = touch.view
            var gestures: [String] = []
            var presses: [String] = []
            var control: UISwitch?
            while let current = ancestor {
                if let value = current as? UISwitch { control = value }
                for recognizer in current.gestureRecognizers ?? [] {
                    gestures.append("\(type(of: recognizer))=\(recognizer.state.rawValue)")
                    if let press = recognizer as? UILongPressGestureRecognizer {
                        presses.append("\(type(of: current)):min=\(press.minimumPressDuration),taps=\(press.numberOfTapsRequired),touches=\(press.numberOfTouchesRequired),move=\(press.allowableMovement)")
                    }
                }
                ancestor = current.superview
            }
            if touch.phase == .began, let control {
                switchTouches[touchID] = (ObjectIdentifier(control), windowID, touch.timestamp)
            }
            guard let tracked = switchTouches[touchID] else { continue }
            let current = control.map { String(describing: ObjectIdentifier($0)) } ?? "none"
            let on = control.map { String($0.isOn) } ?? "none"
            lastSwitchEvent = "stage=\(stage);touch=\(touchID);phase=\(touch.phase.rawValue);point=\(touch.location(in: window));initial=\(tracked.control);current=\(current);on=\(on);elapsed=\(touch.timestamp - tracked.beganAt);presses=\(presses.prefix(2).joined(separator: "|"));gestures=\(gestures.joined(separator: ","))"
            NSLog("browser.input.trace phase=window.touch %@", lastSwitchEvent)
            if stage == "after", touch.phase == .ended || touch.phase == .cancelled {
                switchTouches.removeValue(forKey: touchID)
            }
        }
    }

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
            for field in all.compactMap({ $0 as? UITextField }) where field.isFirstResponder {
                let selection = field.selectedTextRange.map { field.offset(from: $0.start, to: $0.end) } ?? -1
                result.append("textInput:class=\(name(field));id=\(ObjectIdentifier(field));length=\(field.text?.utf16.count ?? 0);selection=\(selection)")
            }
            for control in all.compactMap({ $0 as? UISwitch }) {
                let frame = control.convert(control.bounds, to: window)
                let center = CGPoint(x: frame.midX, y: frame.midY)
                let hit = window.hitTest(center, with: nil)
                let chain = ancestors(control)
                let hitChain = hit.map { ancestors($0).prefix(8).map(name).joined(separator: ">") } ?? "none"
                let gestures = chain.flatMap { $0.gestureRecognizers ?? [] }.map {
                    "\(String(describing: type(of: $0))):state=\($0.state.rawValue),enabled=\($0.isEnabled),cancels=\($0.cancelsTouchesInView)"
                }.joined(separator: ",")
                result.append("switch:frame=\(frame);control=\(ObjectIdentifier(control));on=\(control.isOn);enabled=\(control.isEnabled);interactive=\(chain.allSatisfy(\.isUserInteractionEnabled));hit=\(hitChain);gestures=\(gestures)")
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
        BrowserInputDiagnostics.installWindowTrace()
        if let observer = touchObserver { observer.view?.removeGestureRecognizer(observer) }
        touchObserver = nil
        guard let window, UITestIsolation.namespace() != nil,
              ProcessInfo.processInfo.arguments.contains("--uitest-browser-undo-trace") else { return }
        let observer = BrowserInputTouchObserver(target: nil, action: nil)
        observer.cancelsTouchesInView = false
        observer.delaysTouchesBegan = false
        observer.delaysTouchesEnded = false
        window.addGestureRecognizer(observer)
        touchObserver = observer
    }

    override var accessibilityValue: String? {
        get { readValue.map { $0() + "\nnativeTouches=" + (touchObserver?.summary ?? BrowserInputDiagnostics.lastSwitchEvent) } }
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

        }
        state = .failed
    }

}

private extension UIWindow {
    @objc dynamic func browserInputSendEvent(_ event: UIEvent) {
        BrowserInputDiagnostics.recordWindowEvent(event, window: self, stage: "before")
        // After the exchange this selector invokes UIKit's original method.
        browserInputSendEvent(event)
        BrowserInputDiagnostics.recordWindowEvent(event, window: self, stage: "after")
    }
}
#endif
