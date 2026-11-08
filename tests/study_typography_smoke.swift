import Foundation

@main struct StudyTypographySmoke {
    static func main() {
        let scale = 19.0 / 17.0
        precondition(abs(StudyTypography.editorFontSize(authored: 20, override: 0, dynamicScale: scale) - 26.823529) < 0.001)
        precondition(StudyTypography.editorFontSize(authored: 36, override: 0, dynamicScale: 1) == 36)
        precondition(StudyTypography.editorFontSize(authored: 36, override: 18, dynamicScale: 1) == 18)
        precondition(StudyTypography.editorFontSize(authored: -1, override: 0, dynamicScale: 1) == 24)
        precondition(StudyTypography.editorFontSize(authored: 20, override: 0, dynamicScale: .nan) == 24)
        precondition(abs(20 * StudyTypography.cardTextScale(dynamicScale: scale) - 27.941176) < 0.001)
        let css = StudyTypography.cardReadingCSS(dynamicScale: scale)
        precondition(css.contains("139.706%"))
        precondition(!css.contains("font-size:") && !css.contains("zoom:"), "Card text adjustment must preserve authored font hierarchy and image sizing")
        precondition(StudyTypography.cardReadingCSS(dynamicScale: .infinity).contains("125.000%"))
        print("PASS: reading baseline scales editor text, preserves explicit and larger authored sizes, handles invalid scale and emits text-only card adjustment")
    }
}
