#if DEBUG
import SwiftUI
import UIKit

/// Observe hit testing only in synthetic UI runs. Never sends an event,
/// changes a control, or reads labels/fields/searches/account information.
struct BrowserOptionsHitProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ uiView: ProbeView, context: Context) {}
    static func dismantleUIView(_ uiView: ProbeView, coordinator: ()) { uiView.stop() }

    final class ProbeView: UIView {
        private var timer: Timer?
        private var remaining = 30
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            stop()
            guard window != nil, UITestIsolation.namespace() != nil else { return }
            remaining = 30
            let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.sample() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        func stop() { timer?.invalidate(); timer = nil }
        private func sample() {
            guard remaining > 0, let window else { stop(); return }
            remaining -= 1
            var pending: [UIView] = [window]
            var visited = 0
            var switches = 0
            while let view = pending.popLast(), visited < 4096, switches < 12 {
                visited += 1
                pending.append(contentsOf: view.subviews)
                guard let control = view as? UISwitch else { continue }
                switches += 1
                let frame = control.convert(control.bounds, to: window)
                let point = CGPoint(x: frame.midX, y: frame.midY)
                let hit = window.hitTest(point, with: nil)
                let within = hit.map { $0 === control || $0.isDescendant(of: control) } ?? false
                let hitClass = hit.map { String(NSStringFromClass(type(of: $0)).prefix(128)) } ?? "nil"
                NSLog("browser.options.trace phase=hit.sample sample=%d switch=%d x=%.2f y=%.2f width=%.2f height=%.2f on=%d enabled=%d interactive=%d hidden=%d alpha=%.2f hitWithinSwitch=%d hitClass=%@",
                      30 - remaining, switches, Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height),
                      control.isOn ? 1 : 0, control.isEnabled ? 1 : 0, control.isUserInteractionEnabled ? 1 : 0,
                      control.isHidden ? 1 : 0, Double(control.alpha), within ? 1 : 0, hitClass)
            }
            NSLog("browser.options.trace phase=hit.summary sample=%d visited=%d switches=%d", 30 - remaining, visited, switches)
            if remaining == 0 { stop() }
        }
    }
}
#endif
