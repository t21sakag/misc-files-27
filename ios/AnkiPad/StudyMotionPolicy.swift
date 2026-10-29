import Foundation

enum StudyMotionPolicy {
    static func disablesAnimations(appSetting: Bool, systemReduceMotion: Bool, theme: StudyTheme) -> Bool {
        appSetting || systemReduceMotion || theme == .eink
    }
}
