import Foundation

struct TemplatePreview {
    let question: String
    let answer: String
    let css: String
    let questionAV: [[String: Any]]
    let answerAV: [[String: Any]]
}
extension Engine {
    func noteType(_ id: String) throws -> [String: Any] { try call("NotetypesService.GetNotetype", ["ntid": id]) }
    func saveNoteType(_ value: [String: Any]) throws { try backup(); _ = try call("NotetypesService.UpdateNotetype", value) }
    func deleteNoteType(_ id: String) throws { try backup(); _ = try call("NotetypesService.RemoveNotetype", ["ntid": id]) }
    func copyNoteType(_ id: String, name: String) throws {
        var value = try noteType(id)
        value["id"] = "0"
        value["name"] = name
        _ = try call("NotetypesService.AddNotetype", value)
    }
    func addStockNoteType(name: String, kind: String) throws {
        let response = try call("NotetypesService.GetStockNotetypeLegacy", ["kind": kind])
        guard let encoded = response["json"] as? String, let data = Data(base64Encoded: encoded),
              var legacy = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw EngineError(message: AppText.localized("ノートタイプを作成できませんでした。")) }
        legacy["name"] = name
        legacy["id"] = 0
        let encodedNew = try JSONSerialization.data(withJSONObject: legacy).base64EncodedString()
        _ = try call("NotetypesService.AddNotetypeLegacy", ["json": encodedNew])
    }
    func templatePreview(typeID: String, ordinal: Int, document: NoteDocument? = nil) throws -> TemplatePreview {
        let schema = try noteType(typeID)
        let templates = schema["templates"] as? [[String: Any]] ?? []
        let isCloze = (schema["config"] as? [String: Any])?["kind"] as? String == "KIND_CLOZE"
        let templateIndex = isCloze ? 0 : ordinal
        guard ordinal >= 0, templates.indices.contains(templateIndex) else { throw EngineError(message: AppText.localized("テンプレートが見つかりません。")) }
        let result = try call("SearchService.SearchNotes", ["search": "mid:" + typeID])
        var note: [String: Any]
        if let document {
            note = document.raw
            note["fields"] = document.fields
            note["tags"] = document.tags.split(whereSeparator: \.isWhitespace).map(String.init)
        } else if let id = (result["ids"] as? [String])?.first { note = try call("NotesService.GetNote", ["nid": id]) }
        else {
            note = try call("NotesService.NewNote", ["ntid": typeID])
            let cloze = (schema["config"] as? [String: Any])?["kind"] as? String == "KIND_CLOZE"
            note["fields"] = (schema["fields"] as? [[String: Any]] ?? []).map { field in
                let name = field["name"] as? String ?? ""
                return cloze ? "{{c1::" + name + "}}" : name
            }
        }
        let rendered = try call("CardRenderingService.RenderUncommittedCard", ["note": note, "cardOrd": ordinal, "template": templates[templateIndex], "fillEmpty": true])
        func html(_ key: String, front: String? = nil) throws -> String { try TemplateNodeText.render(rendered[key] as? [[String: Any]] ?? [], frontSide: front) }
        let latexSVG = (schema["config"] as? [String: Any])?["latexSvg"] as? Bool ?? false
        let question = try templateAV(html("questionNodes"), questionSide: true, latexSVG: latexSVG)
        let answer = try templateAV(html("answerNodes", front: question["text"] as? String ?? ""), questionSide: false, latexSVG: latexSVG)
        return TemplatePreview(question: question["text"] as? String ?? "", answer: answer["text"] as? String ?? "",
            css: rendered["css"] as? String ?? "", questionAV: question["avTags"] as? [[String: Any]] ?? [], answerAV: answer["avTags"] as? [[String: Any]] ?? [])
    }
}
