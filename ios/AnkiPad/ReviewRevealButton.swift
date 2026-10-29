import SwiftUI
import UIKit

struct ReviewRevealButton<Label: View>: View {
    let milliseconds: Int
    let enabled: Bool
    let cardKey: String
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    private var hold: Int { max(0, min(2000, milliseconds)) }

    var body: some View {
        Button { if hold == 0 { action() } } label: { label() }
            .disabled(!enabled)
            .overlay {
                if hold > 0 {
                    RevealHoldCapture(milliseconds: hold, enabled: enabled, cardKey: cardKey, action: action)
                }
            }
            .accessibilityAction { if enabled { action() } }
    }
}

private struct RevealHoldCapture: UIViewRepresentable {
    let milliseconds: Int
    let enabled: Bool
    let cardKey: String
    let action: () -> Void
    func makeUIView(context: Context) -> RevealHoldView { RevealHoldView() }
    func updateUIView(_ view: RevealHoldView, context: Context) {
        if view.cardKey != cardKey || view.milliseconds != milliseconds || !enabled { view.cancel() }
        view.cardKey = cardKey
        view.milliseconds = milliseconds
        view.action = action
        view.isUserInteractionEnabled = enabled
    }
    static func dismantleUIView(_ view: RevealHoldView, coordinator: ()) { view.cancel() }
}

private final class RevealHoldView: UIView {
    var cardKey = ""
    var milliseconds = 0
    var action: (() -> Void)?
    private var pending: Task<Void, Never>?
    private var holding = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancel()
        guard touches.count == 1, let touch = touches.first, bounds.contains(touch.location(in: self)) else { return }
        holding = true
        let delay = milliseconds
        pending = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000) }
            catch { return }
            guard let self, self.holding, self.isUserInteractionEnabled, self.window != nil, !Task.isCancelled else { return }
            self.holding = false
            self.action?()
        }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if touches.contains(where: { !bounds.contains($0.location(in: self)) }) { cancel() }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { cancel() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { cancel() }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { cancel() } }
    func cancel() { pending?.cancel(); pending = nil; holding = false }
}
