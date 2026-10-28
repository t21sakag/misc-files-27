import Foundation

@main struct StudyThemeSmoke {
    static func main() {
        precondition(StudyTheme.resolve(dark: false, day: "1", night: "3") == .light)
        precondition(StudyTheme.resolve(dark: false, day: "2", night: "4") == .plain)
        precondition(StudyTheme.resolve(dark: false, day: "3", night: "3") == .eink)
        precondition(StudyTheme.resolve(dark: true, day: "3", night: "3") == .black)
        precondition(StudyTheme.resolve(dark: true, day: "1", night: "4") == .dark)
        precondition(StudyTheme.resolve(dark: false, day: "invalid", night: "invalid") == .light)
        precondition(StudyTheme.resolve(dark: true, day: "invalid", night: "invalid") == .black)
        precondition(StudyTheme.dark.cardClasses == "night_mode nightMode ankidroid_dark_mode")
        precondition(StudyTheme.black.cardClasses == "night_mode nightMode")
        precondition(StudyTheme.plain.cardClasses == "ankidroid_plain_mode")
        precondition(StudyTheme.eink.cardClasses.isEmpty)
        print("PASS: day/night resolution, defaults, invalid values and upstream card selectors")
    }
}
