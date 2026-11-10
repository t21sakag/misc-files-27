import Foundation

extension Engine {
    /// The whole lookup/validation/add sequence is one synchronous actor turn.
    /// AddDeck alone silently appends "+" to an existing name, unlike the dialog.
    func createDeckForSelection(_ rawName: String, parentID: String? = nil) throws -> String {
        guard !rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EngineError(message: AppText.localized("名前を入力してください。"))
        }
        var name = rawName
        if let parentID {
            guard !rawName.replacingOccurrences(of: "\"", with: "").isEmpty else {
                throw EngineError(message: AppText.localized("名前を入力してください。"))
            }
            let parent = try call("DecksService.GetDeck", ["did": parentID])
            guard parent["filtered"] == nil, let parentName = parent["name"] as? String else {
                throw EngineError(message: AppText.localized("フィルターデッキの中には作成できません。"))
            }
            name = parentName + "::" + rawName
        }
        do {
            _ = try call("DecksService.GetDeckIdByName", ["val": name])
        } catch let error as EngineError where error.kind == 11 {
            // NotFound is the documented backend result for an absent name.
            // All other lookup errors propagate instead of allowing a write.
            var deck = try call("DecksService.NewDeck")
            deck["name"] = name
            guard let id = try call("DecksService.AddDeck", deck)["id"] as? String,
                  Int64(id).map({ $0 > 0 }) == true else {
                throw EngineError(message: AppText.localized("作成したデッキを確認できませんでした。"))
            }
            return id
        }
        throw EngineError(message: AppText.localized("同じ名前のデッキがあります。"))
    }
}
