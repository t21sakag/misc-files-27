import SwiftUI
import GameController

struct ReviewGamepadInput: UIViewRepresentable {
    let enabled: Bool
    let pressed: (ReviewGamepadButton) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView {
        context.coordinator.start()
        return UIView(frame: .zero)
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.enabled = enabled
        context.coordinator.pressed = pressed
    }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.stop() }
    @MainActor final class Coordinator {
        var enabled = false
        var pressed: ((ReviewGamepadButton) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var controllers: [ObjectIdentifier: GCController] = [:]
        private func inputs(_ controller: GCController) -> [(ReviewGamepadButton, GCControllerButtonInput)] {
            guard let pad = controller.extendedGamepad else { return [] }
            return [(.a, pad.buttonA), (.b, pad.buttonB), (.x, pad.buttonX), (.y, pad.buttonY),
                (.up, pad.dpad.up), (.down, pad.dpad.down), (.left, pad.dpad.left), (.right, pad.dpad.right),
                (.leftShoulder, pad.leftShoulder), (.rightShoulder, pad.rightShoulder), (.leftTrigger, pad.leftTrigger), (.rightTrigger, pad.rightTrigger)]
        }
        func start() {
            guard observers.isEmpty else { return }
            observers.append(NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { if let controller = note.object as? GCController { self?.attach(controller) } }
            })
            observers.append(NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { if let controller = note.object as? GCController { self?.detach(controller) } }
            })
            for controller in GCController.controllers() { attach(controller) }
        }
        private func attach(_ controller: GCController) {
            guard controllers[ObjectIdentifier(controller)] == nil, controller.extendedGamepad != nil else { return }
            controllers[ObjectIdentifier(controller)] = controller
            controller.handlerQueue = .main
            for (button, input) in inputs(controller) {
                input.pressedChangedHandler = { [weak self] _, _, isPressed in
                    guard isPressed else { return }
                    MainActor.assumeIsolated {
                        guard let self, self.enabled else { return }
                        self.pressed?(button)
                    }
                }
            }
        }
        private func detach(_ controller: GCController) {
            for (_, input) in inputs(controller) { input.pressedChangedHandler = nil }
            controllers.removeValue(forKey: ObjectIdentifier(controller))
        }
        func stop() {
            enabled = false; pressed = nil
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
            for controller in Array(controllers.values) { detach(controller) }
        }
    }
}
