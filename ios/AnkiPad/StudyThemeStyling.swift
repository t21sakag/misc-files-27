import SwiftUI
import UIKit

extension StudyTheme {
    var selectedDeckBackground: Color {
        let white: Double
        switch self {
        case .light, .plain: white = 236
        case .eink: white = 224
        case .black: white = 26
        case .dark: white = 57
        }
        return Color(.sRGB, red: white / 255, green: white / 255, blue: white / 255, opacity: 1)
    }
    var nativeBackground: UIColor {
        switch self {
        case .black: .black
        case .dark: UIColor(white: 48.0 / 255, alpha: 1)
        case .light, .plain, .eink: .white
        }
    }
    var accent: Color {
        switch self {
        case .plain: Color(red: 96.0 / 255, green: 125.0 / 255, blue: 139.0 / 255)
        case .eink: .black
        case .light, .black, .dark: .blue
        }
    }
}

struct StudyThemeContainer<Content: View>: View {
    @AppStorage("dayTheme") private var day = "1"
    @AppStorage("nightTheme") private var night = "3"
    @AppStorage("safeDisplay") private var removeAnimations = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @ViewBuilder var content: () -> Content
    var body: some View {
        let theme = StudyTheme.resolve(dark: scheme == .dark, day: day, night: night)
        let motionDisabled = StudyMotionPolicy.disablesAnimations(appSetting: removeAnimations, systemReduceMotion: systemReduceMotion, theme: theme)
        content().tint(theme.accent)
            .background(Color(uiColor: theme.nativeBackground).ignoresSafeArea())
            .background(alignment: .bottomLeading) {
                #if DEBUG
                if UITestIsolation.namespace() != nil {
                    StudyMotionTransactionProbe(policyDisabled: motionDisabled).frame(width: 1, height: 1).allowsHitTesting(false)
                }
                #endif
            }
            .transaction { transaction in
                if motionDisabled {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
    }
}

private struct StudyThemeSurface: ViewModifier {
    @AppStorage("dayTheme") private var day = "1"
    @AppStorage("nightTheme") private var night = "3"
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let theme = StudyTheme.resolve(dark: scheme == .dark, day: day, night: night)
        content.scrollContentBackground(.hidden).background(Color(uiColor: theme.nativeBackground))
    }
}
extension View {
    func studyThemeSurface() -> some View { modifier(StudyThemeSurface()) }
}
