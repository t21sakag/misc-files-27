import Foundation

/// Display-only sizes. Stored note HTML, template CSS and user percentages are
/// separate from the reading baseline applied by the iPad interface.
enum StudyTypography {
    static func editorFontSize(authored: Int, override: Int, dynamicScale: Double) -> Double {
        let base = override > 0 ? override : max(24, authored)
        let scale = dynamicScale.isFinite && dynamicScale > 0 ? dynamicScale : 1
        return Double(base) * scale
    }

    static func cardTextScale(dynamicScale: Double) -> Double {
        let scale = dynamicScale.isFinite && dynamicScale > 0 ? dynamicScale : 1
        return 1.25 * scale
    }

    static func cardReadingCSS(dynamicScale: Double) -> String {
        let percentage = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), 100 * cardTextScale(dynamicScale: dynamicScale))
        return """
        html, body, #qa { -webkit-text-size-adjust: \(percentage)%; text-size-adjust: \(percentage)%; }
        #qa { line-height: 1.5; }
        """
    }
}
