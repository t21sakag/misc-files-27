import Foundation

extension Engine {
    /// Use the engine's exact LaTeX media names, matching desktop-generated
    /// media and AnkiDroid. This does not run a TeX compiler on the device.
    func templateAV(_ html: String, questionSide: Bool, latexSVG: Bool) throws -> [String: Any] {
        var text = html
        if html.range(of: #"\[(?:latex|\$)"#, options: [.regularExpression, .caseInsensitive]) != nil {
            text = try call("CardRenderingService.ExtractLatex", ["text": html, "svg": latexSVG, "expandClozes": false])["text"] as? String ?? html
        }
        return try call("CardRenderingService.ExtractAvTags", ["text": text, "questionSide": questionSide])
    }
}
