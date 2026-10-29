import SwiftUI
import UIKit

@MainActor enum StudyMotion {
    static func allowsAnimations(in controller: UIViewController) -> Bool {
        let defaults = UserDefaults.standard
        let theme = StudyTheme.resolve(dark: controller.traitCollection.userInterfaceStyle == .dark,
                                       day: defaults.string(forKey: "dayTheme") ?? "1",
                                       night: defaults.string(forKey: "nightTheme") ?? "3")
        return !StudyMotionPolicy.disablesAnimations(appSetting: defaults.bool(forKey: "safeDisplay"),
                                                     systemReduceMotion: UIAccessibility.isReduceMotionEnabled, theme: theme)
    }
    static func present(_ controller: UIViewController, from presenter: UIViewController, completion: (() -> Void)? = nil) {
        presenter.present(controller, animated: allowsAnimations(in: presenter), completion: completion)
        #if DEBUG
        if UITestIsolation.namespace() != nil {
            StudyMotionProbe.lastPresentation = controller.transitionCoordinator?.isAnimated == true ? "animated" : "none"
            NotificationCenter.default.post(name: StudyMotionProbe.changed, object: nil)
        }
        #endif
    }
    static func dismiss(_ controller: UIViewController, completion: (() -> Void)? = nil) {
        controller.dismiss(animated: allowsAnimations(in: controller), completion: completion)
    }
}

#if DEBUG
/// Read-only observation of the actual SwiftUI transaction and UIKit transition.
struct StudyMotionTransactionProbe: UIViewRepresentable {
    let policyDisabled: Bool
    func makeUIView(context: Context) -> StudyMotionProbe { StudyMotionProbe() }
    func updateUIView(_ view: StudyMotionProbe, context: Context) {
        view.policyDisabled = policyDisabled
        view.transactionDisabled = context.transaction.disablesAnimations
        view.hasAnimation = context.transaction.animation != nil
        view.refresh()
    }
}

final class StudyMotionProbe: UIView {
    static let changed = Notification.Name("StudyMotionPresentationChanged")
    static var lastPresentation = "unobserved"
    var policyDisabled = false
    var transactionDisabled = false
    var hasAnimation = false
    private var observer: NSObjectProtocol?
    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityIdentifier = "motion-transaction"
        accessibilityLabel = "Motion observation"
        isUserInteractionEnabled = false
        observer = NotificationCenter.default.addObserver(forName: Self.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    func refresh() {
        accessibilityValue = "policy=\(policyDisabled ? "disabled" : "normal");transaction=\(transactionDisabled ? "disabled" : "normal");animation=\(hasAnimation ? "set" : "none");presentation=\(Self.lastPresentation);system=\(UIAccessibility.isReduceMotionEnabled ? "reduced" : "normal")"
    }
}
#endif
