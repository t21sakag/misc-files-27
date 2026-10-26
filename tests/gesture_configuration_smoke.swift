import Foundation

@main struct GestureConfigurationSmoke {
    static func main() throws {
        let defaults = ReviewGestureConfiguration.load(Data("invalid".utf8))
        precondition(defaults.action(x: -200, y: 0) == .flipOrGood)
        precondition(defaults.action(x: 200, y: 0) == .flipOrAgain)
        precondition(defaults.action(x: 0, y: -200) == .none)
        precondition(defaults.action(x: -5, y: 0) == .none)
        precondition(defaults.action(x: 200, y: 200) == .none)
        var configured = defaults
        configured.up = .user9
        configured.left = .hint
        configured.right = .flag7
        configured.down = .edit
        configured.distance = 100
        let restored = ReviewGestureConfiguration.load(try JSONEncoder().encode(configured))
        precondition(restored.action(x: 0, y: -140) == .user9)
        precondition(restored.action(x: -140, y: 0) == .hint)
        precondition(restored.action(x: 140, y: 0) == .flag7)
        precondition(restored.action(x: 0, y: 140) == .edit)
        precondition(restored.action(x: 80, y: 0) == .none)
        configured.distance = -100
        precondition(configured.minimumDistance == 20)
        configured.distance = 1_000
        precondition(configured.minimumDistance == 180)
        var keyboard = ReviewKeyboardConfiguration.load(Data("invalid".utf8))
        precondition(keyboard.action(for: .space) == .flipOrGood)
        precondition(keyboard.action(for: .four) == .easy)
        precondition(keyboard.action(for: .control7) == .flag7)
        keyboard.actions[ReviewKey.space.rawValue] = ReviewGestureAction.none
        keyboard.actions[ReviewKey.r.rawValue] = .user9
        let restoredKeyboard = ReviewKeyboardConfiguration.load(try JSONEncoder().encode(keyboard))
        precondition(restoredKeyboard.action(for: .space) == .none)
        precondition(restoredKeyboard.action(for: .r) == .user9)
        precondition(restoredKeyboard.action(for: .enter) == .flipOrGood)
        precondition(Set(ReviewKey.allCases.map(\.rawValue)).count == ReviewKey.allCases.count)
        var gamepad = ReviewGamepadConfiguration.load(Data("invalid".utf8))
        precondition(!gamepad.enabled)
        precondition(gamepad.action(for: .a) == .flipOrGood)
        gamepad.enabled = true
        gamepad.actions[ReviewGamepadButton.a.rawValue] = ReviewGestureAction.none
        gamepad.actions[ReviewGamepadButton.leftTrigger.rawValue] = .user9
        let restoredGamepad = ReviewGamepadConfiguration.load(try JSONEncoder().encode(gamepad))
        precondition(restoredGamepad.enabled)
        precondition(restoredGamepad.action(for: .a) == .none)
        precondition(restoredGamepad.action(for: .leftTrigger) == .user9)
        precondition(restoredGamepad.action(for: .rightShoulder) == .replay)
        var touch = ReviewTouchConfiguration()
        touch.question["0"] = .showAnswer
        touch.answer["8"] = .good
        precondition(touch.action(x: 0, y: 0, revealed: false) == .none)
        touch.enabled = true
        let restoredTouch = ReviewTouchConfiguration.load(try JSONEncoder().encode(touch))
        precondition(restoredTouch.action(x: 0, y: 0, revealed: false) == .showAnswer)
        precondition(restoredTouch.action(x: 1, y: 1, revealed: true) == .good)
        precondition(restoredTouch.action(x: 0, y: 0, revealed: true) == .none)
        precondition(restoredTouch.action(x: .nan, y: 0, revealed: false) == .none)
        precondition(restoredTouch.action(x: -0.1, y: 0, revealed: false) == .none)
        var toolbar = ReviewToolbarConfiguration()
        toolbar.enabled = true
        toolbar.items = [ReviewToolbarItem(action: .user9), ReviewToolbarItem(action: .recordVoice)]
        let restoredToolbar = ReviewToolbarConfiguration.load(try JSONEncoder().encode(toolbar))
        precondition(restoredToolbar.enabled)
        precondition(restoredToolbar.items.map(\.action) == [.user9, .recordVoice])
        precondition(restoredToolbar.items.map(\.id) == toolbar.items.map(\.id))
        toolbar.items.append(toolbar.items[0])
        let invalidToolbarData = try JSONEncoder().encode(toolbar)
        precondition(!ReviewToolbarConfiguration.load(invalidToolbarData).enabled)
        print("PASS: toolbar order/identity persistence and duplicate identity fallback")
        print("PASS: touch zone side separation, boundaries, invalid coordinates and persistence")
        print("PASS: gamepad assignments, opt-in and explicit disabled binding serialization")
        print("PASS: keyboard assignment serialization, explicit disabled binding and defaults")
        print("PASS: actual gesture configuration serialization + assignments + direction/threshold + malformed settings fallback")
    }
}
