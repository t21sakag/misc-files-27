import Foundation

/// Like AnkiDroid TemplateManager.applyCustomFilters: unknown add-on filters
/// leave the backend's currentText intact; FrontSide uses the processed front.
enum TemplateNodeText {
    static func render(_ nodes: [[String: Any]], frontSide: String? = nil) throws -> String {
        try nodes.map { node in
            if let text = node["text"] as? String { return text }
            guard let replacement = node["replacement"] as? [String: Any] else {
                throw NSError(domain: "TemplateNodeText", code: 1, userInfo: [NSLocalizedDescriptionKey: AppText.localized("テンプレートの描画結果を読み取れませんでした。")])
            }
            if replacement["fieldName"] as? String == "FrontSide", let frontSide { return frontSide }
            // Protobuf JSON omits currentText when the field is empty.
            return replacement["currentText"] as? String ?? ""
        }.joined()
    }
}
