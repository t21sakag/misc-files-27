import SwiftUI
import UIKit

extension StudyTheme {
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
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder var content: () -> Content
    var body: some View {
        let theme = StudyTheme.resolve(dark: scheme == .dark, day: day, night: night)
        content().tint(theme.accent)
            .background(Color(uiColor: theme.nativeBackground).ignoresSafeArea())
            .environment(\.colorSchemeContrast, theme == .eink ? .increased : contrast)
            .transaction { transaction in
                if theme == .eink { transaction.animation = nil; transaction.disablesAnimations = true }
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
